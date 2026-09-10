-module(nit_input_rebuild_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("nitui/include/nit_elements.hrl").

-export([view/1, handle_event/2]).

view(#{tree := Tree}) -> Tree.
handle_event({event, enter_fullscreen}, State) ->
    {fullscreen, form, State};
handle_event({event, exit_and_reset}, State = #{next_tree := Next}) ->
    {exit_fullscreen, State#{tree => Next}};
handle_event(Event, State = #{next_tree := Next}) ->
    {noreply, State#{tree => Next, event => Event}}.

submit_clears_value_cursor_and_selection_test() ->
    Old = form(typed_input()),
    New = form(empty_input()),
    {US, Result, undefined} = nit_server:input_for_test(
        ?MODULE, #{tree => Old, next_tree => New}, Old, undefined, enter),
    ?assertEqual({submit, input, <<"typed">>, undefined}, maps:get(event, US)),
    ?assertEqual(empty_input(), nit_focus:find_element(Result, input)).

button_callback_replaces_input_test() ->
    Button = #button{id = reset, focusable = true, label = <<"Reset">>},
    Old = #box{id = form, focusable = true, children = [Button, typed_input()]},
    Replacement = (empty_input())#input{value = <<"replacement">>, cursor_pos = 3},
    New = Old#box{children = [Button, Replacement]},
    {US, Result, undefined} = nit_server:input_for_test(
        ?MODULE, #{tree => Old, next_tree => New}, Old, undefined, enter),
    ?assertEqual({click, reset, undefined}, maps:get(event, US)),
    ?assertEqual(Replacement, nit_focus:find_element(Result, input)).

async_input_reset_preserves_other_native_state_test() ->
    Table = #table{id = table, rows = [[1], [2], [3]], selected_row = 2},
    Tree = #tree{id = tree, nodes = [#tree_node{id = root}], selected = root,
                 selection_request = {once, root}, selection_request_applied = {once, root}},
    List = #list{id = list, items = [<<"a">>, <<"b">>], selected = 1},
    Old = #scroll{id = scroll, offset = 3, children = [
        #vbox{children = [typed_input(), Table, Tree, List]}]},
    New = #scroll{id = scroll, offset = 0, children = [
        #vbox{children = [empty_input(), Table#table{selected_row = 0},
                         Tree#tree{selected = undefined}, List#list{selected = 0}]}]},
    Result = nit_server:rebuild_for_test(?MODULE, #{tree => New}, Old, undefined),
    ?assertEqual(empty_input(), nit_focus:find_element(Result, input)),
    ?assertEqual(Table, nit_focus:find_element(Result, table)),
    ?assertEqual(Tree, nit_focus:find_element(Result, tree)),
    ?assertEqual(List, nit_focus:find_element(Result, list)),
    ?assertMatch(#scroll{offset = 3}, Result).

tick_and_native_navigation_preserve_input_test() ->
    Old = form(typed_input()),
    New = form(empty_input()),
    Result = nit_server:rebuild_for_test(?MODULE, #{tree => New}, Old, Old),
    ?assertEqual(typed_input(), nit_focus:find_element(Result, input)),
    ?assertEqual(Old, nit_tree:merge_state(Old, New)).

fullscreen_submit_and_exit_reset_inputs_test_() ->
    [?_test(begin
        Old = #vbox{children = [form(typed_input())]},
        New = #vbox{children = [form(empty_input())]},
        {_, Result, undefined} = nit_server:input_sequence_for_test(
            ?MODULE, #{tree => Old, next_tree => New}, Old, undefined,
            [enter_fullscreen, Event]),
        ?assertEqual(empty_input(), nit_focus:find_element(Result, input))
    end) || Event <- [enter, exit_and_reset]].

async_reset_inside_every_container_test_() ->
    [?_test(begin
        Old = Wrap(typed_input()),
        New = Wrap(empty_input()),
        Result = nit_server:rebuild_for_test(?MODULE, #{tree => New}, Old, undefined),
        ?assertEqual(New, Result)
    end) || Wrap <- [
        fun(I) -> #panel{children = [I]} end,
        fun(I) -> #box{children = [I]} end,
        fun(I) -> #vbox{children = [I]} end,
        fun(I) -> #hbox{children = [I]} end,
        fun(I) -> #scroll{children = [I]} end,
        fun(I) -> #modal{children = [I]} end,
        fun(I) -> #tabs{active_tab = first, tabs = [
            #tab{id = first}, #tab{id = inactive, content = [I]}]} end
    ]].

form(Input) -> #box{id = form, focusable = true, children = [Input]}.
typed_input() -> #input{id = input, focusable = true, value = <<"typed">>,
                         cursor_pos = 5, selection_anchor = 1}.
empty_input() -> #input{id = input, focusable = true, value = <<>>, cursor_pos = 0}.