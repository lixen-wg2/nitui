%%%-------------------------------------------------------------------
%%% @doc NitUI ANSI Helpers
%%%
%%% Common ANSI escape sequence utilities used by element modules.
%%% @end
%%%-------------------------------------------------------------------
-module(iso_ansi).

-export([move_to/2, style_to_ansi/1, reset_style/0]).
-export([truncate_content/2, repeat_bin/2]).
-export([border_chars/1, render_title_line/3, render_box_border/7]).
-export([resolve_size/2]).

%%====================================================================
%% Cursor Movement
%%====================================================================

%% @doc Move cursor to row, col (1-based)
-spec move_to(integer(), integer()) -> binary().
move_to(Row, Col) ->
    iolist_to_binary(io_lib:format("\e[~B;~BH", [Row, Col])).

%%====================================================================
%% Style Handling
%%====================================================================

-spec style_to_ansi(map()) -> iolist().
style_to_ansi(Style) when map_size(Style) == 0 ->
    [];
style_to_ansi(Style) ->
    Codes = lists:filtermap(
        fun({Key, Value}) -> style_code(Key, Value) end,
        maps:to_list(Style)
    ),
    case Codes of
        [] -> [];
        _ -> [<<"\e[">>, lists:join($;, Codes), <<"m">>]
    end.

style_code(fg, Color) -> {true, fg_code(Color)};
style_code(bg, Color) -> {true, bg_code(Color)};
style_code(bold, true) -> {true, <<"1">>};
style_code(dim, true) -> {true, <<"2">>};
style_code(italic, true) -> {true, <<"3">>};
style_code(underline, true) -> {true, <<"4">>};
style_code(_, _) -> false.

fg_code(black) -> <<"30">>; fg_code(red) -> <<"31">>; fg_code(green) -> <<"32">>;
fg_code(yellow) -> <<"33">>; fg_code(blue) -> <<"34">>; fg_code(magenta) -> <<"35">>;
fg_code(cyan) -> <<"36">>; fg_code(white) -> <<"37">>;
fg_code(bright_black) -> <<"90">>; fg_code(bright_red) -> <<"91">>;
fg_code(bright_green) -> <<"92">>; fg_code(bright_yellow) -> <<"93">>;
fg_code(bright_blue) -> <<"94">>; fg_code(bright_magenta) -> <<"95">>;
fg_code(bright_cyan) -> <<"96">>; fg_code(bright_white) -> <<"97">>;
fg_code(_) -> <<"37">>.

bg_code(black) -> <<"40">>; bg_code(red) -> <<"41">>; bg_code(green) -> <<"42">>;
bg_code(yellow) -> <<"43">>; bg_code(blue) -> <<"44">>; bg_code(magenta) -> <<"45">>;
bg_code(cyan) -> <<"46">>; bg_code(white) -> <<"47">>;
bg_code(bright_black) -> <<"100">>; bg_code(bright_red) -> <<"101">>;
bg_code(bright_green) -> <<"102">>; bg_code(bright_yellow) -> <<"103">>;
bg_code(bright_blue) -> <<"104">>; bg_code(bright_magenta) -> <<"105">>;
bg_code(bright_cyan) -> <<"106">>; bg_code(bright_white) -> <<"107">>;
bg_code(_) -> <<"40">>.

-spec reset_style() -> binary().
reset_style() ->
    <<"\e[0m">>.

%%====================================================================
%% Text Helpers
%%====================================================================

%% @doc Truncate content to fit within MaxWidth
-spec truncate_content(iodata(), integer()) -> binary().
truncate_content(_Content, MaxWidth) when MaxWidth =< 0 ->
    <<>>;
truncate_content(Content, MaxWidth) ->
    iso_unicode:truncate(Content, MaxWidth).

%% @doc Repeat a binary N times
-spec repeat_bin(binary(), integer()) -> iolist().
repeat_bin(_Bin, N) when N =< 0 -> [];
repeat_bin(Bin, N) -> [Bin || _ <- lists:seq(1, N)].

%%====================================================================
%% Border Helpers
%%====================================================================

%% @doc Get border characters for a border style
-spec border_chars(atom()) -> {binary(), binary(), binary(), binary(), binary(), binary()}.
border_chars(single) -> 
    {<<"┌"/utf8>>, <<"┐"/utf8>>, <<"└"/utf8>>, <<"┘"/utf8>>, <<"─"/utf8>>, <<"│"/utf8>>};
border_chars(double) -> 
    {<<"╔"/utf8>>, <<"╗"/utf8>>, <<"╚"/utf8>>, <<"╝"/utf8>>, <<"═"/utf8>>, <<"║"/utf8>>};
border_chars(rounded) -> 
    {<<"╭"/utf8>>, <<"╮"/utf8>>, <<"╰"/utf8>>, <<"╯"/utf8>>, <<"─"/utf8>>, <<"│"/utf8>>};
border_chars(_) -> 
    {<<"┌"/utf8>>, <<"┐"/utf8>>, <<"└"/utf8>>, <<"┘"/utf8>>, <<"─"/utf8>>, <<"│"/utf8>>}.

%% @doc Render a title line with horizontal border characters
-spec render_title_line(undefined | binary() | string(), binary(), integer()) -> iolist().
render_title_line(undefined, HZ, Width) ->
    repeat_bin(HZ, Width);
render_title_line(Title, HZ, Width) ->
    TitleBin = unicode:characters_to_binary(Title),
    TitleLen = iso_unicode:display_width(TitleBin),
    case TitleLen + 2 > Width of
        true -> repeat_bin(HZ, Width);
        false ->
            Padding = Width - TitleLen - 2,
            LeftPad = Padding div 2,
            RightPad = Padding - LeftPad,
            [repeat_bin(HZ, LeftPad), $\s, TitleBin, $\s, repeat_bin(HZ, RightPad)]
    end.

%%====================================================================
%% Size Helpers
%%====================================================================

%% @doc Resolve auto size to available space
-spec resolve_size(auto | fill | integer(), integer()) -> integer().
resolve_size(auto, Available) -> Available;
resolve_size(fill, Available) -> Available;
resolve_size(Size, _Available) when is_integer(Size) -> Size.

%% @doc Render a box border (used by box, tabs, modal)
-spec render_box_border(integer(), integer(), integer(), integer(),
                        map(), undefined | binary() | string(), atom()) -> iolist().
render_box_border(ActualX, ActualY, Width, Height, Style, Title, Border) ->
    {TL, TR, BL, BR, HZ, VT} = border_chars(Border),
    [
        style_to_ansi(Style),
        %% Top border
        move_to(ActualY + 1, ActualX + 1),
        TL, render_title_line(Title, HZ, Width - 2), TR,
        %% Side borders
        [[move_to(ActualY + 1 + Row, ActualX + 1),
          VT, lists:duplicate(Width - 2, $\s), VT]
         || Row <- lists:seq(1, Height - 2)],
        %% Bottom border
        move_to(ActualY + Height, ActualX + 1),
        BL, repeat_bin(HZ, Width - 2), BR,
        reset_style()
    ].
