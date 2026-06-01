%%%-------------------------------------------------------------------
%%% @doc Shortcut parsing and declarative shortcut dispatch helpers.
%%% @end
%%%-------------------------------------------------------------------
-module(nit_shortcuts).

-export([parse/1, matches/2, handle/3]).

-type normalized_event() :: enter
                          | tab
                          | btab
                          | escape
                          | backspace
                          | {char, char()}
                          | {ctrl, char()}
                          | {key, atom()}.

-spec parse(term()) -> normalized_event() | undefined.
parse({event, Event}) ->
    parse(Event);
parse({char, Char}) when is_integer(Char), Char >= 32 ->
    {char, lower_char(Char)};
parse({ctrl, Char}) when is_integer(Char) ->
    {ctrl, lower_char(Char)};
parse({key, Key}) when is_atom(Key) ->
    {key, Key};
parse(enter) ->
    enter;
parse(tab) ->
    tab;
parse(btab) ->
    btab;
parse(escape) ->
    escape;
parse(backspace) ->
    backspace;
parse(Char) when is_integer(Char), Char >= 32 ->
    {char, lower_char(Char)};
parse(Bin) when is_binary(Bin) ->
    parse_text(Bin);
parse(List) when is_list(List) ->
    parse_text(unicode:characters_to_binary(List));
parse(Atom) when is_atom(Atom) ->
    parse_text(atom_to_binary(Atom, utf8));
parse(_) ->
    undefined.

-spec matches(term(), term()) -> boolean().
matches(Event, Specs) when is_list(Specs), Specs =/= [], not is_integer(hd(Specs)) ->
    lists:any(fun(Spec) -> matches(Event, Spec) end, Specs);
matches(Event, Spec) ->
    case {parse(Event), parse(Spec)} of
        {Parsed, Parsed} when Parsed =/= undefined -> true;
        _ -> false
    end.

-spec handle(term(), State, [{term(), term() | fun((State) -> term())}]) -> nomatch | term().
handle(Event, State, Bindings) ->
    case lists:dropwhile(
        fun({Spec, _Action}) ->
            not matches(Event, Spec)
        end,
        Bindings) of
        [{_Spec, Action} | _] ->
            apply_action(Action, State);
        [] ->
            nomatch
    end.

apply_action(Action, State) when is_function(Action, 1) ->
    Action(State);
apply_action(stop, State) ->
    {stop, normal, State};
apply_action({stop, Reason}, State) ->
    {stop, Reason, State};
apply_action(Result, _State) ->
    Result.

parse_text(Bin) ->
    Normalized = unicode:characters_to_binary(
        string:lowercase(unicode:characters_to_list(Bin))),
    case unicode:characters_to_list(Normalized) of
        [Char] when Char >= 32 ->
            {char, Char};
        _ ->
            parse_named_text(Normalized)
    end.

parse_named_text(<<"enter">>) -> enter;
parse_named_text(<<"tab">>) -> tab;
parse_named_text(<<"shift+tab">>) -> btab;
parse_named_text(<<"esc">>) -> escape;
parse_named_text(<<"escape">>) -> escape;
parse_named_text(<<"backspace">>) -> backspace;
parse_named_text(<<"up">>) -> {key, up};
parse_named_text(<<"arrowup">>) -> {key, up};
parse_named_text(<<"down">>) -> {key, down};
parse_named_text(<<"arrowdown">>) -> {key, down};
parse_named_text(<<"left">>) -> {key, left};
parse_named_text(<<"arrowleft">>) -> {key, left};
parse_named_text(<<"right">>) -> {key, right};
parse_named_text(<<"arrowright">>) -> {key, right};
parse_named_text(<<"home">>) -> {key, home};
parse_named_text(<<"end">>) -> {key, 'end'};
parse_named_text(<<"pageup">>) -> {key, page_up};
parse_named_text(<<"pagedown">>) -> {key, page_down};
parse_named_text(<<"f1">>) -> {key, f1};
parse_named_text(<<"f2">>) -> {key, f2};
parse_named_text(<<"f3">>) -> {key, f3};
parse_named_text(<<"f4">>) -> {key, f4};
parse_named_text(<<"f5">>) -> {key, f5};
parse_named_text(<<"f6">>) -> {key, f6};
parse_named_text(<<"f7">>) -> {key, f7};
parse_named_text(<<"f8">>) -> {key, f8};
parse_named_text(<<"f9">>) -> {key, f9};
parse_named_text(<<"f10">>) -> {key, f10};
parse_named_text(<<"f11">>) -> {key, f11};
parse_named_text(<<"f12">>) -> {key, f12};
parse_named_text(<<"ctrl+", Rest/binary>>) ->
    case unicode:characters_to_list(Rest) of
        [Char] -> {ctrl, lower_char(Char)};
        _ -> undefined
    end;
parse_named_text(_) -> undefined.

lower_char(Char) ->
    [Lower] = string:lowercase([Char]),
    Lower.
