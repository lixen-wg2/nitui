%%%-------------------------------------------------------------------
%%% @doc NitUI Input Element
%%%
%%% Renders a text input field with cursor and placeholder support.
%%% @end
%%%-------------------------------------------------------------------
-module(nit_el_input).

-behaviour(nit_element).

-include("nit_elements.hrl").

-export([render/3, height/2, width/2, fixed_width/1]).

%%====================================================================
%% nit_element callbacks
%%====================================================================

-spec render(#input{}, #bounds{}, map()) -> iolist().
render(#input{visible = false}, _Bounds, _Opts) ->
    [];
render(#input{value = Value, placeholder = Placeholder, cursor_pos = CursorPos,
              style = Style, x = X, y = Y, width = W} = Input, Bounds, Opts) ->
    ActualX = Bounds#bounds.x + X,
    ActualY = Bounds#bounds.y + Y,
    Focused = maps:get(focused, Opts, false),
    CursorVisible = maps:get(cursor_visible, Opts, true),
    BaseStyle = maps:get(base_style, Opts, #{}),
    
    Width = case W of
        auto -> 20;  %% Default input width
        fill -> Bounds#bounds.width - X;  %% Default input width
        _ -> W
    end,
    
    ValueBin = to_binary(Value),
    DisplayText = case byte_size(ValueBin) of
        0 -> to_binary(Placeholder);
        _ -> ValueBin
    end,
    
    %% Truncate or pad to width
    FieldWidth = max(0, Width - 2),  %% Account for [ ]
    DisplayChars = unicode:characters_to_list(DisplayText),
    ValueChars = unicode:characters_to_list(ValueBin),
    VisibleChars = lists:sublist(DisplayChars, FieldWidth),
    Padding = lists:duplicate(max(0, FieldWidth - length(VisibleChars)), $\s),
    
    %% Style: dim for placeholder, normal for value
    TextStyle = case byte_size(ValueBin) of
        0 -> maps:merge(Style, #{dim => true});
        _ -> Style
    end,
    FocusStyle = case Focused of
        true -> maps:merge(TextStyle, #{underline => true});
        false -> TextStyle
    end,
    MergedStyle = maps:merge(FocusStyle, BaseStyle),
    SelectionRange = case byte_size(ValueBin) of
        0 -> none;
        _ -> selection_range(Input, length(ValueChars))
    end,
    FieldOutput = render_field_cells(VisibleChars ++ Padding, 0, SelectionRange,
                                     MergedStyle, []),
    
    %% Cursor positioning (show cursor at position if focused)
    CursorOutput = case Focused andalso CursorVisible of
        true ->
            CursorCol = ActualX + 1 + min(CursorPos, max(0, FieldWidth - 1)),
            [nit_ansi:move_to(ActualY, CursorCol)];
        false -> []
    end,
    [
        nit_ansi:move_to(ActualY, ActualX),
        nit_ansi:style_to_ansi(MergedStyle),
        <<"[">>, FieldOutput,
        nit_ansi:reset_style(),
        nit_ansi:style_to_ansi(MergedStyle),
        <<"]">>,
        nit_ansi:reset_style(),
        CursorOutput
    ].

-spec height(#input{}, #bounds{}) -> pos_integer().
height(#input{}, _Bounds) -> 1.

-spec width(#input{}, #bounds{}) -> pos_integer().
width(#input{width = W}, Bounds) ->
    case W of
        auto -> 20;
        fill -> Bounds#bounds.width;
        _ -> W
    end.

-spec fixed_width(#input{}) -> auto | pos_integer().
fixed_width(#input{width = auto}) -> 20;
fixed_width(#input{width = fill}) -> auto;
fixed_width(#input{width = W}) -> W.

to_binary(Value) when is_binary(Value) ->
    Value;
to_binary(Value) when is_list(Value) ->
    unicode:characters_to_binary(Value).

selection_range(#input{cursor_pos = CursorPos, selection_anchor = Anchor}, _Len)
        when Anchor =:= undefined; Anchor =:= CursorPos ->
    none;
selection_range(#input{cursor_pos = CursorPos, selection_anchor = Anchor}, Len) ->
    SafeCursor = clamp(CursorPos, Len),
    SafeAnchor = clamp(Anchor, Len),
    case SafeCursor =:= SafeAnchor of
        true -> none;
        false -> {min(SafeCursor, SafeAnchor), max(SafeCursor, SafeAnchor)}
    end.

render_field_cells([], _Idx, _SelectionRange, _Style, Acc) ->
    lists:reverse(Acc);
render_field_cells([Char | Rest], Idx, SelectionRange, Style, Acc) ->
    CellStyle = case selected_cell(Idx, SelectionRange) of
        true -> maps:merge(Style, #{bg => blue, fg => white});
        false -> Style
    end,
    Cell = [
        nit_ansi:reset_style(),
        nit_ansi:style_to_ansi(CellStyle),
        unicode:characters_to_binary([Char])
    ],
    render_field_cells(Rest, Idx + 1, SelectionRange, Style, [Cell | Acc]).

selected_cell(Idx, {Start, End}) ->
    Idx >= Start andalso Idx < End;
selected_cell(_Idx, none) ->
    false.

clamp(Pos, Max) ->
    min(max(0, Pos), Max).
