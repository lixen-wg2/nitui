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
                   State = #{open_view := Action, events := Events}) ->
    %% No table_select may run before an activation that navigates away.
    ?assertEqual([], Events),
    NewState = State#{events := [Event]},
    DetailState = NewState#{tree := #text{id = detail, content = integer_to_binary(RowIdx)}},
    case Action of
        rebuild -> {noreply, DetailState#{expected_selection => {RowIdx, RowData}}};
        switch -> {switch, ?MODULE, DetailState};
        push -> {push, ?MODULE, DetailState,
                 NewState#{expected_selection => {RowIdx, RowData}}}
    end;
handle_table_event(Event = {Kind, rows, RowIdx, RowData}, State = #{events := Events})
        when Kind =:= table_select; Kind =:= table_activate ->
    {noreply, State#{events := [Event | Events], expected_selection => {RowIdx, RowData}}};
handle_table_event(Event, State = #{events := Events}) ->
    {noreply, State#{events := [Event | Events]}}.

activate_on_click_is_appended_and_opt_in_test() ->
    Table = #table{},
    ?assertEqual(false, Table#table.activate_on_click),
    ?assertEqual(#table.focused_selected_style + 1, #table.activate_on_click),
    ?assertEqual(#table.activate_on_click, tuple_size(Table)).

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