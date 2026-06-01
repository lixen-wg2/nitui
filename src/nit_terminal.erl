%%%-------------------------------------------------------------------
%%% @doc OTP 29 terminal backend for NitUI.
%%%
%%% Centralizes terminal control sequence rendering through stdlib's
%%% io_ansi module. Coordinates accepted by this module are 0-based.
%%% @end
%%%-------------------------------------------------------------------
-module(nit_terminal).

-export([alternate_screen/0, alternate_screen_off/0]).
-export([cursor_hide/0, cursor_show/0, cursor/2, clear/0, reset/0]).
-export([keypad_transmit_mode/0, keypad_transmit_mode_off/0]).
-export([mouse_mode/0, mouse_mode_off/0]).
-export([style/1, render/1, render/2, capabilities/0]).

-spec alternate_screen() -> unicode:chardata().
alternate_screen() ->
    io_ansi:alternate_screen().

-spec alternate_screen_off() -> unicode:chardata().
alternate_screen_off() ->
    io_ansi:alternate_screen_off().

-spec cursor_hide() -> unicode:chardata().
cursor_hide() ->
    io_ansi:cursor_hide().

-spec cursor_show() -> unicode:chardata().
cursor_show() ->
    io_ansi:cursor_show().

%% @doc Move to a 0-based row/column.
-spec cursor(integer(), integer()) -> unicode:chardata().
cursor(Row, Col) ->
    io_ansi:cursor(max(0, Row), max(0, Col)).

-spec clear() -> unicode:chardata().
clear() ->
    io_ansi:clear().

-spec reset() -> unicode:chardata().
reset() ->
    io_ansi:reset().

-spec keypad_transmit_mode() -> unicode:chardata().
keypad_transmit_mode() ->
    io_ansi:keypad_transmit_mode().

-spec keypad_transmit_mode_off() -> unicode:chardata().
keypad_transmit_mode_off() ->
    io_ansi:keypad_transmit_mode_off().

%% SGR mouse tracking is still outside io_ansi's higher-level API.
-spec mouse_mode() -> iodata().
mouse_mode() ->
    <<"\e[?1002h\e[?1006h">>.

-spec mouse_mode_off() -> iodata().
mouse_mode_off() ->
    <<"\e[?1006l\e[?1002l">>.

-spec style(map()) -> iolist().
style(Style) when map_size(Style) == 0 ->
    [];
style(Style) ->
    render(style_vts(Style)).

-spec render([io_ansi:vts() | unicode:chardata()]) -> iolist().
render(Data) ->
    render(Data, []).

-spec render([io_ansi:vts() | unicode:chardata()], io_ansi:options()) -> iolist().
render(Data, Options) ->
    io_ansi:render(Data, render_options(Options)).

-spec capabilities() -> map().
capabilities() ->
    #{
        ansi => io_ansi:enabled(user),
        color => color_enabled(),
        term_columns => io_ansi:tigetnum("cols"),
        term_lines => io_ansi:tigetnum("lines")
    }.

render_options(Options) ->
    %% Rendering is used both for live TTY output and headless tests. Force VTS
    %% emission here; callers can still inspect capabilities/0 separately.
    Options ++ [{reset, false}, {enabled, true}, {color, true}].

color_enabled() ->
    os:getenv("NO_COLOR") =:= false.

style_vts(Style) ->
    lists:filtermap(
        fun({Key, Value}) -> style_vts(Key, Value) end,
        maps:to_list(Style)).

style_vts(fg, Color) ->
    {true, fg_vts(Color)};
style_vts(bg, Color) ->
    {true, bg_vts(Color)};
style_vts(bold, true) ->
    {true, bold};
style_vts(dim, true) ->
    {true, dim};
style_vts(italic, true) ->
    {true, italic};
style_vts(underline, true) ->
    {true, underline};
style_vts(reverse, true) ->
    {true, inverse};
style_vts(_, _) ->
    false.

fg_vts(black) -> black;
fg_vts(red) -> red;
fg_vts(green) -> green;
fg_vts(yellow) -> yellow;
fg_vts(blue) -> blue;
fg_vts(magenta) -> magenta;
fg_vts(cyan) -> cyan;
fg_vts(white) -> white;
fg_vts(bright_black) -> light_black;
fg_vts(gray) -> light_black;
fg_vts(bright_red) -> light_red;
fg_vts(bright_green) -> light_green;
fg_vts(bright_yellow) -> light_yellow;
fg_vts(bright_blue) -> light_blue;
fg_vts(bright_magenta) -> light_magenta;
fg_vts(bright_cyan) -> light_cyan;
fg_vts(bright_white) -> light_white;
fg_vts(_) -> white.

bg_vts(black) -> black_background;
bg_vts(red) -> red_background;
bg_vts(green) -> green_background;
bg_vts(yellow) -> yellow_background;
bg_vts(blue) -> blue_background;
bg_vts(magenta) -> magenta_background;
bg_vts(cyan) -> cyan_background;
bg_vts(white) -> white_background;
bg_vts(bright_black) -> light_black_background;
bg_vts(gray) -> light_black_background;
bg_vts(bright_red) -> light_red_background;
bg_vts(bright_green) -> light_green_background;
bg_vts(bright_yellow) -> light_yellow_background;
bg_vts(bright_blue) -> light_blue_background;
bg_vts(bright_magenta) -> light_magenta_background;
bg_vts(bright_cyan) -> light_cyan_background;
bg_vts(bright_white) -> light_white_background;
bg_vts(_) -> black_background.
