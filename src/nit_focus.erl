%%%-------------------------------------------------------------------
%%% @doc Focus management for NitUI.
%%%
%%% Two-level focus model:
%%% - Tab/Shift+Tab: Navigate between containers (box, tabs)
%%% - Arrow keys: Navigate between elements within focused container
%%% @end
%%%-------------------------------------------------------------------
-module(nit_focus).

-include("nit_elements.hrl").

-export([next_focus/2, prev_focus/2, find_element/2, find_container/2]).
-export([collect_containers/1, collect_children/2]).

%%====================================================================
%% API
%%====================================================================

%% @doc Collect all focusable container IDs (for Tab navigation).
-spec collect_containers(tuple()) -> [term()].
collect_containers(Element) ->
    lists:flatten(do_collect_containers(Element)).

%% @doc Collect focusable children within a container (for arrow navigation).
-spec collect_children(tuple(), term()) -> [term()].
collect_children(Tree, ContainerId) ->
    case find_element(Tree, ContainerId) of
        undefined -> [];
        Container -> lists:flatten(do_collect_children(Container))
    end.

%% @doc Get the next focusable element ID after CurrentId.
%% If CurrentId is undefined or not found, returns the first focusable.
-spec next_focus([term()], term()) -> term() | undefined.
next_focus([], _CurrentId) ->
    undefined;
next_focus(FocusableIds, undefined) ->
    hd(FocusableIds);
next_focus(FocusableIds, CurrentId) ->
    case find_next(FocusableIds, CurrentId) of
        undefined -> hd(FocusableIds);  %% Wrap around
        NextId -> NextId
    end.

%% @doc Get the previous focusable element ID before CurrentId.
-spec prev_focus([term()], term()) -> term() | undefined.
prev_focus([], _CurrentId) ->
    undefined;
prev_focus(FocusableIds, undefined) ->
    lists:last(FocusableIds);
prev_focus(FocusableIds, CurrentId) ->
    case find_prev(FocusableIds, CurrentId) of
        undefined -> lists:last(FocusableIds);  %% Wrap around
        PrevId -> PrevId
    end.

%% @doc Find an element by ID in the tree.
-spec find_element(tuple(), term()) -> tuple() | undefined.
find_element(Element, Id) ->
    do_find(Element, Id).

%% @doc Find the nearest focusable container that owns the given element.
%% Returns undefined when the element is itself the outermost container.
-spec find_container(tuple(), term()) -> term() | undefined.
find_container(Element, Id) ->
    case do_find_container(Element, Id, undefined) of
        {ok, ContainerId} -> ContainerId;
        not_found -> undefined
    end.

%%====================================================================
%% Internal - Container collection (for Tab navigation)
%%====================================================================

%% Containers are: box with id, tabs with id, table with id, tree with id (all have internal navigation)
do_collect_containers(#box{id = Id, focusable = true}) when Id =/= undefined -> [Id];
do_collect_containers(#box{children = Children}) -> [do_collect_containers(C) || C <- Children];
do_collect_containers(#tabs{id = Id, focusable = true}) when Id =/= undefined -> [Id];
do_collect_containers(#tabs{}) -> [];
do_collect_containers(#table{id = Id, focusable = true}) when Id =/= undefined -> [Id];
do_collect_containers(#table{}) -> [];
do_collect_containers(#tree{id = Id, focusable = true}) when Id =/= undefined -> [Id];
do_collect_containers(#tree{}) -> [];
do_collect_containers(#list{id = Id, focusable = true}) when Id =/= undefined -> [Id];
do_collect_containers(#list{}) -> [];
do_collect_containers(#scroll{id = Id, focusable = true}) when Id =/= undefined -> [Id];
do_collect_containers(#panel{children = Children}) -> [do_collect_containers(C) || C <- Children];
do_collect_containers(#vbox{children = Children}) -> [do_collect_containers(C) || C <- Children];
do_collect_containers(#hbox{children = Children}) -> [do_collect_containers(C) || C <- Children];
do_collect_containers(#scroll{children = Children}) -> [do_collect_containers(C) || C <- Children];
do_collect_containers(#modal{children = Children}) -> [do_collect_containers(C) || C <- Children];
do_collect_containers(_) -> [].

%%====================================================================
%% Internal - Children collection (for arrow navigation within container)
%%====================================================================

do_collect_children(#box{children = Children}) ->
    lists:flatten([do_collect_child(C) || C <- Children]);
do_collect_children(#tabs{tabs = TabList}) ->
    %% For tabs, the "children" are the tab IDs themselves
    [T#tab.id || T <- TabList];
do_collect_children(_) -> [].

%% Collect focusable elements (not containers)
do_collect_child(#button{id = Id, focusable = true}) when Id =/= undefined -> [Id];
do_collect_child(#button{}) -> [];
do_collect_child(#input{id = Id, focusable = true}) when Id =/= undefined -> [Id];
do_collect_child(#input{}) -> [];
do_collect_child(#table{id = Id, focusable = true}) when Id =/= undefined -> [Id];
do_collect_child(#table{}) -> [];
do_collect_child(#list{id = Id, focusable = true}) when Id =/= undefined -> [Id];
do_collect_child(#list{}) -> [];
do_collect_child(#scroll{id = Id, focusable = true}) when Id =/= undefined -> [Id];
do_collect_child(#vbox{children = Children}) -> [do_collect_child(C) || C <- Children];
do_collect_child(#hbox{children = Children}) -> [do_collect_child(C) || C <- Children];
do_collect_child(#scroll{children = Children}) -> [do_collect_child(C) || C <- Children];
do_collect_child(_) -> [].

find_next([CurrentId, NextId | _], CurrentId) -> NextId;
find_next([_ | Rest], CurrentId) -> find_next(Rest, CurrentId);
find_next(_, _) -> undefined.

find_prev([PrevId, CurrentId | _], CurrentId) -> PrevId;
find_prev([_ | Rest], CurrentId) -> find_prev(Rest, CurrentId);
find_prev(_, _) -> undefined.

do_find(#button{id = Id} = E, Id) -> E;
do_find(#input{id = Id} = E, Id) -> E;
do_find(#table{id = Id} = E, Id) -> E;
do_find(#tree{id = Id} = E, Id) -> E;
do_find(#list{id = Id} = E, Id) -> E;
do_find(#scroll{id = Id} = E, Id) -> E;
do_find(#tabs{id = Id} = E, Id) -> E;
do_find(#tabs{tabs = TabList, active_tab = ActiveTab0}, Id) ->
    %% Search in active tab content (default to first tab if undefined)
    ActiveTab = case ActiveTab0 of
        undefined -> case TabList of [#tab{id = First}|_] -> First; [] -> undefined end;
        _ -> ActiveTab0
    end,
    ActiveContent = case lists:keyfind(ActiveTab, #tab.id, TabList) of
        #tab{content = Content} -> Content;
        false -> []
    end,
    find_in_children(ActiveContent, Id);
do_find(#box{id = Id} = E, Id) -> E;
do_find(#box{children = Children}, Id) -> find_in_children(Children, Id);
do_find(#panel{children = Children}, Id) -> find_in_children(Children, Id);
do_find(#vbox{children = Children}, Id) -> find_in_children(Children, Id);
do_find(#hbox{children = Children}, Id) -> find_in_children(Children, Id);
do_find(#scroll{children = Children}, Id) -> find_in_children(Children, Id);
do_find(#modal{id = Id} = E, Id) -> E;
do_find(#modal{children = Children}, Id) -> find_in_children(Children, Id);
do_find(_, _) -> undefined.

find_in_children([], _Id) -> undefined;
find_in_children([Child | Rest], Id) ->
    case do_find(Child, Id) of
        undefined -> find_in_children(Rest, Id);
        Found -> Found
    end.

do_find_container(Element, Id, CurrentContainer) when is_tuple(Element) ->
    ElementId = get_element_id(Element),
    case ElementId =:= Id of
        true ->
            {ok, CurrentContainer};
        false ->
            NextContainer = case container_id(Element) of
                undefined -> CurrentContainer;
                ContainerId -> ContainerId
            end,
            find_container_in_children(get_search_children(Element), Id, NextContainer)
    end;
do_find_container(_, _, _) ->
    not_found.

find_container_in_children([], _Id, _CurrentContainer) ->
    not_found;
find_container_in_children([Child | Rest], Id, CurrentContainer) ->
    case do_find_container(Child, Id, CurrentContainer) of
        not_found -> find_container_in_children(Rest, Id, CurrentContainer);
        Found -> Found
    end.

get_search_children(#box{children = Children}) -> Children;
get_search_children(#panel{children = Children}) -> Children;
get_search_children(#vbox{children = Children}) -> Children;
get_search_children(#hbox{children = Children}) -> Children;
get_search_children(#scroll{children = Children}) -> Children;
get_search_children(#modal{children = Children}) -> Children;
get_search_children(#tabs{tabs = TabList, active_tab = ActiveTab0}) ->
    ActiveTab = case ActiveTab0 of
        undefined -> case TabList of [#tab{id = First} | _] -> First; [] -> undefined end;
        _ -> ActiveTab0
    end,
    case lists:keyfind(ActiveTab, #tab.id, TabList) of
        #tab{content = Content} -> Content;
        false -> []
    end;
get_search_children(_) -> [].

container_id(#box{id = Id, focusable = true}) when Id =/= undefined -> Id;
container_id(#tabs{id = Id, focusable = true}) when Id =/= undefined -> Id;
container_id(#table{id = Id, focusable = true}) when Id =/= undefined -> Id;
container_id(#tree{id = Id, focusable = true}) when Id =/= undefined -> Id;
container_id(#list{id = Id, focusable = true}) when Id =/= undefined -> Id;
container_id(#scroll{id = Id, focusable = true}) when Id =/= undefined -> Id;
container_id(_) -> undefined.

get_element_id(#button{id = Id}) -> Id;
get_element_id(#input{id = Id}) -> Id;
get_element_id(#table{id = Id}) -> Id;
get_element_id(#tree{id = Id}) -> Id;
get_element_id(#list{id = Id}) -> Id;
get_element_id(#scroll{id = Id}) -> Id;
get_element_id(#tabs{id = Id}) -> Id;
get_element_id(#box{id = Id}) -> Id;
get_element_id(#panel{id = Id}) -> Id;
get_element_id(#vbox{id = Id}) -> Id;
get_element_id(#hbox{id = Id}) -> Id;
get_element_id(#text{id = Id}) -> Id;
get_element_id(#header{id = Id}) -> Id;
get_element_id(#status_bar{id = Id}) -> Id;
get_element_id(#progress_bar{id = Id}) -> Id;
get_element_id(#sparkline{id = Id}) -> Id;
get_element_id(#stat_row{id = Id}) -> Id;
get_element_id(#spacer{id = Id}) -> Id;
get_element_id(#modal{id = Id}) -> Id;
get_element_id(_) -> undefined.
