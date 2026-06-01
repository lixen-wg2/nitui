%%%-------------------------------------------------------------------
%%% @doc NitUI Engine - Shared navigation, resolution and data access
%%% logic for the nitui TUI framework.
%%% @end
%%%-------------------------------------------------------------------
-module(iso_engine).

-include("iso_elements.hrl").

%% Navigation
-export([navigate_table/4, navigate_table/5]).
-export([navigate_list/4, navigate_list/5]).
-export([navigate_scroll/5]).
-export([navigate_tabs/2]).
-export([navigate_tree/3]).
-export([navigate_tree/5]).
-export([scroll_tree/5]).
-export([toggle_tree_node/3]).

%% Height resolvers
-export([resolved_table_visible_height/4]).
-export([resolved_list_visible_height/4]).
-export([resolved_tree_visible_height/4]).
-export([resolved_scroll_bounds/3]).

%% Page calculators
-export([page_lines_table/4, page_lines_list/4]).
-export([page_lines_tree/4, page_lines_scroll/3]).

%% Content finders
-export([find_table_in_content/1, find_pageable_in_content/1]).

%% Tab helpers
-export([update_tab_content/4, resolve_active_tab/2]).

%% Scroll helpers
-export([scroll_content_height/2]).
-export([find_scroll_at/4]).
-export([scroll_target/3, scroll_target_element/2]).
-export([collect_scroll_ids/1]).

%% List helpers
-export([next_in_list/2, prev_in_list/2]).

%% Data accessors
-export([selection_user_state/3, maybe_tree_selection_user_state/4]).
-export([list_selected_item/2, table_row_data/2]).
-export([focus_container_for/2]).
-export([activation_target/3]).
-export([default_table_visible_height/1]).
-export([split_at/2]).
-export([call_handler/3]).
-export([call_view/3]).
-export([init_focus_state/2]).
-export([cycle_focus/4]).

%% Input editing
-export([apply_char_input/3, apply_backspace/2, apply_delete_input/2]).
-export([move_input_cursor/4, position_input_cursor/4, start_input_selection/3,
         select_all_input/2]).

%% Element navigation (unified per-element dispatch)
-export([navigate_element/6, page_navigate_element/6]).
-export([page_navigate_tab_content/8]).

%%====================================================================
%% Navigation
%%====================================================================

navigate_table(Dir, Table, Tree, Bounds) ->
    navigate_table(Dir, 1, Table, Tree, Bounds).

navigate_table(Dir, Lines, #table{id = TableId} = Table, Tree, Bounds) ->
    case resolved_table_visible_height(Tree, TableId, Table, Bounds) of
        undefined ->
            iso_nav:navigate_table(Dir, Lines, Table);
        VisibleHeight ->
            iso_nav:navigate_table(Dir, Lines, VisibleHeight, Table)
    end.

navigate_list(Dir, List, Tree, Bounds) ->
    navigate_list(Dir, 1, List, Tree, Bounds).

navigate_list(Dir, Lines, #list{id = ListId} = List, Tree, Bounds) ->
    case resolved_list_visible_height(Tree, ListId, List, Bounds) of
        undefined ->
            iso_nav:navigate_list(Dir, Lines, List);
        VisibleHeight ->
            iso_nav:navigate_list(Dir, Lines, VisibleHeight, List)
    end.

navigate_scroll(down, Lines, #scroll{offset = Offset} = Scroll, Tree, Bounds) ->
    case resolved_scroll_bounds(Tree, Scroll#scroll.id, Bounds) of
        undefined ->
            Scroll;
        #bounds{height = ViewHeight} = ScrollBounds ->
            TotalHeight = scroll_content_height(Scroll, ScrollBounds),
            MaxOffset = max(0, TotalHeight - ViewHeight),
            Scroll#scroll{offset = min(MaxOffset, Offset + Lines)}
    end;
navigate_scroll(up, Lines, #scroll{offset = Offset} = Scroll, Tree, Bounds) ->
    case resolved_scroll_bounds(Tree, Scroll#scroll.id, Bounds) of
        undefined ->
            Scroll;
        #bounds{} ->
            Scroll#scroll{offset = max(0, Offset - Lines)}
    end;
navigate_scroll(_, _Lines, Scroll, _Tree, _Bounds) ->
    Scroll.

navigate_tabs(left, #tabs{tabs = TabList, active_tab = Active0} = T) ->
    TabIds = [Tab#tab.id || Tab <- TabList],
    Active = resolve_active_tab(Active0, TabIds),
    T#tabs{active_tab = prev_in_list(TabIds, Active)};
navigate_tabs(right, #tabs{tabs = TabList, active_tab = Active0} = T) ->
    TabIds = [Tab#tab.id || Tab <- TabList],
    Active = resolve_active_tab(Active0, TabIds),
    T#tabs{active_tab = next_in_list(TabIds, Active)}.

navigate_tree(Dir, TreeEl, Bounds) ->
    iso_tree_nav:navigate(Dir, TreeEl, Bounds).

navigate_tree(Dir, Lines, #tree{id = TreeId} = TreeEl, Tree, Bounds) ->
    VisibleHeight = resolved_tree_visible_height(Tree, TreeId, TreeEl, Bounds),
    iso_tree_nav:navigate(Dir, Lines, VisibleHeight, TreeEl).

scroll_tree(Dir, Lines, #tree{id = TreeId} = TreeEl, Tree, Bounds) ->
    VisibleHeight = resolved_tree_visible_height(Tree, TreeId, TreeEl, Bounds),
    iso_tree_nav:scroll(Dir, Lines, VisibleHeight, TreeEl).

toggle_tree_node(Dir, TreeEl, Bounds) ->
    iso_tree_nav:toggle(Dir, TreeEl, Bounds).

%%====================================================================
%% Height Resolvers
%%====================================================================

resolved_table_visible_height(Tree, TableId, #table{border = Border, show_header = ShowHeader},
                              Bounds) ->
    case iso_bounds:find_element_bounds(Tree, TableId, Bounds) of
        {ok, #bounds{height = ResolvedHeight}} ->
            BorderOffset = case Border of
                none -> 0;
                _ -> 1
            end,
            HeaderOffset = case ShowHeader of
                true -> 2;
                false -> 0
            end,
            max(1, ResolvedHeight - 2 * BorderOffset - HeaderOffset);
        not_found ->
            undefined
    end.

resolved_list_visible_height(Tree, ListId, #list{items = Items, height = H}, Bounds) ->
    case iso_bounds:find_element_bounds(Tree, ListId, Bounds) of
        {ok, #bounds{height = ResolvedHeight}} ->
            max(1, ResolvedHeight);
        not_found ->
            case H of
                auto -> max(1, length(Items));
                fill -> max(1, length(Items));
                _ -> max(1, H)
            end
    end.

resolved_tree_visible_height(Tree, TreeId, TreeEl, Bounds) ->
    case iso_bounds:find_element_bounds(Tree, TreeId, Bounds) of
        {ok, #bounds{height = ResolvedHeight}} ->
            max(1, ResolvedHeight);
        not_found ->
            max(1, iso_tree_nav:resolved_height(TreeEl, Bounds))
    end.

resolved_scroll_bounds(Tree, ScrollId, Bounds) ->
    case iso_bounds:find_element_bounds(Tree, ScrollId, Bounds) of
        {ok, ScrollBounds} -> ScrollBounds;
        not_found -> undefined
    end.


%%====================================================================
%% Page Calculators
%%====================================================================

page_lines_table(Tree, TableId, Table, Bounds) ->
    case resolved_table_visible_height(Tree, TableId, Table, Bounds) of
        undefined -> default_table_visible_height(Table);
        VisibleHeight -> VisibleHeight
    end.

page_lines_list(Tree, ListId, List, Bounds) ->
    resolved_list_visible_height(Tree, ListId, List, Bounds).

page_lines_tree(Tree, TreeId, TreeEl, Bounds) ->
    resolved_tree_visible_height(Tree, TreeId, TreeEl, Bounds).

page_lines_scroll(Tree, ScrollId, Bounds) ->
    case resolved_scroll_bounds(Tree, ScrollId, Bounds) of
        #bounds{height = ViewHeight} -> max(1, ViewHeight);
        undefined -> 1
    end.

%%====================================================================
%% Content Finders
%%====================================================================

find_table_in_content([]) -> false;
find_table_in_content([#table{} = T | _]) -> {ok, T};
find_table_in_content([_ | Rest]) -> find_table_in_content(Rest).

find_pageable_in_content([]) -> false;
find_pageable_in_content([#table{} = Table | _]) -> {ok, Table};
find_pageable_in_content([#list{} = List | _]) -> {ok, List};
find_pageable_in_content([#tree{} = TreeEl | _]) -> {ok, TreeEl};
find_pageable_in_content([#scroll{} = Scroll | _]) -> {ok, Scroll};
find_pageable_in_content([_ | Rest]) -> find_pageable_in_content(Rest).

%%====================================================================
%% Tab Helpers
%%====================================================================

update_tab_content(#tabs{tabs = TabList} = Tabs, TabId, OldElement, NewElement) ->
    NewTabList = lists:map(
        fun(#tab{id = Id, content = Content} = Tab) when Id =:= TabId ->
            NewContent = lists:map(
                fun(El) when El =:= OldElement -> NewElement;
                   (El) -> El
                end, Content),
            Tab#tab{content = NewContent};
           (Tab) -> Tab
        end, TabList),
    Tabs#tabs{tabs = NewTabList}.

resolve_active_tab(undefined, [First | _]) -> First;
resolve_active_tab(undefined, []) -> undefined;
resolve_active_tab(Active, _) -> Active.

%%====================================================================
%% Scroll Helpers
%%====================================================================

scroll_content_height(#scroll{children = Children}, Bounds) ->
    %% Children may return {flex, Min}; resolve to Min before summing so a
    %% fill-height child (e.g. #text{height = fill}) does not crash with
    %% badarith.
    lists:sum([height_value(iso_element:height(Child, Bounds)) || Child <- Children]).

height_value({flex, Min}) -> Min;
height_value(N) when is_integer(N) -> N.

find_scroll_at(Tree, Col, Row, Bounds) ->
    ScrollIds = lists:reverse(collect_scroll_ids(Tree)),
    find_scroll_at_ids(ScrollIds, Tree, Col, Row, Bounds).

find_scroll_at_ids([], _Tree, _Col, _Row, _Bounds) ->
    not_found;
find_scroll_at_ids([ScrollId | Rest], Tree, Col, Row, Bounds) ->
    case iso_bounds:find_element_bounds(Tree, ScrollId, Bounds) of
        {ok, ScrollBounds} ->
            case point_in_bounds(ScrollBounds, Col, Row) of
                true ->
                    {ok, ScrollId};
                false ->
                    find_scroll_at_ids(Rest, Tree, Col, Row, Bounds)
            end;
        _ ->
            find_scroll_at_ids(Rest, Tree, Col, Row, Bounds)
    end.

scroll_target(Tree, FocusedChild, FocusedContainer) ->
    case scroll_target_element(Tree, FocusedChild) of
        undefined ->
            scroll_target_element(Tree, FocusedContainer);
        Target ->
            Target
    end.

scroll_target_element(_Tree, undefined) ->
    undefined;
scroll_target_element(Tree, Id) ->
    case iso_focus:find_element(Tree, Id) of
        #list{} ->
            {list, Id};
        #table{} ->
            {table, Id};
        #tree{} ->
            {tree, Id};
        #scroll{} ->
            {scroll, Id};
        _ ->
            undefined
    end.

point_in_bounds(#bounds{x = X, y = Y, width = Width, height = Height}, Col, Row) ->
    Col >= X + 1 andalso Col =< X + Width andalso
    Row >= Y + 1 andalso Row =< Y + Height.

collect_scroll_ids(#scroll{id = Id} = El) ->
    Current = case Id of
        undefined -> [];
        _ -> [Id]
    end,
    Current ++ lists:flatmap(fun collect_scroll_ids/1, iso_element:children(El));
collect_scroll_ids(El) ->
    lists:flatmap(fun collect_scroll_ids/1, iso_element:children(El)).

%%====================================================================
%% List Helpers
%%====================================================================

next_in_list([], _) -> undefined;
next_in_list([Only], _) -> Only;
next_in_list(List, Current) ->
    next_in_list_wrap(List, Current, List).

next_in_list_wrap([Current], Current, [First | _]) -> First;
next_in_list_wrap([Current, Next | _], Current, _Orig) -> Next;
next_in_list_wrap([_ | Rest], Current, Orig) -> next_in_list_wrap(Rest, Current, Orig);
next_in_list_wrap(_, _, [First | _]) -> First.

prev_in_list(L, C) -> next_in_list(lists:reverse(L), C).

%%====================================================================
%% Data Accessors
%%====================================================================

selection_user_state(Cb, Event, US) ->
    case call_handler(Cb, Event, US) of
        {noreply, NewUS} -> NewUS;
        _ -> US
    end.

maybe_tree_selection_user_state(Cb, #tree{id = Id, selected = OldSelected},
                                #tree{selected = NewSelected}, US) ->
    case OldSelected =:= NewSelected of
        true -> US;
        false -> selection_user_state(Cb, {tree_select, Id, NewSelected}, US)
    end.

list_selected_item(Items, SelectedIdx) when SelectedIdx >= 0, SelectedIdx < length(Items) ->
    lists:nth(SelectedIdx + 1, Items);
list_selected_item(_Items, _SelectedIdx) ->
    undefined.

table_row_data(#table{row_provider = Provider, total_rows = TotalRows}, RowIdx)
        when is_function(Provider, 2), RowIdx >= 1 ->
    case TotalRows of
        undefined ->
            [];
        N when RowIdx =< N ->
            try Provider(RowIdx - 1, 1) of
                [Row | _] -> Row;
                _ -> []
            catch
                _:_ -> []
            end;
        _ ->
            []
    end;
table_row_data(#table{rows = Rows}, RowIdx) when RowIdx >= 1, RowIdx =< length(Rows) ->
    lists:nth(RowIdx, Rows);
table_row_data(_, _) ->
    [].

focus_container_for(Tree, ElementId) ->
    case iso_focus:find_container(Tree, ElementId) of
        undefined -> ElementId;
        Container -> Container
    end.

activation_target(Tree, Container, FocusedChild) ->
    case iso_focus:find_element(Tree, FocusedChild) of
        undefined ->
            case iso_focus:find_element(Tree, Container) of
                #table{} = Table -> Table;
                #list{} = List -> List;
                #tree{} = TreeEl -> TreeEl;
                _ -> undefined
            end;
        Element ->
            Element
    end.

default_table_visible_height(#table{rows = Rows, total_rows = TotalRows, height = H,
                                    border = Border, show_header = ShowHeader}) ->
    NumRows = case TotalRows of
        undefined -> length(Rows);
        N -> N
    end,
    case H of
        auto ->
            max(1, NumRows);
        fill ->
            max(1, NumRows);
        _ ->
            BorderOffset = case Border of
                none -> 0;
                _ -> 1
            end,
            HeaderOffset = case ShowHeader of
                true -> 2;
                false -> 0
            end,
            max(1, H - 2 * BorderOffset - HeaderOffset)
    end.

split_at(Bin, Pos) ->
    Chars = unicode:characters_to_list(iolist_to_binary([Bin])),
    SafePos = min(max(0, Pos), length(Chars)),
    lists:split(SafePos, Chars).



%%====================================================================
%% Element Navigation (unified per-element dispatch)
%%====================================================================

%% @doc Navigate an element by a single step (arrow keys).
%% Returns {ok, NewTree, NewUS} or unhandled.
-spec navigate_element(term(), term(), term(), term(), module(), term()) ->
    {ok, term(), term()} | unhandled.
navigate_element(Dir, ElementId, Tree, Bounds, Cb, US) ->
    case iso_focus:find_element(Tree, ElementId) of
        #table{} = Table when Dir =:= up; Dir =:= down ->
            NewTable = navigate_table(Dir, Table, Tree, Bounds),
            NewTree = iso_tree:update(Tree, ElementId, NewTable),
            Event = {table_select, NewTable#table.id, NewTable#table.selected_row,
                     table_row_data(NewTable, NewTable#table.selected_row)},
            NewUS = selection_user_state(Cb, Event, US),
            {ok, NewTree, NewUS};
        #tree{} = TreeEl when Dir =:= up; Dir =:= down ->
            NewTreeEl = navigate_tree(Dir, 1, TreeEl, Tree, Bounds),
            NewTree = iso_tree:update(Tree, ElementId, NewTreeEl),
            NewUS = maybe_tree_selection_user_state(Cb, TreeEl, NewTreeEl, US),
            {ok, NewTree, NewUS};
        #tree{} = TreeEl when Dir =:= left; Dir =:= right ->
            NewTreeEl = toggle_tree_node(Dir, TreeEl, Bounds),
            NewTree = iso_tree:update(Tree, ElementId, NewTreeEl),
            NewUS = maybe_tree_selection_user_state(Cb, TreeEl, NewTreeEl, US),
            {ok, NewTree, NewUS};
        #list{} = List when Dir =:= up; Dir =:= down ->
            NewList = navigate_list(Dir, List, Tree, Bounds),
            NewTree = iso_tree:update(Tree, ElementId, NewList),
            Event = {list_select, List#list.id, NewList#list.selected,
                     list_selected_item(NewList#list.items, NewList#list.selected)},
            NewUS = selection_user_state(Cb, Event, US),
            {ok, NewTree, NewUS};
        #scroll{} = Scroll when Dir =:= up; Dir =:= down ->
            NewScroll = navigate_scroll(Dir, 1, Scroll, Tree, Bounds),
            NewTree = iso_tree:update(Tree, ElementId, NewScroll),
            {ok, NewTree, US};
        _ ->
            unhandled
    end.

%% @doc Navigate an element by a page-sized step (PgUp/PgDn).
%% Returns {ok, NewTree, NewUS} or unhandled.
-spec page_navigate_element(term(), term(), term(), term(), module(), term()) ->
    {ok, term(), term()} | unhandled.
page_navigate_element(Dir, ElementId, Tree, Bounds, Cb, US) ->
    case iso_focus:find_element(Tree, ElementId) of
        #table{} = Table ->
            Lines = page_lines_table(Tree, Table#table.id, Table, Bounds),
            NewTable = navigate_table(Dir, Lines, Table, Tree, Bounds),
            NewTree = iso_tree:update(Tree, ElementId, NewTable),
            Event = {table_select, NewTable#table.id, NewTable#table.selected_row,
                     table_row_data(NewTable, NewTable#table.selected_row)},
            NewUS = selection_user_state(Cb, Event, US),
            {ok, NewTree, NewUS};
        #list{} = List ->
            Lines = page_lines_list(Tree, List#list.id, List, Bounds),
            NewList = navigate_list(Dir, Lines, List, Tree, Bounds),
            NewTree = iso_tree:update(Tree, ElementId, NewList),
            Event = {list_select, NewList#list.id, NewList#list.selected,
                     list_selected_item(NewList#list.items, NewList#list.selected)},
            NewUS = selection_user_state(Cb, Event, US),
            {ok, NewTree, NewUS};
        #tree{} = TreeEl ->
            Lines = page_lines_tree(Tree, TreeEl#tree.id, TreeEl, Bounds),
            NewTreeEl = iso_tree_nav:navigate(Dir, Lines, Lines, TreeEl),
            NewTree = iso_tree:update(Tree, ElementId, NewTreeEl),
            NewUS = maybe_tree_selection_user_state(Cb, TreeEl, NewTreeEl, US),
            {ok, NewTree, NewUS};
        #scroll{} = Scroll ->
            Lines = page_lines_scroll(Tree, Scroll#scroll.id, Bounds),
            NewScroll = navigate_scroll(Dir, Lines, Scroll, Tree, Bounds),
            NewTree = iso_tree:update(Tree, ElementId, NewScroll),
            {ok, NewTree, US};
        _ ->
            unhandled
    end.

%% @doc Page-navigate within active tab content.
%% Returns {ok, NewTree, NewUS} or unhandled.
-spec page_navigate_tab_content(term(), term(), term(), [term()], term(), term(), module(), term()) ->
    {ok, term(), term()} | unhandled.
page_navigate_tab_content(Dir, ContainerId, Tabs, Content, Tree, Bounds, Cb, US) ->
    case find_pageable_in_content(Content) of
        {ok, Element} ->
            ElementId = element_id(Element),
            case page_navigate_element_raw(Dir, Element, ElementId, Tree, Bounds, Cb, US) of
                {ok, NewElement, NewTree0, NewUS} ->
                    ActiveTab = Tabs#tabs.active_tab,
                    NewTabs = update_tab_content(Tabs, ActiveTab, Element, NewElement),
                    NewTree = iso_tree:update(NewTree0, ContainerId, NewTabs),
                    {ok, NewTree, NewUS};
                unhandled ->
                    unhandled
            end;
        false ->
            unhandled
    end.

%% Internal: page navigate returning the new element too (for tab content wrapping)
page_navigate_element_raw(Dir, #table{} = Table, ElementId, Tree, Bounds, Cb, US) ->
    Lines = page_lines_table(Tree, Table#table.id, Table, Bounds),
    NewTable = navigate_table(Dir, Lines, Table, Tree, Bounds),
    NewTree = iso_tree:update(Tree, ElementId, NewTable),
    Event = {table_select, NewTable#table.id, NewTable#table.selected_row,
             table_row_data(NewTable, NewTable#table.selected_row)},
    NewUS = selection_user_state(Cb, Event, US),
    {ok, NewTable, NewTree, NewUS};
page_navigate_element_raw(Dir, #list{} = List, ElementId, Tree, Bounds, Cb, US) ->
    Lines = page_lines_list(Tree, List#list.id, List, Bounds),
    NewList = navigate_list(Dir, Lines, List, Tree, Bounds),
    NewTree = iso_tree:update(Tree, ElementId, NewList),
    Event = {list_select, NewList#list.id, NewList#list.selected,
             list_selected_item(NewList#list.items, NewList#list.selected)},
    NewUS = selection_user_state(Cb, Event, US),
    {ok, NewList, NewTree, NewUS};
page_navigate_element_raw(Dir, #tree{} = TreeEl, ElementId, Tree, Bounds, Cb, US) ->
    Lines = page_lines_tree(Tree, TreeEl#tree.id, TreeEl, Bounds),
    NewTreeEl = iso_tree_nav:navigate(Dir, Lines, Lines, TreeEl),
    NewTree = iso_tree:update(Tree, ElementId, NewTreeEl),
    NewUS = maybe_tree_selection_user_state(Cb, TreeEl, NewTreeEl, US),
    {ok, NewTreeEl, NewTree, NewUS};
page_navigate_element_raw(Dir, #scroll{} = Scroll, ElementId, Tree, Bounds, _Cb, US) ->
    Lines = page_lines_scroll(Tree, Scroll#scroll.id, Bounds),
    NewScroll = navigate_scroll(Dir, Lines, Scroll, Tree, Bounds),
    NewTree = iso_tree:update(Tree, ElementId, NewScroll),
    {ok, NewScroll, NewTree, US};
page_navigate_element_raw(_, _, _, _, _, _, _) ->
    unhandled.

element_id(#table{id = Id}) -> Id;
element_id(#list{id = Id}) -> Id;
element_id(#tree{id = Id}) -> Id;
element_id(#scroll{id = Id}) -> Id;
element_id(_) -> undefined.
%%====================================================================
%% Input Editing
%%====================================================================

%% @doc Apply a character insertion at cursor position.
%% Returns {ok, NewTree, InputId, NewValue} or false if element is not an input.
-spec apply_char_input(term(), term(), integer() | string() | binary()) ->
    {ok, term(), term(), binary()} | false.
apply_char_input(_Tree, undefined, _Char) ->
    false;
apply_char_input(Tree, FocusedChild, Char) ->
    case iso_focus:find_element(Tree, FocusedChild) of
        #input{id = Id} = Input ->
            InsertedChars = input_chars(Char),
            {NewValue, NewPos} = replace_input_range(Input, InsertedChars),
            NewInput = Input#input{
                value = NewValue,
                cursor_pos = NewPos,
                selection_anchor = undefined
            },
            NewTree = iso_tree:update(Tree, FocusedChild, NewInput),
            {ok, NewTree, Id, NewValue};
        _ ->
            false
    end.

%% @doc Apply a backspace at cursor position.
%% Returns {ok, NewTree, InputId, NewValue} or false if element is not an input or cursor at 0.
-spec apply_backspace(term(), term()) ->
    {ok, term(), term(), binary()} | false.
apply_backspace(_Tree, undefined) ->
    false;
apply_backspace(Tree, FocusedChild) ->
    case iso_focus:find_element(Tree, FocusedChild) of
        #input{id = Id} = Input ->
            case backspace_input(Input) of
                false ->
                    false;
                {NewValue, NewPos} ->
                    NewInput = Input#input{
                        value = NewValue,
                        cursor_pos = NewPos,
                        selection_anchor = undefined
                    },
                    NewTree = iso_tree:update(Tree, FocusedChild, NewInput),
                    {ok, NewTree, Id, NewValue}
            end;
        _ ->
            false
    end.

-spec apply_delete_input(term(), term()) ->
    {ok, term(), term(), binary()} | false.
apply_delete_input(_Tree, undefined) ->
    false;
apply_delete_input(Tree, FocusedChild) ->
    case iso_focus:find_element(Tree, FocusedChild) of
        #input{id = Id} = Input ->
            case delete_input(Input) of
                false ->
                    false;
                {NewValue, NewPos} ->
                    NewInput = Input#input{
                        value = NewValue,
                        cursor_pos = NewPos,
                        selection_anchor = undefined
                    },
                    NewTree = iso_tree:update(Tree, FocusedChild, NewInput),
                    {ok, NewTree, Id, NewValue}
            end;
        _ ->
            false
    end.

-spec move_input_cursor(term(), term(), left | right | home | 'end', boolean()) ->
    {ok, term()} | false.
move_input_cursor(_Tree, undefined, _Dir, _Select) ->
    false;
move_input_cursor(Tree, InputId, Dir, Select) ->
    case iso_focus:find_element(Tree, InputId) of
        #input{} = Input ->
            NewInput = move_input_cursor_element(Input, Dir, Select),
            {ok, iso_tree:update(Tree, InputId, NewInput)};
        _ ->
            false
    end.

-spec position_input_cursor(term(), term(), integer(), boolean()) -> {ok, term()} | false.
position_input_cursor(_Tree, undefined, _Pos, _Select) ->
    false;
position_input_cursor(Tree, InputId, Pos, Select) ->
    case iso_focus:find_element(Tree, InputId) of
        #input{} = Input ->
            NewInput = position_input_cursor_element(Input, Pos, Select),
            {ok, iso_tree:update(Tree, InputId, NewInput)};
        _ ->
            false
    end.

-spec start_input_selection(term(), term(), integer()) -> {ok, term()} | false.
start_input_selection(_Tree, undefined, _Pos) ->
    false;
start_input_selection(Tree, InputId, Pos) ->
    case iso_focus:find_element(Tree, InputId) of
        #input{} = Input ->
            SafePos = clamp_input_pos(Pos, Input),
            NewInput = Input#input{cursor_pos = SafePos, selection_anchor = SafePos},
            {ok, iso_tree:update(Tree, InputId, NewInput)};
        _ ->
            false
    end.

-spec select_all_input(term(), term()) -> {ok, term()} | false.
select_all_input(_Tree, undefined) ->
    false;
select_all_input(Tree, InputId) ->
    case iso_focus:find_element(Tree, InputId) of
        #input{} = Input ->
            Len = input_length(Input),
            Anchor = case Len of
                0 -> undefined;
                _ -> 0
            end,
            NewInput = Input#input{cursor_pos = Len, selection_anchor = Anchor},
            {ok, iso_tree:update(Tree, InputId, NewInput)};
        _ ->
            false
    end.

replace_input_range(Input, InsertedChars) ->
    Chars = input_value_chars(Input),
    {Start, End} = input_replace_range(Input),
    {Before, Rest} = lists:split(Start, Chars),
    {_Replaced, After} = lists:split(End - Start, Rest),
    NewChars = Before ++ InsertedChars ++ After,
    {unicode:characters_to_binary(NewChars), Start + length(InsertedChars)}.

backspace_input(Input = #input{cursor_pos = Pos}) ->
    case input_selection_range(Input) of
        {Start, End} ->
            delete_input_range(Input, Start, End);
        none ->
            SafePos = clamp_input_pos(Pos, Input),
            case SafePos of
                0 -> false;
                _ -> delete_input_range(Input, SafePos - 1, SafePos)
            end
    end.

delete_input(Input = #input{cursor_pos = Pos}) ->
    case input_selection_range(Input) of
        {Start, End} ->
            delete_input_range(Input, Start, End);
        none ->
            SafePos = clamp_input_pos(Pos, Input),
            case SafePos >= input_length(Input) of
                true -> false;
                false -> delete_input_range(Input, SafePos, SafePos + 1)
            end
    end.

delete_input_range(Input, Start, End) ->
    Chars = input_value_chars(Input),
    {Before, Rest} = lists:split(Start, Chars),
    {_Deleted, After} = lists:split(End - Start, Rest),
    {unicode:characters_to_binary(Before ++ After), Start}.

move_input_cursor_element(Input, Dir, Select) ->
    CurrentPos = clamp_input_pos(Input#input.cursor_pos, Input),
    TargetPos = case {Select, input_selection_range(Input), Dir} of
        {false, {Start, _End}, left} -> Start;
        {false, {_Start, End}, right} -> End;
        _ -> move_pos(Dir, CurrentPos, input_length(Input))
    end,
    update_input_cursor_selection(Input, CurrentPos, TargetPos, Select).

position_input_cursor_element(Input, Pos, Select) ->
    CurrentPos = clamp_input_pos(Input#input.cursor_pos, Input),
    TargetPos = clamp_input_pos(Pos, Input),
    update_input_cursor_selection(Input, CurrentPos, TargetPos, Select).

update_input_cursor_selection(Input, CurrentPos, TargetPos, true) ->
    Anchor0 = case Input#input.selection_anchor of
        undefined -> CurrentPos;
        ExistingAnchor -> clamp_input_pos(ExistingAnchor, Input)
    end,
    Anchor = case Anchor0 =:= TargetPos of
        true -> undefined;
        false -> Anchor0
    end,
    Input#input{cursor_pos = TargetPos, selection_anchor = Anchor};
update_input_cursor_selection(Input, _CurrentPos, TargetPos, false) ->
    Input#input{cursor_pos = TargetPos, selection_anchor = undefined}.

move_pos(left, Pos, _Len) -> max(0, Pos - 1);
move_pos(right, Pos, Len) -> min(Len, Pos + 1);
move_pos(home, _Pos, _Len) -> 0;
move_pos('end', _Pos, Len) -> Len.

input_replace_range(Input = #input{cursor_pos = Pos}) ->
    case input_selection_range(Input) of
        {Start, End} -> {Start, End};
        none ->
            SafePos = clamp_input_pos(Pos, Input),
            {SafePos, SafePos}
    end.

input_selection_range(#input{selection_anchor = undefined}) ->
    none;
input_selection_range(Input = #input{cursor_pos = CursorPos, selection_anchor = Anchor}) ->
    SafeCursor = clamp_input_pos(CursorPos, Input),
    SafeAnchor = clamp_input_pos(Anchor, Input),
    case SafeCursor =:= SafeAnchor of
        true -> none;
        false -> {min(SafeCursor, SafeAnchor), max(SafeCursor, SafeAnchor)}
    end.

clamp_input_pos(Pos, Input) ->
    min(max(0, Pos), input_length(Input)).

input_length(Input) ->
    length(input_value_chars(Input)).

input_value_chars(#input{value = Value}) ->
    input_chars(Value).

input_chars(Value) when is_integer(Value) ->
    [Value];
input_chars(Value) when is_binary(Value) ->
    unicode:characters_to_list(Value);
input_chars(Value) when is_list(Value) ->
    unicode:characters_to_list(unicode:characters_to_binary(Value)).


%%====================================================================
%% Focus Cycling
%%====================================================================

%% @doc Cycle focus to the next or previous container and pick first child.
%% Returns {NewContainer, NewChild}.
-spec cycle_focus(next | prev, [term()], term(), term()) ->
    {term(), term()}.
cycle_focus(Dir, ContainerIds, CurrentContainer, Tree) ->
    NewContainer = case Dir of
        next -> next_in_list(ContainerIds, CurrentContainer);
        prev -> prev_in_list(ContainerIds, CurrentContainer)
    end,
    ChildIds = iso_focus:collect_children(Tree, NewContainer),
    NewChild = case ChildIds of [First | _] -> First; [] -> undefined end,
    {NewContainer, NewChild}.
%%====================================================================
%% Initialization
%%====================================================================

%% @doc Initialize callback module and compute initial focus state.
%% Returns {UserState, Tree, ContainerIds, FocusedContainer, FocusedChild}.
-spec init_focus_state(module(), term()) ->
    {term(), term(), [term()], term(), term()}.
init_focus_state(CallbackModule, InitArg) ->
    {UserState, Tree} = case CallbackModule:init(InitArg) of
        {ok, S} -> {S, call_view(CallbackModule, S, undefined)};
        {ok, S, T} -> {S, T}
    end,
    ContainerIds = iso_focus:collect_containers(Tree),
    FocusedContainer = case ContainerIds of
        [First | _] -> First;
        [] -> undefined
    end,
    ChildIds = iso_focus:collect_children(Tree, FocusedContainer),
    FocusedChild = case ChildIds of
        [FirstChild | _] -> FirstChild;
        [] -> undefined
    end,
    {UserState, Tree, ContainerIds, FocusedContainer, FocusedChild}.

%%====================================================================
%% Internal
%%====================================================================

%% @doc Render the user's view.
%%
%% When ContextTree is `undefined' (initial render after init or push),
%% view/1 is invoked twice: the first call seeds the
%% `nitui_view_tree' process-dictionary key, and the second call
%% sees that tree via nitui:selected_item/1. view/1 MUST therefore
%% be a pure function of State on those entry points; side effects
%% will fire twice.
%%
%% On subsequent re-renders ContextTree is the previous tree and
%% view/1 is invoked exactly once.
call_view(CallbackModule, State, undefined) ->
    Tree1 = call_view_once(CallbackModule, State, undefined),
    call_view_once(CallbackModule, State, Tree1);
call_view(CallbackModule, State, ContextTree) ->
    call_view_once(CallbackModule, State, ContextTree).

call_view_once(CallbackModule, State, ContextTree) ->
    Previous = erlang:get(nitui_view_tree),
    erlang:put(nitui_view_tree, ContextTree),
    try
        CallbackModule:view(State)
    after
        case Previous of
            undefined -> erlang:erase(nitui_view_tree);
            _ -> erlang:put(nitui_view_tree, Previous)
        end
    end.

call_handler(Cb, Event, US) ->
    case erlang:function_exported(Cb, handle_event, 2) of
        true ->
            WrappedEvent = case Event of
                {list_select, _, _, _} -> Event;
                {table_select, _, _, _} -> Event;
                {table_activate, _, _, _} -> Event;
                {table_header_click, _, _} -> Event;
                {tab_change, _, _} -> Event;
                {tree_activate, _, _} -> Event;
                {tree_select, _, _} -> Event;
                {click, _, _} -> Event;
                {input, _, _} -> Event;
                _ -> {event, Event}
            end,
            try Cb:handle_event(WrappedEvent, US)
            catch _:_ -> {noreply, US}
            end;
        false ->
            {noreply, US}
    end.
