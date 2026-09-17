-module(nit_server_table_activation_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("nitui/include/nit_elements.hrl").

-export([init/1, view/1, handle_event/2]).

init(State) ->
    {ok, State}.

%% Rebuilds must expose the new selection to view/1, even when the callback
%% returns the original tree and relies on the server to preserve widget state.
view(#{tree := Tree, expected_selection := {RowIdx, RowData}}) ->
    Table = nit_focus:find_element(erlang:get(nitui_view_tree), rows),
    ?assertEqual(RowIdx, Table#table.selected_row),
    ?assertEqual(RowData, nit_engine:table_row_data(Table, RowIdx)),
    Tree;
view(#{tree := Tree}) ->
    Tree.

handle_event({event, escape}, _State) ->
    pop;
handle_event(Event, State = #{event_ref := Ref}) ->
    %% Observe delivery independently of whether the server retains NewState.
    self() ! {Ref, Event},
    handle_table_event(Event, State).

handle_table_event(Event = {table_activate, rows, RowIdx, RowData},
                   State = #{open_view := _}) ->
    open_table_view(Event, RowIdx, RowData, State);
handle_table_event(Event = {table_cell_click, rows, RowIdx, _ColumnId, RowData},
                   State = #{open_view := _}) ->
    open_table_view(Event, RowIdx, RowData, State);
handle_table_event(Event = {table_cell_click, rows, RowIdx, _ColumnId, RowData},
                   State = #{events := Events, tree := Tree}) ->
    NewState = State#{events := [Event | Events], expected_selection => {RowIdx, RowData},
                      tree := maps:get(replacement_tree, State, Tree)},
    case maps:get(cell_response, State, noreply) of
        {modal, Modal} -> {modal, Modal, NewState};
        Response -> {Response, NewState}
    end;
handle_table_event(Event = {Kind, rows, RowIdx, RowData}, State = #{events := Events})
        when Kind =:= table_select; Kind =:= table_activate ->
    {noreply, State#{events := [Event | Events], expected_selection => {RowIdx, RowData}}};
handle_table_event(Event, State = #{events := Events}) ->
    {noreply, State#{events := [Event | Events]}}.

open_table_view(Event, RowIdx, RowData, #{open_view := Action, events := Events} = State) ->
    %% No table_select may run before a click/activation that navigates away.
    ?assertEqual([], Events),
    NewState = State#{events := [Event]},
    DetailState = NewState#{tree := #text{id = detail, content = integer_to_binary(RowIdx)}},
    case Action of
        rebuild -> {noreply, DetailState#{expected_selection => {RowIdx, RowData}}};
        switch -> {switch, ?MODULE, DetailState};
        push -> {push, ?MODULE, DetailState,
                 NewState#{expected_selection => {RowIdx, RowData}}}
    end.

table_click_options_are_appended_and_opt_in_test() ->
    Table = #table{},
    ?assertEqual(false, Table#table.activate_on_click),
    ?assertEqual(#table.focused_selected_style + 1, #table.activate_on_click),
    ?assertEqual([], Table#table.clickable_columns),
    ?assertEqual(#table.activate_on_click + 1, #table.clickable_columns),
    ?assertEqual(#table.clickable_columns, tuple_size(Table)).

single_click_activates_actual_row_test_() ->
    [?_test(begin
        Table = (table())#table{selected_row = Selected, activate_on_click = true,
                                activate_on_reclick = Reclick},
        Tree = case Nested of
            false -> Table;
            true -> #box{id = box, border = none, focusable = true, children = [Table]}
        end,
        {Events, NewTree} = run(Tree, [click(2)]),
        ?assertEqual([{table_activate, rows, 2, [2]}], Events),
        assert_selection(NewTree, 2)
    end) || Selected <- [0, 1, 2, 3], Reclick <- [false, true], Nested <- [false, true]].

default_clicks_select_once_each_and_enter_activates_test() ->
    {Events, Tree} = run(table(), [click(2), click(2), click(3), enter]),
    ?assertEqual([{table_select, rows, 2, [2]}, {table_select, rows, 2, [2]},
                  {table_select, rows, 3, [3]}, {table_activate, rows, 3, [3]}], Events),
    assert_selection(Tree, 3).

reclick_still_selects_first_then_activates_test() ->
    Table = (table())#table{activate_on_reclick = true},
    {Events, Tree} = run(Table, [click(2), click(2), click(3), click(3)]),
    ?assertEqual([{table_select, rows, 2, [2]}, {table_activate, rows, 2, [2]},
                  {table_select, rows, 3, [3]}, {table_activate, rows, 3, [3]}], Events),
    assert_selection(Tree, 3).

single_click_repeats_activate_once_each_test() ->
    Table = (table())#table{activate_on_click = true},
    {Events, Tree} = run(Table, [click(2), click(2), click(3)]),
    ?assertEqual([{table_activate, rows, 2, [2]}, {table_activate, rows, 2, [2]},
                  {table_activate, rows, 3, [3]}], Events),
    assert_selection(Tree, 3).

arrows_only_select_and_enter_activates_test_() ->
    [?_test(begin
        Table = (table())#table{activate_on_click = Click, activate_on_reclick = Reclick},
        {Events, Tree} = run(Table, [{key, down}, {key, down}, {key, up}, enter]),
        ?assertEqual([{table_select, rows, 2, [2]}, {table_select, rows, 3, [3]},
                      {table_select, rows, 2, [2]}, {table_activate, rows, 2, [2]}], Events),
        assert_selection(Tree, 2)
    end) || Click <- [false, true], Reclick <- [false, true]].

activation_opens_view_without_selection_callback_test_() ->
    [?_test(begin
        Table = (table())#table{activate_on_click = true},
        {Events, Tree} = run(Table, [click(3)], #{open_view => Action}),
        ?assertEqual([{table_activate, rows, 3, [3]}], Events),
        ?assertEqual(#text{id = detail, content = <<"3">>}, Tree)
    end) || Action <- [rebuild, switch, push]].

push_and_pop_preserve_clicked_selection_test() ->
    Table = (table())#table{activate_on_click = true},
    {Events, Tree} = run(Table, [click(3), escape], #{open_view => push}),
    ?assertEqual([{table_activate, rows, 3, [3]}], Events),
    assert_selection(Tree, 3).

scrolled_virtual_click_activates_absolute_row_test() ->
    Provider = fun(Start, Count) -> [[N] || N <- lists:seq(Start + 1, Start + Count)] end,
    Table = (table())#table{activate_on_click = true, rows = [], total_rows = 20,
                            row_provider = Provider, scroll_offset = 5},
    {Events, Tree} = run(Table, [click(2)]),
    ?assertEqual([{table_activate, rows, 7, [7]}], Events),
    assert_selection(Tree, 7).

cell_click_emits_only_cell_event_for_every_activation_mode_test_() ->
    [?_test(begin
        Table = (cell_table())#table{selected_row = Selected, activate_on_click = Click,
                                     activate_on_reclick = Reclick},
        Tree = case Nested of
            false -> Table;
            true -> #box{id = box, border = none, focusable = true, children = [Table]}
        end,
        {Events, NewTree} = run(Tree, [click(2), click(2)]),
        ?assertEqual([{table_cell_click, rows, 2, value, [2]},
                      {table_cell_click, rows, 2, value, [2]}], Events),
        assert_selection(NewTree, 2)
    end) || Selected <- [0, 1, 2, 3], Click <- [false, true],
            Reclick <- [false, true], Nested <- [false, true]].

ordinary_columns_separators_and_trailing_padding_are_unchanged_test_() ->
    [?_test(begin
        Table = (cell_table())#table{activate_on_click = Click, activate_on_reclick = Reclick},
        Input = [{mouse, click, left, Col, Row} || Row <- [2, 2, 3], Col <- [5, 6, 20]]
                ++ [{key, up}, enter],
        {Expected, _} = run(Table#table{clickable_columns = []}, Input),
        {Events, _} = run(Table, Input),
        ?assertEqual(Expected, Events)
    end) || Click <- [false, true], Reclick <- [false, true]].

unknown_clickable_column_keeps_row_activation_test() ->
    Table = (table())#table{clickable_columns = [missing], activate_on_click = true},
    {Events, Tree} = run(Table, [click(2)]),
    ?assertEqual([{table_activate, rows, 2, [2]}], Events),
    assert_selection(Tree, 2).

cell_click_focuses_table_before_keyboard_navigation_test() ->
    Table = cell_table(),
    Tree = #box{id = box, focusable = true, border = none,
                children = [(table())#table{id = other, x = 30}, Table]},
    {Events, NewTree} = run(Tree, [click(2), {key, down}, enter]),
    ?assertEqual([{table_cell_click, rows, 2, value, [2]},
                  {table_select, rows, 3, [3]}, {table_activate, rows, 3, [3]}], Events),
    assert_selection(NewTree, 3),
    ?assertMatch(#table{selected_row = 1}, nit_focus:find_element(NewTree, other)).

wheel_over_clickable_column_scrolls_hovered_not_focused_table_test() ->
    Tree = #box{id = box, focusable = true, border = none,
                children = [(table())#table{id = other, x = 30}, cell_table()]},
    {Events, NewTree} = run(Tree, [{mouse, scroll, down, 2, 2}]),
    ?assertEqual([{table_select, rows, 2, [2]}], Events),
    assert_selection(NewTree, 2),
    ?assertMatch(#table{selected_row = 1}, nit_focus:find_element(NewTree, other)).

cell_click_controlled_rebuild_owns_selection_scroll_and_sort_test_() ->
    [?_test(begin
        Table = (cell_table())#table{controlled = true, rows = [[1], [2], [3], [4], [5]],
                                     scroll_offset = 1, sort_by = value, sort_dir = desc},
        Replacement = Table#table{selected_row = NextSelected, scroll_offset = 0,
                                   sort_by = undefined, sort_dir = asc},
        {Events, NewTree} = run(Table, [click(2)], #{replacement_tree => Replacement}),
        ?assertEqual([{table_cell_click, rows, 3, value, [3]}], Events),
        ?assertEqual(Replacement, NewTree)
    end) || NextSelected <- [0, 1, 3]].

cell_click_unhandled_keeps_native_selection_test() ->
    {Events, Tree} = run(cell_table(), [click(3)], #{cell_response => unhandled}),
    ?assertEqual([{table_cell_click, rows, 3, value, [3]}], Events),
    assert_selection(Tree, 3).

cell_click_opens_view_without_row_event_test_() ->
    [?_test(begin
        {Events, Tree} = run(cell_table(), [click(3)], #{open_view => Action}),
        ?assertEqual([{table_cell_click, rows, 3, value, [3]}], Events),
        ?assertEqual(#text{id = detail, content = <<"3">>}, Tree)
    end) || Action <- [rebuild, switch, push]].

cell_click_push_pop_preserves_selection_test() ->
    {Events, Tree} = run(cell_table(), [click(3), escape], #{open_view => push}),
    ?assertEqual([{table_cell_click, rows, 3, value, [3]}], Events),
    assert_selection(Tree, 3).

cell_click_can_open_modal_test() ->
    Table = cell_table(),
    Modal = #modal{id = detail, children = [#text{content = <<"Details">>}]},
    Ref = make_ref(),
    State = #{tree => Table, events => [], event_ref => Ref, cell_response => {modal, Modal}},
    try
        {NewState, NewTree, Modal} =
            nit_server:input_for_test(?MODULE, State, Table, undefined, click(3)),
        ?assertEqual([{table_cell_click, rows, 3, value, [3]}], take_events(Ref)),
        ?assertEqual([{table_cell_click, rows, 3, value, [3]}], maps:get(events, NewState)),
        assert_selection(NewTree, 3)
    after
        take_events(Ref)
    end.

scrolled_virtual_cell_click_has_absolute_index_and_full_data_test() ->
    Provider = fun(Start, Count) -> [[N, N * 10] || N <- lists:seq(Start + 1, Start + Count)] end,
    Table = (cell_table())#table{rows = [], total_rows = 20, row_provider = Provider,
                                scroll_offset = 99, activate_on_click = true},
    {Events, Tree} = run(Table, [click(2)]),
    ?assertEqual([{table_cell_click, rows, 18, value, [18, 180]}], Events),
    assert_selection(Tree, 18).

clickable_header_still_sorts_and_emits_only_header_event_test() ->
    Table = (cell_table())#table{show_header = true, header_separator = false,
                                sortable = true, rows = [[1], [4], [2], [3]]},
    {Events, Tree} = run(Table, [click(1), click(2)]),
    ?assertEqual([{table_header_click, rows, value},
                  {table_cell_click, rows, 1, value, [4]}], Events),
    ?assertMatch(#table{sort_by = value, sort_dir = desc, rows = [[4], [3], [2], [1]]}, Tree).

empty_and_outside_clicks_emit_no_cell_events_test() ->
    Table = (cell_table())#table{rows = [[1]], show_header = true, header_separator = true},
    Outside = {mouse, click, left, 21, 3},
    {Events, Tree} = run(Table, [click(2), click(4), Outside]),
    ?assertEqual([{event, Outside}], Events),
    assert_selection(Tree, 1),
    {EmptyEvents, _} = run(Table#table{rows = []}, [click(3)]),
    ?assertEqual([], EmptyEvents).

engine_delivers_cell_event_without_generic_wrapper_test() ->
    Ref = make_ref(),
    Event = {table_cell_click, rows, 2, value, [2]},
    State = #{tree => cell_table(), events => [], event_ref => Ref},
    try
        {noreply, NewState} = nit_engine:call_handler(?MODULE, Event, State),
        ?assertEqual([Event], take_events(Ref)),
        ?assertEqual([Event], maps:get(events, NewState))
    after
        take_events(Ref)
    end.

cell_table() ->
    (table())#table{clickable_columns = [value],
                    columns = [#table_col{id = value, width = 4},
                               #table_col{id = other, width = 4}]}.

table() ->
    #table{id = rows, focusable = true, width = 20, height = 4,
           show_header = false, selected_row = 1,
           columns = [#table_col{id = value, width = 20}], rows = [[1], [2], [3], [4]]}.

%% With no border/header and no scroll offset, screen row equals data row.
click(ScreenRow) ->
    {mouse, click, left, 2, ScreenRow}.

run(Tree, Events) ->
    run(Tree, Events, #{}).

run(Tree, Events, ExtraState) ->
    Ref = make_ref(),
    State = maps:merge(#{tree => Tree, events => [], event_ref => Ref}, ExtraState),
    try
        {NewState, NewTree, undefined} =
            nit_server:input_sequence_for_test(?MODULE, State, Tree, undefined, Events),
        Delivered = take_events(Ref),
        ?assertEqual(lists:reverse(maps:get(events, NewState)), Delivered),
        {Delivered, NewTree}
    after
        take_events(Ref)
    end.

take_events(Ref) ->
    receive
        {Ref, Event} -> [Event | take_events(Ref)]
    after 0 -> []
    end.

assert_selection(Tree, RowIdx) ->
    ?assertMatch(#table{selected_row = RowIdx}, nit_focus:find_element(Tree, rows)).