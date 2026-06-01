%%%-------------------------------------------------------------------
%%% @doc Tree Element
%%%
%%% Displays a hierarchical tree view with expand/collapse.
%%% @end
%%%-------------------------------------------------------------------
-module(nit_el_tree).

-behaviour(nit_element).

-include("nit_elements.hrl").

-export([render/3, height/2, width/2, fixed_width/1]).

%%====================================================================
%% nit_element callbacks
%%====================================================================

render(#tree{visible = false}, _Bounds, _Opts) ->
    [];
render(Tree = #tree{selected = Selected, indent = Indent, show_lines = ShowLines,
                    x = X, y = Y, style = Style}, Bounds, Opts) ->
    ActualX = Bounds#bounds.x + X,
    ActualY = Bounds#bounds.y + Y,
    Width = width(Tree, Bounds),
    
    BaseStyle = maps:get(base_style, Opts, #{}),
    MergedStyle = maps:merge(BaseStyle, Style),
    
    %% Flatten and clip visible nodes to the current viewport
    VisibleNodes = nit_tree_nav:visible_nodes(Tree, Bounds),

    %% Render each node
    {Output, _} = lists:foldl(
        fun({Depth, IsLast, Node}, {Acc, Row}) ->
            NodeOutput = render_node(Node, Depth, IsLast, Selected, 
                                     ActualX, ActualY + Row, Width, Indent, ShowLines, MergedStyle),
            {[Acc, NodeOutput], Row + 1}
        end,
        {[], 0},
        VisibleNodes
    ),
    Output.

height(#tree{height = fill}, _Bounds) ->
    {flex, 1};
height(#tree{height = auto, nodes = Nodes}, _Bounds) ->
    count_visible_nodes(Nodes);
height(#tree{height = Height}, _Bounds) ->
    Height.

width(#tree{width = auto}, Bounds) -> Bounds#bounds.width;
width(#tree{width = fill}, Bounds) -> Bounds#bounds.width;
width(#tree{width = W}, _Bounds) -> W.

fixed_width(#tree{width = fill}) -> auto;
fixed_width(#tree{width = W}) -> W.

%%====================================================================
%% Internal functions
%%====================================================================

count_visible_nodes([]) -> 0;
count_visible_nodes(Nodes) ->
    lists:sum([count_node(N) || N <- Nodes]).

count_node(#tree_node{expanded = false}) -> 1;
count_node(#tree_node{expanded = true, children = Children}) ->
    1 + count_visible_nodes(Children).

render_node(#tree_node{id = Id, label = Label, icon = Icon, children = Children, expanded = Expanded},
            Depth, IsLast, Selected, X, Y, Width, Indent, ShowLines, Style) ->
    %% Build prefix with tree lines
    Prefix = build_prefix(Depth, IsLast, ShowLines, Indent),
    
    %% Expand/collapse indicator
    Indicator = case Children of
        [] -> <<"    ">>;
        _ when Expanded -> <<"[-] ">>;
        _ -> <<"[+] ">>
    end,
    
    %% Icon
    IconPart = case Icon of
        undefined -> <<>>;
        _ -> [Icon, " "]
    end,
    PrefixWidth = nit_unicode:display_width(Prefix),
    NodeContent = nit_ansi:truncate_content([Indicator, IconPart, Label], max(0, Width - PrefixWidth)),
    
    %% Selection styling
    NodeStyle = case Id =:= Selected of
        true -> maps:merge(Style, #{bg => white, fg => black});
        false -> Style
    end,
    
    [
        nit_ansi:move_to(Y + 1, X + 1),
        nit_ansi:style_to_ansi(#{dim => true}),
        Prefix,
        nit_ansi:reset_style(),
        nit_ansi:style_to_ansi(NodeStyle),
        NodeContent,
        nit_ansi:reset_style()
    ].

build_prefix(0, _IsLast, _ShowLines, _Indent) ->
    <<>>;
build_prefix(Depth, IsLast, true, Indent) ->
    %% Build tree lines
    Spaces = list_to_binary(lists:duplicate((Depth - 1) * Indent, $ )),
    Connector = case IsLast of
        true -> <<"└">>;
        false -> <<"├">>
    end,
    %% Use unicode:characters_to_binary for Unicode box drawing characters
    Dash = unicode:characters_to_binary(lists:duplicate(Indent - 1, $─)),
    <<Spaces/binary, Connector/binary, Dash/binary>>;
build_prefix(Depth, _IsLast, false, Indent) ->
    list_to_binary(lists:duplicate(Depth * Indent, $ )).
