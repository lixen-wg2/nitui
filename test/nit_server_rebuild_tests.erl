-module(nit_server_rebuild_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("nitui/include/nit_elements.hrl").

-export([view/1, handle_event/2]).

%% Callback used by the shared rebuild seam; also verify the view context.
view({ExpectedContext, NewTree}) ->
    ?assertEqual(ExpectedContext, erlang:get(nitui_view_tree)),
    NewTree;
view(#{tree := Tree}) ->
    Tree.

handle_event(Event, State = #{events := Events}) ->
    {noreply, State#{events := [Event | Events]}}.

async_default_merge_matches_tick_test() ->
    Old = nested(#table{id = table, rows = [[1], [2], [3]],
                        row_keys = [a, b, c], selected_row = 2, scroll_offset = 1}, 4),
    New = nested(#table{id = table, rows = [[30], [20], [10]],
                        row_keys = [b, c, a]}, 0),
    %% update/2 and send_event/2 rebuild with undefined; ticks supply OldTree.
    Async = nit_server:rebuild_for_test(?MODULE, {Old, New}, Old, undefined),
    Tick = nit_server:rebuild_for_test(?MODULE, {Old, New}, Old, Old),
    ?assertEqual(Tick, Async),
    ?assertMatch(#table{selected_row = 1, scroll_offset = 1, rows = [[30], [20], [10]]},
                 nit_focus:find_element(Async, table)),
    ?assertMatch(#scroll{offset = 4}, nit_focus:find_element(Async, scroll)).

async_controlled_view_overrides_old_state_test() ->
    OldTable = #table{id = table, rows = [[1], [2], [3]], row_keys = [a, b, c],
                      selected_row = 3, scroll_offset = 2, sortable = true,
                      sort_by = value, sort_dir = desc},
    NewTable = OldTable#table{controlled = true, selected_row = 0, scroll_offset = 0,
                              sort_by = undefined, sort_dir = asc},
    Old = nested(OldTable, 4),
    New = nested(NewTable, 0),
    lists:foreach(fun(Source) ->
        Rebuilt = nit_server:rebuild_for_test(?MODULE, {Old, New}, Old, Source),
        ?assertEqual(NewTable, nit_focus:find_element(Rebuilt, table))
    end, [undefined, Old]).

explicit_merge_source_wins_test() ->
    Old = #table{id = table, rows = [[1], [2]], selected_row = 1},
    Edited = Old#table{selected_row = 2},
    New = Old#table{selected_row = 0},
    Rebuilt = nit_server:rebuild_for_test(?MODULE, {Edited, New}, Old, Edited),
    ?assertEqual(2, Rebuilt#table.selected_row).

non_input_edit_keys_forwarded_test_() ->
    [?_test(begin
        State = #{tree => Tree, events => []},
        {NewState, NewTree, undefined} =
            nit_server:input_for_test(?MODULE, State, Tree, undefined, Event),
        ?assertEqual([{event, Event}], maps:get(events, NewState)),
        ?assertEqual(Tree, NewTree)
    end) || Event <- [backspace, delete],
            Tree <- [#text{content = <<"Manual command">>},
                     #box{id = box, focusable = true, children = [
                         #button{id = button, focusable = true, label = <<"Run">>},
                         #input{id = input, focusable = true, value = <<"abc">>,
                                cursor_pos = 1}]}]].

focused_input_edit_keys_consumed_test_() ->
    [?_test(begin
        Tree = input_tree(<<"abc">>, 1),
        State = #{tree => Tree, events => []},
        {NewState, NewTree, undefined} =
            nit_server:input_for_test(?MODULE, State, Tree, undefined, Event),
        ?assertEqual([{input, input, Value}], maps:get(events, NewState)),
        ?assertEqual(input_tree(Value, Pos), NewTree)
    end) || {Event, Value, Pos} <- [{backspace, <<"bc">>, 0}, {delete, <<"ac">>, 1}]].

focused_input_boundary_keys_consumed_test_() ->
    [?_test(begin
        Tree = input_tree(Value, Pos),
        State = #{tree => Tree, events => []},
        ?assertEqual({State, Tree, undefined},
                     nit_server:input_for_test(?MODULE, State, Tree, undefined, Event))
    end) || {Event, Value, Pos} <- [{backspace, <<"abc">>, 0}, {delete, <<"abc">>, 3},
                                   {backspace, <<>>, 0}, {delete, <<>>, 0}]].

modal_edit_keys_isolated_test_() ->
    [?_test(begin
        Tree = input_tree(<<"abc">>, 1),
        Modal = #modal{children = [#button{id = close, focusable = true,
                                          label = <<"Close">>}]},
        State = #{tree => Tree, events => []},
        ?assertEqual({State, Tree, Modal},
                     nit_server:input_for_test(?MODULE, State, Tree, Modal, Event))
    end) || Event <- [backspace, delete]].

modal_input_edit_keys_consumed_test_() ->
    [?_test(begin
        Tree = input_tree(<<"main">>, 1),
        Modal = #modal{children = [input_tree(<<"abc">>, 1)]},
        State = #{tree => Tree, events => []},
        {NewState, NewTree, NewModal} =
            nit_server:input_for_test(?MODULE, State, Tree, Modal, Event),
        ?assertEqual([{input, input, Value}], maps:get(events, NewState)),
        ?assertEqual(Tree, NewTree),
        ?assertEqual(Modal#modal{children = [input_tree(Value, Pos)]}, NewModal)
    end) || {Event, Value, Pos} <- [{backspace, <<"bc">>, 0}, {delete, <<"ac">>, 1}]].

input_tree(Value, Pos) ->
    #box{id = box, focusable = true, children = [
        #input{id = input, focusable = true, value = Value, cursor_pos = Pos}
    ]}.

anonymous_layout_does_not_shadow_table_activation_test() ->
    Table = #table{id = rows, focusable = true, selected_row = 1, rows = [[1]]},
    Tree = #vbox{children = [#text{content = <<"anonymous">>}, Table]},
    ?assertEqual(Table, nit_engine:activation_target(Tree, rows, undefined)).

nested(Table, Offset) ->
    #tabs{id = tabs, active_tab = tab, tabs = [
        #tab{id = tab, content = [#scroll{id = scroll, offset = Offset, children = [Table]}]}
    ]}.