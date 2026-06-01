%%%-------------------------------------------------------------------
%%% @doc Virtual Screen Buffer for NitUI.
%%%
%%% Provides a virtual screen buffer that stores character cells with
%%% their attributes. Supports differential rendering by comparing
%%% the current buffer with the previous one and generating minimal
%%% ANSI output for only the changed cells.
%%%
%%% Each cell contains:
%%% - Character (unicode codepoint or binary)
%%% - Style (foreground, background, bold, dim, etc.)
%%% @end
%%%-------------------------------------------------------------------
-module(iso_screen).

-export([new/2, resize/3, put_char/5, put_string/5, fill/3]).
-export([diff/2, to_ansi/1, clear/1]).
-export([get_size/1, get_cell/3]).
-export([from_ansi/3]).

-record(cell, {
    char = $\s :: integer() | binary(),
    style = #{} :: map()
}).

-record(screen, {
    width :: pos_integer(),
    height :: pos_integer(),
    cells :: array:array()  %% 2D array stored as 1D: row * width + col
}).

-type screen() :: #screen{}.
-export_type([screen/0]).

%%====================================================================
%% API
%%====================================================================

%% @doc Create a new screen buffer filled with spaces.
-spec new(pos_integer(), pos_integer()) -> screen().
new(Width, Height) ->
    EmptyCell = #cell{},
    Size = Width * Height,
    Cells = array:new([{size, Size}, {fixed, true}, {default, EmptyCell}]),
    #screen{width = Width, height = Height, cells = Cells}.

%% @doc Resize the screen buffer, preserving content where possible.
-spec resize(screen(), pos_integer(), pos_integer()) -> screen().
resize(#screen{width = OldW, height = OldH, cells = OldCells}, NewW, NewH) ->
    EmptyCell = #cell{},
    Size = NewW * NewH,
    NewCells = array:new([{size, Size}, {fixed, true}, {default, EmptyCell}]),
    %% Copy existing content
    CopiedCells = lists:foldl(fun(Row, Acc1) ->
        lists:foldl(fun(Col, Acc2) ->
            case Row < OldH andalso Col < OldW of
                true ->
                    OldIdx = Row * OldW + Col,
                    NewIdx = Row * NewW + Col,
                    Cell = array:get(OldIdx, OldCells),
                    array:set(NewIdx, Cell, Acc2);
                false ->
                    Acc2
            end
        end, Acc1, lists:seq(0, NewW - 1))
    end, NewCells, lists:seq(0, NewH - 1)),
    #screen{width = NewW, height = NewH, cells = CopiedCells}.

%% @doc Put a single character at position (0-indexed).
-spec put_char(screen(), non_neg_integer(), non_neg_integer(), integer() | binary(), map()) -> screen().
put_char(Screen = #screen{width = W, height = H, cells = Cells}, Col, Row, Char, Style) 
  when Col >= 0, Col < W, Row >= 0, Row < H ->
    Idx = Row * W + Col,
    NewCells = array:set(Idx, #cell{char = Char, style = Style}, Cells),
    Screen#screen{cells = NewCells};
put_char(Screen, _, _, _, _) ->
    Screen.  %% Out of bounds, ignore

%% @doc Put a string starting at position (0-indexed).
-spec put_string(screen(), non_neg_integer(), non_neg_integer(), iodata(), map()) -> screen().
put_string(Screen, Col, Row, String, Style) ->
    Chars = unicode:characters_to_list(iolist_to_binary(String)),
    put_chars(Screen, Col, Row, Chars, Style).

put_chars(Screen, _Col, _Row, [], _Style) ->
    Screen;
put_chars(Screen = #screen{width = W}, Col, Row, [Char | Rest], Style) ->
    NewScreen = put_char(Screen, Col, Row, Char, Style),
    NextCol = Col + 1,
    case NextCol >= W of
        true -> NewScreen;  %% Stop at end of line
        false -> put_chars(NewScreen, NextCol, Row, Rest, Style)
    end.

%% @doc Fill entire screen with a character and style.
-spec fill(screen(), integer() | binary(), map()) -> screen().
fill(Screen = #screen{width = W, height = H}, Char, Style) ->
    Cell = #cell{char = Char, style = Style},
    Size = W * H,
    NewCells = array:new([{size, Size}, {fixed, true}, {default, Cell}]),
    Screen#screen{cells = NewCells}.

%% @doc Clear the screen (fill with spaces, no style).
-spec clear(screen()) -> screen().
clear(Screen) ->
    fill(Screen, $\s, #{}).

%% @doc Get screen dimensions.
-spec get_size(screen()) -> {pos_integer(), pos_integer()}.
get_size(#screen{width = W, height = H}) ->
    {W, H}.

%% @doc Get cell at position (0-indexed).
-spec get_cell(screen(), non_neg_integer(), non_neg_integer()) -> {integer() | binary(), map()}.
get_cell(#screen{width = W, height = H, cells = Cells}, Col, Row) 
  when Col >= 0, Col < W, Row >= 0, Row < H ->
    Idx = Row * W + Col,
    #cell{char = Char, style = Style} = array:get(Idx, Cells),
    {Char, Style};
get_cell(_, _, _) ->
    {$\s, #{}}.  %% Out of bounds returns space

%% @doc Generate ANSI output for the entire screen.
-spec to_ansi(screen()) -> iolist().
to_ansi(#screen{width = W, height = H, cells = Cells}) ->
    render_rows(Cells, W, H, 0, #{}, []).

%% @doc Compare two screens and generate ANSI output for differences only.
-spec diff(screen(), screen()) -> iolist().
diff(OldScreen, NewScreen) ->
    case diff_screens(OldScreen, NewScreen) of
        [] ->
            [];
        DiffOutput ->
            [iso_ansi:reset_style(), DiffOutput, iso_ansi:reset_style()]
    end.

%%====================================================================
%% Internal - Full screen rendering
%%====================================================================

render_rows(_Cells, _W, H, Row, _LastStyle, Acc) when Row >= H ->
    lists:reverse(Acc);
render_rows(Cells, W, H, Row, LastStyle, Acc) ->
    {RowOutput, NewLastStyle} = render_row(Cells, W, Row, 0, LastStyle, []),
    %% Move to start of row (1-indexed for ANSI)
    MoveTo = io_lib:format("\e[~B;1H", [Row + 1]),
    render_rows(Cells, W, H, Row + 1, NewLastStyle, [[MoveTo, RowOutput] | Acc]).

render_row(_Cells, W, _Row, Col, LastStyle, Acc) when Col >= W ->
    {lists:reverse(Acc), LastStyle};
render_row(Cells, W, Row, Col, LastStyle, Acc) ->
    Idx = Row * W + Col,
    #cell{char = Char, style = Style} = array:get(Idx, Cells),
    StyleChange = style_change(LastStyle, Style),
    CharBin = char_to_binary(Char),
    render_row(Cells, W, Row, Col + 1, Style, [[StyleChange, CharBin] | Acc]).

%%====================================================================
%% Internal - Differential rendering
%%====================================================================

diff_screens(#screen{width = W1, height = H1}, #screen{width = W2, height = H2})
  when W1 =/= W2; H1 =/= H2 ->
    %% Size changed - can't diff, need full redraw
    %% Return empty and let caller handle full redraw
    [];
diff_screens(#screen{width = W, height = H, cells = OldCells},
             #screen{cells = NewCells}) ->
    diff_rows(OldCells, NewCells, W, H, 0, #{}, []).

diff_rows(_OldCells, _NewCells, _W, H, Row, _LastStyle, Acc) when Row >= H ->
    lists:reverse(Acc);
diff_rows(OldCells, NewCells, W, H, Row, LastStyle, Acc) ->
    {RowOutput, NewLastStyle} = diff_row(OldCells, NewCells, W, Row, 0, LastStyle, []),
    NewAcc = case RowOutput of
        [] -> Acc;
        _ -> [RowOutput | Acc]
    end,
    diff_rows(OldCells, NewCells, W, H, Row + 1, NewLastStyle, NewAcc).

diff_row(_OldCells, _NewCells, W, _Row, Col, LastStyle, Acc) when Col >= W ->
    {lists:reverse(Acc), LastStyle};
diff_row(OldCells, NewCells, W, Row, Col, LastStyle, Acc) ->
    Idx = Row * W + Col,
    OldCell = array:get(Idx, OldCells),
    NewCell = array:get(Idx, NewCells),
    case OldCell =:= NewCell of
        true ->
            diff_row(OldCells, NewCells, W, Row, Col + 1, LastStyle, Acc);
        false ->
            MoveTo = io_lib:format("\e[~B;~BH", [Row + 1, Col + 1]),
            {RunOutput, NewLastStyle, NextCol} =
                diff_changed_run(OldCells, NewCells, W, Row, Col, LastStyle, []),
            diff_row(OldCells, NewCells, W, Row, NextCol, NewLastStyle,
                     [[MoveTo, RunOutput] | Acc])
    end.

diff_changed_run(_OldCells, _NewCells, W, _Row, Col, LastStyle, Acc) when Col >= W ->
    {lists:reverse(Acc), LastStyle, Col};
diff_changed_run(OldCells, NewCells, W, Row, Col, LastStyle, Acc) ->
    Idx = Row * W + Col,
    OldCell = array:get(Idx, OldCells),
    NewCell = array:get(Idx, NewCells),
    case OldCell =:= NewCell of
        true ->
            {lists:reverse(Acc), LastStyle, Col};
        false ->
            #cell{char = Char, style = Style} = NewCell,
            StyleChange = style_change(LastStyle, Style),
            CharBin = char_to_binary(Char),
            diff_changed_run(OldCells, NewCells, W, Row, Col + 1, Style,
                             [[StyleChange, CharBin] | Acc])
    end.

%%====================================================================
%% Internal - Style handling
%%====================================================================

style_change(OldStyle, NewStyle) when OldStyle =:= NewStyle ->
    [];
style_change(_OldStyle, NewStyle) ->
    %% For simplicity, always reset and apply new style
    %% Could be optimized to only change what's different
    ["\e[0m", iso_ansi:style_to_ansi(NewStyle)].

char_to_binary(Char) when is_integer(Char) ->
    unicode:characters_to_binary([Char]);
char_to_binary(Bin) when is_binary(Bin) ->
    Bin.

%%====================================================================
%% Internal - ANSI parsing to populate screen buffer
%%====================================================================

%% @doc Parse ANSI output and populate a screen buffer.
%% Returns a new screen with the ANSI content rendered into it.
-spec from_ansi(iodata(), pos_integer(), pos_integer()) -> screen().
from_ansi(AnsiData, Width, Height) ->
    Screen = new(Width, Height),
    Bin = iolist_to_binary(AnsiData),
    parse_ansi(Bin, Screen, 0, 0, #{}).

%% Parse state: current position (Col, Row) and current style
parse_ansi(<<>>, Screen, _Col, _Row, _Style) ->
    Screen;
parse_ansi(<<"\e[", Rest/binary>>, Screen, Col, Row, Style) ->
    %% CSI sequence
    parse_csi(Rest, Screen, Col, Row, Style);
parse_ansi(<<"\n", Rest/binary>>, Screen, _Col, Row, Style) ->
    %% Newline - move to start of next row
    parse_ansi(Rest, Screen, 0, Row + 1, Style);
parse_ansi(<<"\r", Rest/binary>>, Screen, _Col, Row, Style) ->
    %% Carriage return - move to start of current row
    parse_ansi(Rest, Screen, 0, Row, Style);
parse_ansi(<<Char/utf8, Rest/binary>>, Screen, Col, Row, Style) ->
    %% Regular character - write to screen and advance
    NewScreen = put_char(Screen, Col, Row, Char, Style),
    parse_ansi(Rest, NewScreen, Col + 1, Row, Style);
parse_ansi(<<_InvalidByte, Rest/binary>>, Screen, Col, Row, Style) ->
    %% Skip invalid/orphaned UTF-8 continuation bytes (0x80-0xBF appearing without leading byte)
    %% This can happen when multi-byte UTF-8 characters get truncated at byte boundaries
    parse_ansi(Rest, Screen, Col, Row, Style).

%% Parse CSI (Control Sequence Introducer) sequences
parse_csi(Bin, Screen, Col, Row, Style) ->
    case parse_csi_params(Bin, []) of
        {Params, $H, Rest} ->
            %% Cursor position: ESC[row;colH or ESC[H (home)
            {NewRow, NewCol} = case Params of
                [] -> {0, 0};
                [R] -> {R - 1, 0};
                [R, C | _] -> {R - 1, C - 1}
            end,
            parse_ansi(Rest, Screen, NewCol, NewRow, Style);
        {Params, $m, Rest} ->
            %% SGR (Select Graphic Rendition) - style changes
            NewStyle = apply_sgr(Params, Style),
            parse_ansi(Rest, Screen, Col, Row, NewStyle);
        {_Params, $J, Rest} ->
            %% Erase in Display - ignore for now
            parse_ansi(Rest, Screen, Col, Row, Style);
        {_Params, $K, Rest} ->
            %% Erase in Line - ignore for now
            parse_ansi(Rest, Screen, Col, Row, Style);
        {_Params, $A, Rest} ->
            %% Cursor up - ignore for now
            parse_ansi(Rest, Screen, Col, Row, Style);
        {_Params, $B, Rest} ->
            %% Cursor down - ignore for now
            parse_ansi(Rest, Screen, Col, Row, Style);
        {_Params, $C, Rest} ->
            %% Cursor forward - ignore for now
            parse_ansi(Rest, Screen, Col, Row, Style);
        {_Params, $D, Rest} ->
            %% Cursor back - ignore for now
            parse_ansi(Rest, Screen, Col, Row, Style);
        {_Params, _Cmd, Rest} ->
            %% Unknown command - skip
            parse_ansi(Rest, Screen, Col, Row, Style);
        incomplete ->
            %% Incomplete sequence at end - ignore
            Screen
    end.

%% Parse CSI parameters (semicolon-separated numbers)
parse_csi_params(<<>>, _Acc) ->
    incomplete;
parse_csi_params(<<C, Rest/binary>>, Acc) when C >= $0, C =< $9 ->
    parse_csi_number(Rest, C - $0, Acc);
parse_csi_params(<<$;, Rest/binary>>, Acc) ->
    %% Empty parameter, treat as 0
    parse_csi_params(Rest, [0 | Acc]);
parse_csi_params(<<$?, Rest/binary>>, Acc) ->
    %% Private mode indicator - skip and continue
    parse_csi_params(Rest, Acc);
parse_csi_params(<<Cmd, Rest/binary>>, Acc) when Cmd >= $@, Cmd =< $~ ->
    %% Command character - end of sequence
    {lists:reverse(Acc), Cmd, Rest};
parse_csi_params(<<_, Rest/binary>>, Acc) ->
    %% Unknown character in sequence - skip
    parse_csi_params(Rest, Acc).

parse_csi_number(<<C, Rest/binary>>, Num, Acc) when C >= $0, C =< $9 ->
    parse_csi_number(Rest, Num * 10 + (C - $0), Acc);
parse_csi_number(<<$;, Rest/binary>>, Num, Acc) ->
    parse_csi_params(Rest, [Num | Acc]);
parse_csi_number(<<Cmd, Rest/binary>>, Num, Acc) when Cmd >= $@, Cmd =< $~ ->
    {lists:reverse([Num | Acc]), Cmd, Rest};
parse_csi_number(<<_, Rest/binary>>, Num, Acc) ->
    %% Unknown - treat as end of number
    parse_csi_params(Rest, [Num | Acc]);
parse_csi_number(<<>>, _Num, _Acc) ->
    incomplete.

%% Apply SGR parameters to style
apply_sgr([], Style) -> Style;
apply_sgr([0 | Rest], _Style) ->
    %% Reset
    apply_sgr(Rest, #{});
apply_sgr([1 | Rest], Style) ->
    apply_sgr(Rest, Style#{bold => true});
apply_sgr([2 | Rest], Style) ->
    apply_sgr(Rest, Style#{dim => true});
apply_sgr([3 | Rest], Style) ->
    apply_sgr(Rest, Style#{italic => true});
apply_sgr([4 | Rest], Style) ->
    apply_sgr(Rest, Style#{underline => true});
apply_sgr([7 | Rest], Style) ->
    apply_sgr(Rest, Style#{reverse => true});
apply_sgr([22 | Rest], Style) ->
    apply_sgr(Rest, maps:remove(bold, maps:remove(dim, Style)));
apply_sgr([23 | Rest], Style) ->
    apply_sgr(Rest, maps:remove(italic, Style));
apply_sgr([24 | Rest], Style) ->
    apply_sgr(Rest, maps:remove(underline, Style));
apply_sgr([27 | Rest], Style) ->
    apply_sgr(Rest, maps:remove(reverse, Style));
%% Foreground colors
apply_sgr([30 | Rest], Style) -> apply_sgr(Rest, Style#{fg => black});
apply_sgr([31 | Rest], Style) -> apply_sgr(Rest, Style#{fg => red});
apply_sgr([32 | Rest], Style) -> apply_sgr(Rest, Style#{fg => green});
apply_sgr([33 | Rest], Style) -> apply_sgr(Rest, Style#{fg => yellow});
apply_sgr([34 | Rest], Style) -> apply_sgr(Rest, Style#{fg => blue});
apply_sgr([35 | Rest], Style) -> apply_sgr(Rest, Style#{fg => magenta});
apply_sgr([36 | Rest], Style) -> apply_sgr(Rest, Style#{fg => cyan});
apply_sgr([37 | Rest], Style) -> apply_sgr(Rest, Style#{fg => white});
apply_sgr([39 | Rest], Style) -> apply_sgr(Rest, maps:remove(fg, Style));
%% Background colors
apply_sgr([40 | Rest], Style) -> apply_sgr(Rest, Style#{bg => black});
apply_sgr([41 | Rest], Style) -> apply_sgr(Rest, Style#{bg => red});
apply_sgr([42 | Rest], Style) -> apply_sgr(Rest, Style#{bg => green});
apply_sgr([43 | Rest], Style) -> apply_sgr(Rest, Style#{bg => yellow});
apply_sgr([44 | Rest], Style) -> apply_sgr(Rest, Style#{bg => blue});
apply_sgr([45 | Rest], Style) -> apply_sgr(Rest, Style#{bg => magenta});
apply_sgr([46 | Rest], Style) -> apply_sgr(Rest, Style#{bg => cyan});
apply_sgr([47 | Rest], Style) -> apply_sgr(Rest, Style#{bg => white});
apply_sgr([49 | Rest], Style) -> apply_sgr(Rest, maps:remove(bg, Style));
%% Bright foreground colors
apply_sgr([90 | Rest], Style) -> apply_sgr(Rest, Style#{fg => bright_black});
apply_sgr([91 | Rest], Style) -> apply_sgr(Rest, Style#{fg => bright_red});
apply_sgr([92 | Rest], Style) -> apply_sgr(Rest, Style#{fg => bright_green});
apply_sgr([93 | Rest], Style) -> apply_sgr(Rest, Style#{fg => bright_yellow});
apply_sgr([94 | Rest], Style) -> apply_sgr(Rest, Style#{fg => bright_blue});
apply_sgr([95 | Rest], Style) -> apply_sgr(Rest, Style#{fg => bright_magenta});
apply_sgr([96 | Rest], Style) -> apply_sgr(Rest, Style#{fg => bright_cyan});
apply_sgr([97 | Rest], Style) -> apply_sgr(Rest, Style#{fg => bright_white});
%% Bright background colors
apply_sgr([100 | Rest], Style) -> apply_sgr(Rest, Style#{bg => bright_black});
apply_sgr([101 | Rest], Style) -> apply_sgr(Rest, Style#{bg => bright_red});
apply_sgr([102 | Rest], Style) -> apply_sgr(Rest, Style#{bg => bright_green});
apply_sgr([103 | Rest], Style) -> apply_sgr(Rest, Style#{bg => bright_yellow});
apply_sgr([104 | Rest], Style) -> apply_sgr(Rest, Style#{bg => bright_blue});
apply_sgr([105 | Rest], Style) -> apply_sgr(Rest, Style#{bg => bright_magenta});
apply_sgr([106 | Rest], Style) -> apply_sgr(Rest, Style#{bg => bright_cyan});
apply_sgr([107 | Rest], Style) -> apply_sgr(Rest, Style#{bg => bright_white});
%% Unknown - skip
apply_sgr([_ | Rest], Style) -> apply_sgr(Rest, Style).
