%%%-------------------------------------------------------------------
%%% @doc Unit tests for nit_shortcuts.
%%% @end
%%%-------------------------------------------------------------------
-module(nit_shortcuts_tests).

-include_lib("eunit/include/eunit.hrl").

parse_printable_char_test() ->
    ?assertEqual({char, $q}, nit_shortcuts:parse(<<"Q">>)),
    ?assertEqual({char, $q}, nit_shortcuts:parse({event, {char, $Q}})).

parse_named_keys_test() ->
    ?assertEqual(enter, nit_shortcuts:parse(<<"Enter">>)),
    ?assertEqual(escape, nit_shortcuts:parse(escape)),
    ?assertEqual({key, page_down}, nit_shortcuts:parse(<<"PageDown">>)),
    ?assertEqual({ctrl, $c}, nit_shortcuts:parse(<<"Ctrl+C">>)).

matches_specs_test() ->
    ?assert(nit_shortcuts:matches({event, {char, $H}}, <<"h">>)),
    ?assert(nit_shortcuts:matches({event, escape}, [<<"q">>, escape])),
    ?assertNot(nit_shortcuts:matches({event, {char, $x}}, <<"q">>)).

handle_static_result_test() ->
    State = #{count => 1},
    ?assertEqual(
        {stop, normal, State},
        nit_shortcuts:handle({event, {char, $Q}}, State, [{<<"q">>, stop}])).

handle_fun_result_test() ->
    State = #{count => 1},
    Result = nit_shortcuts:handle({event, {char, $n}}, State, [
        {<<"n">>, fun(S) -> {noreply, S#{count => 2}} end}
    ]),
    ?assertEqual({noreply, #{count => 2}}, Result),
    ?assertEqual(nomatch, nit_shortcuts:handle({event, {char, $x}}, State, [])).
