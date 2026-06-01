%%%-------------------------------------------------------------------
%%% @doc Tree navigation and viewport helpers.
%%% @end
%%%-------------------------------------------------------------------
-module(iso_tree_nav).

-include("iso_elements.hrl").

-export([flatten_visible/1, visible_nodes/2, resolved_height/2, row_node/3]).
-export([navigate/3, navigate/4, scroll/4, toggle/3, toggle_selected/2, select/3]).

%%====================================================================
%% Public API
%%====================================================================

-spec flatten_visible(#tree{}) -> [{non_neg_integer(), boolean(), #tree_node{}}].
flatten_visible(#tree{nodes = Nodes}) ->
    lists:reverse(flatten_nodes(Nodes, 0, [])).

-spec visible_nodes(#tree{}, #bounds{}) -> [{non_neg_integer(), boolean(), #tree_node{}}].
visible_nodes(Tree = #tree{offset = Offset}, Bounds) ->
    VisibleHeight = resolved_height(Tree, Bounds),
    NumNodes = count_visible_nodes(Tree#tree.nodes),
    SafeOffset = clamp_offset(Offset, NumNodes, VisibleHeight),
    collect_visible_nodes(Tree#tree.nodes, 0, SafeOffset, SafeOffset + VisibleHeight, 0, []).

-spec resolved_height(#tree{}, #bounds{}) -> non_neg_integer().
resolved_height(#tree{height = fill, y = Y}, Bounds) ->
    max(1, Bounds#bounds.height - Y);
resolved_height(#tree{height = auto, nodes = Nodes, y = Y}, Bounds) ->
    min(count_visible_nodes(Nodes), max(0, Bounds#bounds.height - Y));
resolved_height(#tree{height = Height, y = Y}, Bounds) when is_integer(Height) ->
    min(Height, max(0, Bounds#bounds.height - Y)).

-spec row_node(#tree{}, #bounds{}, pos_integer()) -> {ok, term()} | not_found.
row_node(Tree, Bounds, Row) when Row >= 1 ->
    case nth_visible_node(Row, visible_nodes(Tree, Bounds)) of
        #tree_node{id = Id} -> {ok, Id};
        false -> not_found
    end;
row_node(_, _, _) ->
    not_found.

-spec navigate(up | down, #tree{}, #bounds{}) -> #tree{}.
navigate(_Dir, #tree{nodes = []} = Tree, _Bounds) ->
    Tree#tree{selected = undefined, offset = 0};
navigate(Dir, Tree = #tree{selected = Selected}, Bounds) ->
    navigate(Dir, 1, max(1, resolved_height(Tree, Bounds)), Tree#tree{selected = Selected}).

-spec navigate(up | down, pos_integer(), pos_integer(), #tree{}) -> #tree{}.
navigate(_Dir, _Lines, _VisibleHeight, #tree{nodes = []} = Tree) ->
    Tree#tree{selected = undefined, offset = 0};
navigate(Dir, Lines, VisibleHeight, Tree = #tree{selected = Selected}) ->
    FlatIds = visible_ids(Tree),
    case FlatIds of
        [] ->
            Tree#tree{selected = undefined, offset = 0};
        _ ->
            CurrentIdx = selected_index(Selected, FlatIds),
            SafeLines = max(1, Lines),
            NewIdx = case Dir of
                up when CurrentIdx =< 1 -> 1;
                up -> max(1, CurrentIdx - SafeLines);
                down when CurrentIdx =:= 0 -> 1;
                down -> min(length(FlatIds), CurrentIdx + SafeLines)
            end,
            ensure_visible_with_height(
                Tree#tree{selected = lists:nth(NewIdx, FlatIds)},
                max(1, VisibleHeight))
    end.

-spec scroll(up | down, pos_integer(), pos_integer(), #tree{}) -> #tree{}.
scroll(_Dir, _Lines, _VisibleHeight, #tree{nodes = []} = Tree) ->
    Tree#tree{offset = 0};
scroll(Dir, Lines, VisibleHeight, Tree = #tree{nodes = Nodes, offset = Offset}) ->
    NumNodes = count_visible_nodes(Nodes),
    SafeLines = max(1, Lines),
    SafeVisibleHeight = max(1, VisibleHeight),
    NewOffset = case Dir of
        up -> Offset - SafeLines;
        down -> Offset + SafeLines
    end,
    Tree#tree{offset = clamp_offset(NewOffset, NumNodes, SafeVisibleHeight)}.

-spec toggle(left | right, #tree{}, #bounds{}) -> #tree{}.
toggle(_Dir, #tree{nodes = []} = Tree, _Bounds) ->
    Tree#tree{selected = undefined, offset = 0};
toggle(left, Tree = #tree{selected = Selected, nodes = Nodes}, Bounds) ->
    case find_node(Nodes, Selected, undefined) of
        {ok, #tree_node{children = [_ | _], expanded = true} = Node, _ParentId} ->
            NewNodes = replace_node(Nodes, Selected, Node#tree_node{expanded = false}),
            ensure_visible(Tree#tree{nodes = NewNodes}, Bounds);
        {ok, _Node, undefined} ->
            ensure_visible(Tree, Bounds);
        {ok, _Node, ParentId} ->
            ensure_visible(Tree#tree{selected = ParentId}, Bounds);
        not_found ->
            Tree
    end;
toggle(right, Tree = #tree{selected = Selected, nodes = Nodes}, Bounds) ->
    case find_node(Nodes, Selected, undefined) of
        {ok, #tree_node{children = [#tree_node{} | _], expanded = false} = Node,
         _ParentId} ->
            NewNodes = replace_node(Nodes, Selected, Node#tree_node{expanded = true}),
            ensure_visible(Tree#tree{nodes = NewNodes}, Bounds);
        {ok, #tree_node{children = [#tree_node{id = FirstChildId} | _], expanded = true},
         _ParentId} ->
            ensure_visible(Tree#tree{selected = FirstChildId}, Bounds);
        not_found ->
            case visible_ids(Tree) of
                [FirstId | _] -> ensure_visible(Tree#tree{selected = FirstId}, Bounds);
                [] -> Tree#tree{selected = undefined, offset = 0}
            end;
        _ ->
            Tree
    end.

-spec toggle_selected(#tree{}, #bounds{}) -> #tree{}.
toggle_selected(#tree{nodes = []} = Tree, _Bounds) ->
    Tree#tree{selected = undefined, offset = 0};
toggle_selected(Tree = #tree{selected = Selected, nodes = Nodes}, Bounds) ->
    case find_node(Nodes, Selected, undefined) of
        {ok, #tree_node{children = []}, _ParentId} ->
            ensure_visible(Tree, Bounds);
        {ok, #tree_node{expanded = Expanded} = Node, _ParentId} ->
            NewNodes = replace_node(Nodes, Selected, Node#tree_node{expanded = not Expanded}),
            ensure_visible(Tree#tree{nodes = NewNodes}, Bounds);
        not_found ->
            case visible_ids(Tree) of
                [FirstId | _] -> ensure_visible(Tree#tree{selected = FirstId}, Bounds);
                [] -> Tree#tree{selected = undefined, offset = 0}
            end
    end.

-spec select(term(), #tree{}, #bounds{}) -> #tree{}.
select(NodeId, Tree = #tree{nodes = Nodes}, Bounds) ->
    case find_node(Nodes, NodeId, undefined) of
        {ok, _Node, _ParentId} ->
            ensure_visible(Tree#tree{selected = NodeId}, Bounds);
        not_found ->
            Tree
    end.

%%====================================================================
%% Internal helpers
%%====================================================================

flatten_nodes([], _Depth, Acc) ->
    Acc;
flatten_nodes([Node | Rest], Depth, Acc) ->
    #tree_node{children = Children, expanded = Expanded} = Node,
    IsLast = Rest =:= [],
    NewAcc = [{Depth, IsLast, Node} | Acc],
    ChildAcc = case Expanded of
        true -> flatten_nodes(Children, Depth + 1, NewAcc);
        false -> NewAcc
    end,
    flatten_nodes(Rest, Depth, ChildAcc).

collect_visible_nodes(Nodes, Depth, Start, End, Index, Acc) ->
    {Rows, _FinalIndex} = collect_visible_nodes(Nodes, Depth, Start, End, Index, Acc, false),
    lists:reverse(Rows).

collect_visible_nodes([], _Depth, _Start, _End, Index, Acc, _Done) ->
    {Acc, Index};
collect_visible_nodes(_Nodes, _Depth, _Start, End, Index, Acc, true) when Index >= End ->
    {Acc, Index};
collect_visible_nodes([Node | Rest], Depth, Start, End, Index, Acc, _Done) ->
    NodeCount = count_node(Node),
    case Index + NodeCount =< Start of
        true ->
            collect_visible_nodes(Rest, Depth, Start, End, Index + NodeCount, Acc, false);
        false ->
            #tree_node{children = Children, expanded = Expanded} = Node,
            IsLast = Rest =:= [],
            Acc1 = case Index >= Start andalso Index < End of
                true -> [{Depth, IsLast, Node} | Acc];
                false -> Acc
            end,
            Index1 = Index + 1,
            {Acc2, Index2} = case Expanded andalso Index1 < End of
                true ->
                    collect_visible_nodes(Children, Depth + 1, Start, End, Index1, Acc1, false);
                false ->
                    {Acc1, Index1}
            end,
            collect_visible_nodes(Rest, Depth, Start, End, Index2, Acc2, Index2 >= End)
    end.

count_visible_nodes(Nodes) ->
    lists:sum([count_node(Node) || Node <- Nodes]).

count_node(#tree_node{expanded = false}) ->
    1;
count_node(#tree_node{expanded = true, children = Children}) ->
    1 + count_visible_nodes(Children).

visible_ids(Tree) ->
    [Id || {_, _, #tree_node{id = Id}} <- flatten_visible(Tree)].

selected_index(undefined, _Ids) ->
    0;
selected_index(Id, Ids) ->
    selected_index(Id, Ids, 1).

selected_index(_Id, [], _Index) ->
    0;
selected_index(Id, [Id | _], Index) ->
    Index;
selected_index(Id, [_ | Rest], Index) ->
    selected_index(Id, Rest, Index + 1).

ensure_visible(#tree{nodes = Nodes} = Tree, Bounds) ->
    ensure_visible_with_height(Tree#tree{nodes = Nodes}, max(1, resolved_height(Tree, Bounds))).

ensure_visible_with_height(#tree{nodes = Nodes} = Tree, VisibleHeight) ->
    FlatIds = [Id || {_, _, #tree_node{id = Id}} <- lists:reverse(flatten_nodes(Nodes, 0, []))],
    case FlatIds of
        [] ->
            Tree#tree{selected = undefined, offset = 0};
        _ ->
            MaxOffset = max(0, length(FlatIds) - VisibleHeight),
            CurrentOffset = clamp_offset(Tree#tree.offset, length(FlatIds), VisibleHeight),
            case selected_index(Tree#tree.selected, FlatIds) of
                0 ->
                    Tree#tree{offset = CurrentOffset};
                SelectedIdx when SelectedIdx =< CurrentOffset ->
                    Tree#tree{offset = SelectedIdx - 1};
                SelectedIdx when SelectedIdx > CurrentOffset + VisibleHeight ->
                    Tree#tree{offset = SelectedIdx - VisibleHeight};
                _ ->
                    Tree#tree{offset = min(CurrentOffset, MaxOffset)}
            end
    end.

clamp_offset(_Offset, _NumNodes, VisibleHeight) when VisibleHeight =< 0 ->
    0;
clamp_offset(Offset, NumNodes, VisibleHeight) ->
    max(0, min(Offset, max(0, NumNodes - VisibleHeight))).

nth_visible_node(1, [{_, _, Node} | _]) ->
    Node;
nth_visible_node(N, [_ | Rest]) when N > 1 ->
    nth_visible_node(N - 1, Rest);
nth_visible_node(_, []) ->
    false.

find_node([], _Id, _ParentId) ->
    not_found;
find_node([#tree_node{id = Id} = Node | _Rest], Id, ParentId) ->
    {ok, Node, ParentId};
find_node([#tree_node{id = NodeId, children = Children} | Rest], Id, ParentId) ->
    case find_node(Children, Id, NodeId) of
        not_found -> find_node(Rest, Id, ParentId);
        Found -> Found
    end.

replace_node([], _Id, _NewNode) ->
    [];
replace_node([#tree_node{id = Id} | Rest], Id, NewNode) ->
    [NewNode | Rest];
replace_node([#tree_node{children = Children} = Node | Rest], Id, NewNode) ->
    [Node#tree_node{children = replace_node(Children, Id, NewNode)}
     | replace_node(Rest, Id, NewNode)].
