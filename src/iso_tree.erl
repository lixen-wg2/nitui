%%%-------------------------------------------------------------------
%%% @doc NitUI Tree Utilities - Update elements in the UI tree.
%%% @end
%%%-------------------------------------------------------------------
-module(iso_tree).

-include("iso_elements.hrl").

-export([update/3, merge_state/2]).

%% Update an element in the tree by ID
-spec update(term(), term(), term()) -> term().
%% Leaf elements - match by ID and replace
update(#input{id = Id}, Id, NewElement) -> NewElement;
update(#button{id = Id}, Id, NewElement) -> NewElement;
update(#table{id = Id}, Id, NewElement) -> NewElement;
update(#tabs{id = Id}, Id, NewElement) -> NewElement;
update(#box{id = Id}, Id, NewElement) -> NewElement;
update(#tree{id = Id}, Id, NewElement) -> NewElement;
update(#text{id = Id}, Id, NewElement) -> NewElement;
update(#header{id = Id}, Id, NewElement) -> NewElement;
update(#status_bar{id = Id}, Id, NewElement) -> NewElement;
update(#progress_bar{id = Id}, Id, NewElement) -> NewElement;
update(#sparkline{id = Id}, Id, NewElement) -> NewElement;
update(#stat_row{id = Id}, Id, NewElement) -> NewElement;
update(#spacer{id = Id}, Id, NewElement) -> NewElement;
update(#modal{id = Id}, Id, NewElement) -> NewElement;
update(#panel{id = Id}, Id, NewElement) -> NewElement;
update(#vbox{id = Id}, Id, NewElement) -> NewElement;
update(#hbox{id = Id}, Id, NewElement) -> NewElement;
update(#scroll{id = Id}, Id, NewElement) -> NewElement;
update(#list{id = Id}, Id, NewElement) -> NewElement;
%% Container elements - recurse into children
update(#box{children = Children} = Box, Id, NewElement) ->
    Box#box{children = [update(C, Id, NewElement) || C <- Children]};
update(#panel{children = Children} = Panel, Id, NewElement) ->
    Panel#panel{children = [update(C, Id, NewElement) || C <- Children]};
update(#vbox{children = Children} = VBox, Id, NewElement) ->
    VBox#vbox{children = [update(C, Id, NewElement) || C <- Children]};
update(#hbox{children = Children} = HBox, Id, NewElement) ->
    HBox#hbox{children = [update(C, Id, NewElement) || C <- Children]};
update(#modal{children = Children} = Modal, Id, NewElement) ->
    Modal#modal{children = [update(C, Id, NewElement) || C <- Children]};
update(#scroll{children = Children} = Scroll, Id, NewElement) ->
    Scroll#scroll{children = [update(C, Id, NewElement) || C <- Children]};
update(#tabs{tabs = Tabs} = TabsEl, Id, NewElement) ->
    NewTabs = [update_tab(T, Id, NewElement) || T <- Tabs],
    TabsEl#tabs{tabs = NewTabs};
update(Element, _Id, _NewElement) -> Element.

update_tab(#tab{content = Content} = Tab, Id, NewElement) ->
    Tab#tab{content = [update(C, Id, NewElement) || C <- Content]}.


%%====================================================================
%% Merge UI state from old tree to new tree
%%====================================================================
%% This preserves scroll positions, selections, etc. when the view is
%% rebuilt (e.g., on tick). Elements are matched by ID.

-spec merge_state(OldTree :: term(), NewTree :: term()) -> term().

%% Tables - preserve selection, scroll, and built-in sort state
merge_state(#table{id = Id} = Old,
            #table{id = Id} = New) ->
    iso_el_table:merge_sort_state(Old, New);

%% Lists - preserve selected index and scroll offset
merge_state(#list{id = Id, selected = OldSel, offset = OldOff},
            #list{id = Id} = New) ->
    New#list{selected = OldSel, offset = OldOff};

%% Scroll containers - preserve scroll offset
merge_state(#scroll{id = Id, offset = OldOff},
            #scroll{id = Id} = New) ->
    New#scroll{offset = OldOff};

%% Trees - preserve selected and expanded states
merge_state(#tree{id = Id, selected = OldSel, offset = OldOff, nodes = OldNodes},
            #tree{id = Id} = New) ->
    New#tree{selected = OldSel, offset = OldOff,
             nodes = merge_tree_nodes(OldNodes, New#tree.nodes)};

%% Inputs - preserve value, cursor position, and active selection
merge_state(#input{id = Id, value = OldVal, cursor_pos = OldPos,
                   selection_anchor = OldAnchor},
            #input{id = Id} = New) ->
    New#input{value = OldVal, cursor_pos = OldPos,
              selection_anchor = OldAnchor};

%% Tabs - preserve active_tab
merge_state(#tabs{id = Id, active_tab = OldActive},
            #tabs{id = Id} = New) ->
    New#tabs{active_tab = OldActive};

%% Container elements - recurse into children and merge
merge_state(#vbox{children = OldChildren}, #vbox{children = NewChildren} = New) ->
    New#vbox{children = merge_children(OldChildren, NewChildren)};
merge_state(#hbox{children = OldChildren}, #hbox{children = NewChildren} = New) ->
    New#hbox{children = merge_children(OldChildren, NewChildren)};
merge_state(#box{children = OldChildren}, #box{children = NewChildren} = New) ->
    New#box{children = merge_children(OldChildren, NewChildren)};
merge_state(#panel{children = OldChildren}, #panel{children = NewChildren} = New) ->
    New#panel{children = merge_children(OldChildren, NewChildren)};
merge_state(#modal{children = OldChildren}, #modal{children = NewChildren} = New) ->
    New#modal{children = merge_children(OldChildren, NewChildren)};
merge_state(#scroll{children = OldChildren} = Old, #scroll{children = NewChildren} = New) ->
    %% For scroll, also preserve offset
    Merged = merge_state_scroll_only(Old, New),
    Merged#scroll{children = merge_children(OldChildren, NewChildren)};
merge_state(#tabs{tabs = OldTabs} = Old, #tabs{tabs = NewTabs} = New) ->
    %% Preserve active_tab and merge tab contents
    Merged = merge_state_tabs_only(Old, New),
    Merged#tabs{tabs = merge_tabs(OldTabs, NewTabs)};

%% No state to merge - return new as-is
merge_state(_Old, New) -> New.

%% Helper to merge scroll element state only (without children)
merge_state_scroll_only(#scroll{id = Id, offset = OldOff},
                        #scroll{id = Id} = New) ->
    New#scroll{offset = OldOff};
merge_state_scroll_only(_Old, New) -> New.

%% Helper to merge tabs element state only (without tab contents)
merge_state_tabs_only(#tabs{id = Id, active_tab = OldActive},
                      #tabs{id = Id} = New) ->
    New#tabs{active_tab = OldActive};
merge_state_tabs_only(_Old, New) -> New.

%% Merge children lists by ID when possible and positionally for anonymous layout nodes.
merge_children(OldChildren, NewChildren) ->
    OldMap = build_id_map(OldChildren),
    OldAnonymous = anonymous_children(OldChildren),
    {Merged, _RemainingAnonymous} = merge_children(NewChildren, OldMap, OldAnonymous, []),
    lists:reverse(Merged).

merge_children([], _OldMap, OldAnonymous, Acc) ->
    {Acc, OldAnonymous};
merge_children([NewChild | Rest], OldMap, OldAnonymous, Acc) ->
    {MergedChild, RemainingAnonymous} = merge_child(NewChild, OldMap, OldAnonymous),
    merge_children(Rest, OldMap, RemainingAnonymous, [MergedChild | Acc]).

merge_child(NewChild, OldMap, OldAnonymous) ->
    case get_element_id(NewChild) of
        undefined ->
            case OldAnonymous of
                [OldChild | Rest] ->
                    {merge_state(OldChild, NewChild), Rest};
                [] ->
                    {NewChild, []}
            end;
        Id ->
            case maps:get(Id, OldMap, undefined) of
                undefined -> {NewChild, OldAnonymous};
                OldChild -> {merge_state(OldChild, NewChild), OldAnonymous}
            end
    end.

build_id_map(Children) ->
    lists:foldl(fun(C, Acc) ->
        case get_element_id(C) of
            undefined -> Acc;
            Id -> maps:put(Id, C, Acc)
        end
    end, #{}, Children).

anonymous_children(Children) ->
    [Child || Child <- Children, get_element_id(Child) =:= undefined].

%% Extract ID from any element type
get_element_id(#table{id = Id}) -> Id;
get_element_id(#list{id = Id}) -> Id;
get_element_id(#scroll{id = Id}) -> Id;
get_element_id(#tree{id = Id}) -> Id;
get_element_id(#input{id = Id}) -> Id;
get_element_id(#tabs{id = Id}) -> Id;
get_element_id(#box{id = Id}) -> Id;
get_element_id(#vbox{id = Id}) -> Id;
get_element_id(#hbox{id = Id}) -> Id;
get_element_id(#panel{id = Id}) -> Id;
get_element_id(#modal{id = Id}) -> Id;
get_element_id(#button{id = Id}) -> Id;
get_element_id(#text{id = Id}) -> Id;
get_element_id(#header{id = Id}) -> Id;
get_element_id(#status_bar{id = Id}) -> Id;
get_element_id(#progress_bar{id = Id}) -> Id;
get_element_id(#sparkline{id = Id}) -> Id;
get_element_id(#stat_row{id = Id}) -> Id;
get_element_id(#spacer{id = Id}) -> Id;
get_element_id(_) -> undefined.

%% Merge tab contents
merge_tabs(OldTabs, NewTabs) ->
    OldTabMap = lists:foldl(fun(#tab{id = Id} = T, Acc) ->
        maps:put(Id, T, Acc)
    end, #{}, OldTabs),
    [merge_tab(T, OldTabMap) || T <- NewTabs].

merge_tab(#tab{id = Id, content = NewContent} = NewTab, OldTabMap) ->
    case maps:get(Id, OldTabMap, undefined) of
        undefined -> NewTab;
        #tab{content = OldContent} ->
            NewTab#tab{content = merge_children(OldContent, NewContent)}
    end.

merge_tree_nodes(OldNodes, NewNodes) ->
    OldNodeMap = lists:foldl(fun(#tree_node{id = Id} = Node, Acc) ->
        maps:put(Id, Node, Acc)
    end, #{}, OldNodes),
    [merge_tree_node(Node, OldNodeMap) || Node <- NewNodes].

merge_tree_node(#tree_node{id = Id, children = NewChildren} = NewNode, OldNodeMap) ->
    case maps:get(Id, OldNodeMap, undefined) of
        undefined ->
            NewNode#tree_node{children = merge_tree_nodes([], NewChildren)};
        #tree_node{expanded = OldExpanded, children = OldChildren} ->
            NewNode#tree_node{
                expanded = OldExpanded,
                children = merge_tree_nodes(OldChildren, NewChildren)
            }
    end.
