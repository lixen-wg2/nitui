-module(nit_text_view_input_integration_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("nitui/include/nit_elements.hrl").

-export([view/1, handle_event/2]).

view(#{tree := Tree}) -> Tree.
handle_event(Event, State = #{ref := Ref}) ->
    self() ! {Ref, {callback, Event}},
    {noreply, State}.

classic_shift_sequences_test_() ->
    [?_test(begin
        Expected = [{key, {shift, Direction}}],
        ?assertEqual(Expected, parse([Sequence])),
        %% Split inside the CSI parameters to exercise retained parser state.
        <<Prefix:4/binary, Suffix/binary>> = Sequence,
        ?assertEqual(Expected, parse([Prefix, Suffix]))
    end) || {Sequence, Direction} <- [
        {<<"\e[1;2A">>, up}, {<<"\e[1;2B">>, down},
        {<<"\e[1;2C">>, right}, {<<"\e[1;2D">>, left},
        {<<"\e[1;2H">>, home}, {<<"\e[1;2F">>, 'end'},
        {<<"\e[1;2~">>, home}, {<<"\e[4;2~">>, 'end'},
        {<<"\e[7;2~">>, home}, {<<"\e[8;2~">>, 'end'},
        {<<"\e[5;2~">>, page_up}, {<<"\e[6;2~">>, page_down}
    ]].

parsed_sgr_release_ends_viewer_drag_test() ->
    View = viewer(),
    Events = parse([<<"\e[<0;2;1M\e[<32;5;1M\e[<0;5;1m\e[<32;9;1M">>]),
    {Tree, Log} = run(View, Events),
    ?assertMatch(#text_view{cursor_pos = 4, selection_anchor = 1}, Tree),
    ?assertEqual([], Log).

parsed_bracketed_paste_never_copies_or_navigates_viewer_test() ->
    View = viewer(),
    Events = parse([<<"\e[200~qYy">>, <<1, 127, "\e[A">>, <<"\e[201~\e[1;2C">>]),
    {Tree, Log} = run(View, Events),
    ?assertMatch(#text_view{cursor_pos = 1, selection_anchor = 0}, Tree),
    ?assertEqual(View#text_view.content, Tree#text_view.content),
    ?assertEqual([], Log).

parsed_typing_and_paste_keep_input_editing_test() ->
    Input = #input{id = input, focusable = true},
    Tree = #box{id = box, focusable = true, children = [Input]},
    Events = parse([<<"a\e[200~Yyq\e[201~">>]),
    {NewTree, Log} = run(Tree, Events),
    ?assertMatch(#input{value = <<"aYyq">>}, nit_focus:find_element(NewTree, input)),
    ?assertEqual([{callback, {input, input, <<"a">>}},
                  {callback, {input, input, <<"aY">>}},
                  {callback, {input, input, <<"aYy">>}},
                  {callback, {input, input, <<"aYyq">>}}], Log).

viewer_shortcuts_only_apply_when_focused_test() ->
    Input = #input{id = input, focusable = true},
    Tree = #box{id = box, focusable = true, children = [Input, (viewer())#text_view{y = 2}]},
    {NewTree, Log} = run(Tree, parse([<<"yY">>])),
    ?assertMatch(#input{value = <<"yY">>}, nit_focus:find_element(NewTree, input)),
    ?assertEqual([{callback, {input, input, <<"y">>}},
                  {callback, {input, input, <<"yY">>}}], Log).

viewer() ->
    #text_view{id = viewer, focusable = true, content = <<"abcdefghij">>,
                width = 20, height = 3, show_toolbar = false}.

parse(Chunks) ->
    {ok, Pid} = nit_input:start_link(),
    try
        nit_input:set_target(self()),
        lists:foreach(fun nit_input:handle_data/1, Chunks),
        %% A synchronous call from the same sender is a deterministic barrier.
        gen_server:call(Pid, parser_barrier),
        input_events()
    after nit_input:stop() end.

input_events() ->
    receive {input, Event} -> [Event | input_events()] after 0 -> [] end.

run(Tree, Events) ->
    ?assertEqual(undefined, whereis(nit_tty)),
    true = register(nit_tty, self()),
    Ref = make_ref(),
    Copy = fun(Text) -> self() ! {Ref, {copy, Text}}, {ok, sent} end,
    try
        {_, NewTree, undefined} = nit_server:input_sequence_for_test(
            ?MODULE, #{tree => Tree, ref => Ref}, Tree, undefined, Events,
            #{clipboard_copy => Copy}),
        {NewTree, drain(Ref)}
    after
        unregister(nit_tty), drain(Ref), drain_writes()
    end.

drain(Ref) -> receive {Ref, E} -> [E | drain(Ref)] after 0 -> [] end.
drain_writes() -> receive {'$gen_cast', {write, _}} -> drain_writes() after 0 -> ok end.