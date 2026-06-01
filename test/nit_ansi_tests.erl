%%%-------------------------------------------------------------------
%%% @doc Unit tests for nit_ansi module.
%%%
%%% Tests ANSI escape sequence generation including:
%%% - Cursor movement
%%% - Style codes (colors, bold, dim, etc.)
%%% - Text truncation
%%% - Border characters
%%% @end
%%%-------------------------------------------------------------------
-module(nit_ansi_tests).

-include_lib("eunit/include/eunit.hrl").

%%====================================================================
%% move_to tests
%%====================================================================

move_to_origin_test() ->
    ?assertEqual(<<"\e[1;1H">>, nit_ansi:move_to(0, 0)).

move_to_position_test() ->
    ?assertEqual(<<"\e[10;20H">>, nit_ansi:move_to(9, 19)).

move_to_large_position_test() ->
    ?assertEqual(<<"\e[100;200H">>, nit_ansi:move_to(99, 199)).

%%====================================================================
%% style_to_ansi tests
%%====================================================================

style_empty_map_test() ->
    ?assertEqual([], nit_ansi:style_to_ansi(#{})).

style_bold_test() ->
    Result = iolist_to_binary(nit_ansi:style_to_ansi(#{bold => true})),
    ?assertEqual(<<"\e[1m">>, Result).

style_dim_test() ->
    Result = iolist_to_binary(nit_ansi:style_to_ansi(#{dim => true})),
    ?assertEqual(<<"\e[2m">>, Result).

style_italic_test() ->
    Result = iolist_to_binary(nit_ansi:style_to_ansi(#{italic => true})),
    ?assertEqual(<<"\e[3m">>, Result).

style_underline_test() ->
    Result = iolist_to_binary(nit_ansi:style_to_ansi(#{underline => true})),
    ?assertEqual(<<"\e[4m">>, Result).

style_fg_red_test() ->
    Result = iolist_to_binary(nit_ansi:style_to_ansi(#{fg => red})),
    ?assertEqual(<<"\e[31m">>, Result).

style_fg_green_test() ->
    Result = iolist_to_binary(nit_ansi:style_to_ansi(#{fg => green})),
    ?assertEqual(<<"\e[32m">>, Result).

style_bg_blue_test() ->
    Result = iolist_to_binary(nit_ansi:style_to_ansi(#{bg => blue})),
    ?assertEqual(<<"\e[44m">>, Result).

style_bg_cyan_test() ->
    Result = iolist_to_binary(nit_ansi:style_to_ansi(#{bg => cyan})),
    ?assertEqual(<<"\e[46m">>, Result).

style_bright_colors_test() ->
    FgResult = iolist_to_binary(nit_ansi:style_to_ansi(#{fg => bright_red})),
    ?assertEqual(<<"\e[91m">>, FgResult),
    BgResult = iolist_to_binary(nit_ansi:style_to_ansi(#{bg => bright_green})),
    ?assertEqual(<<"\e[102m">>, BgResult).

style_false_value_ignored_test() ->
    ?assertEqual([], nit_ansi:style_to_ansi(#{bold => false})).

style_unknown_key_ignored_test() ->
    ?assertEqual([], nit_ansi:style_to_ansi(#{unknown => true})).

%%====================================================================
%% reset_style tests
%%====================================================================

reset_style_test() ->
    ?assertEqual(<<"\e(B\e[m">>, nit_ansi:reset_style()).

%%====================================================================
%% truncate_content tests
%%====================================================================

truncate_short_content_test() ->
    ?assertEqual(<<"hello">>, nit_ansi:truncate_content(<<"hello">>, 10)).

truncate_exact_content_test() ->
    ?assertEqual(<<"hello">>, nit_ansi:truncate_content(<<"hello">>, 5)).

truncate_long_content_test() ->
    ?assertEqual(<<"hel">>, nit_ansi:truncate_content(<<"hello">>, 3)).

truncate_zero_width_test() ->
    ?assertEqual(<<>>, nit_ansi:truncate_content(<<"hello">>, 0)).

truncate_negative_width_test() ->
    ?assertEqual(<<>>, nit_ansi:truncate_content(<<"hello">>, -5)).

truncate_iolist_test() ->
    ?assertEqual(<<"hel">>, nit_ansi:truncate_content([<<"he">>, <<"llo">>], 3)).

truncate_unicode_charlist_test() ->
    ?assertEqual(<<"  ↑/↓"/utf8>>, nit_ansi:truncate_content("  ↑/↓    - Navigate", 5)).

truncate_unicode_charlist_full_width_test() ->
    ?assertEqual(<<"↑/↓"/utf8>>, nit_ansi:truncate_content("↑/↓", 3)).

truncate_emoji_respects_display_width_test() ->
    ?assertEqual(<<"📦Wo"/utf8>>, nit_ansi:truncate_content(<<"📦Worker"/utf8>>, 4)).

%%====================================================================
%% repeat_bin tests
%%====================================================================

repeat_bin_zero_test() ->
    ?assertEqual([], nit_ansi:repeat_bin(<<"x">>, 0)).

repeat_bin_negative_test() ->
    ?assertEqual([], nit_ansi:repeat_bin(<<"x">>, -1)).

repeat_bin_once_test() ->
    ?assertEqual([<<"x">>], nit_ansi:repeat_bin(<<"x">>, 1)).

repeat_bin_multiple_test() ->
    Result = nit_ansi:repeat_bin(<<"ab">>, 3),
    ?assertEqual([<<"ab">>, <<"ab">>, <<"ab">>], Result).

%%====================================================================
%% border_chars tests
%%====================================================================

border_chars_single_test() ->
    {TL, TR, BL, BR, HZ, VT} = nit_ansi:border_chars(single),
    ?assertEqual(<<"┌"/utf8>>, TL),
    ?assertEqual(<<"┐"/utf8>>, TR),
    ?assertEqual(<<"└"/utf8>>, BL),
    ?assertEqual(<<"┘"/utf8>>, BR),
    ?assertEqual(<<"─"/utf8>>, HZ),
    ?assertEqual(<<"│"/utf8>>, VT).

border_chars_double_test() ->
    {TL, TR, BL, BR, HZ, VT} = nit_ansi:border_chars(double),
    ?assertEqual(<<"╔"/utf8>>, TL),
    ?assertEqual(<<"╗"/utf8>>, TR),
    ?assertEqual(<<"╚"/utf8>>, BL),
    ?assertEqual(<<"╝"/utf8>>, BR),
    ?assertEqual(<<"═"/utf8>>, HZ),
    ?assertEqual(<<"║"/utf8>>, VT).

border_chars_rounded_test() ->
    {TL, TR, _BL, _BR, _HZ, _VT} = nit_ansi:border_chars(rounded),
    ?assertEqual(<<"╭"/utf8>>, TL),
    ?assertEqual(<<"╮"/utf8>>, TR).

border_chars_unknown_defaults_to_single_test() ->
    {TL, _, _, _, _, _} = nit_ansi:border_chars(unknown),
    ?assertEqual(<<"┌"/utf8>>, TL).

%%====================================================================
%% resolve_size tests
%%====================================================================

resolve_size_auto_test() ->
    ?assertEqual(80, nit_ansi:resolve_size(auto, 80)).

resolve_size_fixed_test() ->
    ?assertEqual(40, nit_ansi:resolve_size(40, 80)).
