%%%-------------------------------------------------------------------
%%% @doc Small formatting helpers for common TUI display values.
%%% @end
%%%-------------------------------------------------------------------
-module(nit_format).

-export([bytes/1, commas/1, duration/1]).

-spec commas(integer()) -> binary().
commas(N) when is_integer(N), N < 0 ->
    <<"-", (commas(-N))/binary>>;
commas(N) when is_integer(N) ->
    Digits = integer_to_list(N),
    list_to_binary(lists:join($,, group_digits(Digits, []))).

-spec bytes(undefined | integer()) -> binary().
bytes(undefined) ->
    <<"?">>;
bytes(Bytes) when is_integer(Bytes), Bytes < 0 ->
    <<"-", (bytes(-Bytes))/binary>>;
bytes(Bytes) when is_integer(Bytes) ->
    format_bytes(Bytes, [{1 bsl 40, <<"TB">>},
                         {1 bsl 30, <<"GB">>},
                         {1 bsl 20, <<"MB">>},
                         {1 bsl 10, <<"KB">>}]).

-spec duration(non_neg_integer()) -> binary().
duration(Secs) when is_integer(Secs), Secs < 0 ->
    <<"-", (duration(-Secs))/binary>>;
duration(Secs) when is_integer(Secs) ->
    Days = Secs div 86400,
    Hours = (Secs rem 86400) div 3600,
    Mins = (Secs rem 3600) div 60,
    RemSecs = Secs rem 60,
    case Days of
        0 ->
            iolist_to_binary(io_lib:format("~2..0B:~2..0B:~2..0B", [Hours, Mins, RemSecs]));
        _ ->
            iolist_to_binary(io_lib:format("~Bd ~2..0B:~2..0B:~2..0B",
                                           [Days, Hours, Mins, RemSecs]))
    end.

group_digits([], Acc) ->
    lists:reverse(Acc);
group_digits(Digits, Acc) ->
    Len = length(Digits),
    ChunkLen = case Len rem 3 of
        0 when Len >= 3 -> 3;
        0 -> Len;
        Rem -> Rem
    end,
    {Chunk, Rest} = lists:split(ChunkLen, Digits),
    group_digits(Rest, [Chunk | Acc]).

format_bytes(Bytes, []) ->
    iolist_to_binary(io_lib:format("~B B", [Bytes]));
format_bytes(Bytes, [{UnitSize, Suffix} | _Rest]) when Bytes >= UnitSize ->
    iolist_to_binary(io_lib:format("~.1f ~ts", [Bytes / UnitSize, Suffix]));
format_bytes(Bytes, [_ | Rest]) ->
    format_bytes(Bytes, Rest).
