%%%-------------------------------------------------------------------
%%% @doc NitUI ANSI Helpers
%%%
%%% Common ANSI escape sequence utilities used by element modules.
%%% @end
%%%-------------------------------------------------------------------
-module(nit_ansi).

-export([move_to/2, style_to_ansi/1, reset_style/0]).
-export([truncate_content/2, repeat_bin/2]).
-export([border_chars/1, render_title_line/3, render_box_border/7]).
-export([resolve_size/2]).

%%====================================================================
%% Cursor Movement
%%====================================================================

%% @doc Move cursor to row, col (0-based)
-spec move_to(integer(), integer()) -> binary().
move_to(Row, Col) ->
    iolist_to_binary(nit_terminal:cursor(Row, Col)).

%%====================================================================
%% Style Handling
%%====================================================================

-spec style_to_ansi(map()) -> iolist().
style_to_ansi(Style) when map_size(Style) == 0 ->
    [];
style_to_ansi(Style) ->
    nit_terminal:style(Style).

-spec reset_style() -> binary().
reset_style() ->
    iolist_to_binary(nit_terminal:reset()).

%%====================================================================
%% Text Helpers
%%====================================================================

%% @doc Truncate content to fit within MaxWidth
-spec truncate_content(iodata(), integer()) -> binary().
truncate_content(_Content, MaxWidth) when MaxWidth =< 0 ->
    <<>>;
truncate_content(Content, MaxWidth) ->
    nit_unicode:truncate(Content, MaxWidth).

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
    TitleLen = nit_unicode:display_width(TitleBin),
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
        move_to(ActualY, ActualX),
        TL, render_title_line(Title, HZ, Width - 2), TR,
        %% Side borders
        [[move_to(ActualY + Row, ActualX),
          VT, lists:duplicate(Width - 2, $\s), VT]
         || Row <- lists:seq(1, Height - 2)],
        %% Bottom border
        move_to(ActualY + Height - 1, ActualX),
        BL, repeat_bin(HZ, Width - 2), BR,
        reset_style()
    ].
