%%%-------------------------------------------------------------------
%%% @doc Unicode display helpers for terminal rendering.
%%% @end
%%%-------------------------------------------------------------------
-module(nit_unicode).

-export([to_charlist/1, display_width/1, truncate/2, contains_wide/1]).

-spec to_charlist(iodata()) -> [char()].
to_charlist(Content) ->
    case unicode:characters_to_list(Content) of
        Chars when is_list(Chars) -> Chars;
        {incomplete, Chars, _Rest} -> Chars;
        {error, Chars, _Rest} -> Chars
    end.

-spec display_width(iodata()) -> non_neg_integer().
display_width(Content) ->
    lists:sum([char_width(Char) || Char <- to_charlist(Content)]).

-spec truncate(iodata(), integer()) -> binary().
truncate(_Content, MaxWidth) when MaxWidth =< 0 ->
    <<>>;
truncate(Content, MaxWidth) ->
    unicode:characters_to_binary(truncate_chars(to_charlist(Content), MaxWidth, [])).

-spec contains_wide(iodata()) -> boolean().
contains_wide(Content) ->
    contains_wide_iodata(Content).

contains_wide_iodata(Bin) when is_binary(Bin) ->
    contains_wide_binary(Bin);
contains_wide_iodata(Char) when is_integer(Char) ->
    char_width(Char) > 1;
contains_wide_iodata([Head | Rest]) ->
    contains_wide_iodata(Head) orelse contains_wide_iodata(Rest);
contains_wide_iodata([]) ->
    false;
contains_wide_iodata(_) ->
    false.

contains_wide_binary(<<>>) ->
    false;
contains_wide_binary(<<Char/utf8, Rest/binary>>) ->
    char_width(Char) > 1 orelse contains_wide_binary(Rest);
contains_wide_binary(<<_Invalid, Rest/binary>>) ->
    contains_wide_binary(Rest).

truncate_chars([], _Remaining, Acc) ->
    lists:reverse(Acc);
truncate_chars([Char | Rest], Remaining, Acc) ->
    Width = char_width(Char),
    case Width of
        0 ->
            truncate_chars(Rest, Remaining, [Char | Acc]);
        _ when Width =< Remaining ->
            truncate_chars(Rest, Remaining - Width, [Char | Acc]);
        _ ->
            lists:reverse(Acc)
    end.

char_width(Char) when Char < 32 ->
    0;
char_width(Char) when is_integer(Char, 16#7F, 16#9F) ->
    0;
char_width(16#200D) ->
    0;
char_width(Char) when is_integer(Char, 16#0300, 16#036F) ->
    0;
char_width(Char) when is_integer(Char, 16#1AB0, 16#1AFF) ->
    0;
char_width(Char) when is_integer(Char, 16#1DC0, 16#1DFF) ->
    0;
char_width(Char) when is_integer(Char, 16#20D0, 16#20FF) ->
    0;
char_width(Char) when is_integer(Char, 16#FE00, 16#FE0F) ->
    0;
char_width(Char) when is_integer(Char, 16#FE20, 16#FE2F) ->
    0;
char_width(Char) when is_integer(Char, 16#E0100, 16#E01EF) ->
    0;
char_width(Char) when is_integer(Char, 16#1F3FB, 16#1F3FF) ->
    0;
char_width(Char) when is_integer(Char, 16#1100, 16#115F) ->
    2;
char_width(Char) when is_integer(Char, 16#2329, 16#232A) ->
    2;
char_width(Char) when is_integer(Char, 16#2E80, 16#A4CF) ->
    2;
char_width(Char) when is_integer(Char, 16#AC00, 16#D7A3) ->
    2;
char_width(Char) when is_integer(Char, 16#F900, 16#FAFF) ->
    2;
char_width(Char) when is_integer(Char, 16#FE10, 16#FE19) ->
    2;
char_width(Char) when is_integer(Char, 16#FE30, 16#FE6F) ->
    2;
char_width(Char) when is_integer(Char, 16#FF01, 16#FF60) ->
    2;
char_width(Char) when is_integer(Char, 16#FFE0, 16#FFE6) ->
    2;
char_width(Char) when is_integer(Char, 16#1F000, 16#1FAFF) ->
    2;
char_width(_) ->
    1.
