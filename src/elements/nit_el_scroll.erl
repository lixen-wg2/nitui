%%%-------------------------------------------------------------------
%%% @doc NitUI Scroll Container Element
%%%
%%% A scrollable viewport that can contain child elements.
%%% Supports vertical scrolling with optional scrollbar indicator.
%%% @end
%%%-------------------------------------------------------------------
-module(nit_el_scroll).

-behaviour(nit_element).

-include("nit_elements.hrl").

-export([render/3, height/2, width/2, fixed_width/1]).
-export([content_size/2]).

%%====================================================================
%% nit_element callbacks
%%====================================================================

-spec render(#scroll{}, #bounds{}, map()) -> iolist().
render(#scroll{visible = false}, _Bounds, _Opts) ->
    [];
render(#scroll{children = Children, offset = Offset, show_scrollbar = ShowBar} = Scroll, Bounds, Opts) ->
    ViewHeight = max(1, Bounds#bounds.height),
    {ContentWidth, TotalHeight} = content_size(Scroll, Bounds),
    ClampedOffset = clamp_offset(Offset, TotalHeight, ViewHeight),

    %% Render visible portion of children
    ChildOutput = render_children_with_offset(
        Children, ContentWidth, TotalHeight, ClampedOffset, ViewHeight, Opts,
        Bounds#bounds.x, Bounds#bounds.y),

    %% Render scrollbar if needed
    ScrollbarOutput = if ShowBar andalso TotalHeight > ViewHeight ->
                             render_scrollbar(Bounds, ClampedOffset, TotalHeight, ViewHeight,
                                              maps:get(base_style, Opts, #{}));
                         true ->
                             []
                      end,
    
    [ChildOutput, ScrollbarOutput].

-spec height(#scroll{}, #bounds{}) -> pos_integer() | {flex, non_neg_integer()}.
height(#scroll{height = auto}, Bounds) -> Bounds#bounds.height;
height(#scroll{height = fill}, _Bounds) -> {flex, 1};
height(#scroll{height = H}, _Bounds) -> H.

-spec width(#scroll{}, #bounds{}) -> pos_integer().
width(#scroll{width = auto}, Bounds) -> Bounds#bounds.width;
width(#scroll{width = fill}, Bounds) -> Bounds#bounds.width;
width(#scroll{width = W}, _Bounds) -> W.

-spec fixed_width(#scroll{}) -> auto | pos_integer().
fixed_width(#scroll{width = fill}) -> auto;
fixed_width(#scroll{width = W}) -> W.

%% @doc Content dimensions for resolved viewport bounds. Rendering, navigation
%% and hit testing must all remeasure wrapped children after reserving the bar.
-spec content_size(#scroll{}, #bounds{}) -> {pos_integer(), non_neg_integer()}.
content_size(#scroll{children = Children, show_scrollbar = ShowBar}, Bounds) ->
    TotalHeight = calculate_content_height(Children, Bounds),
    case ShowBar andalso TotalHeight > max(1, Bounds#bounds.height) of
        true ->
            ContentWidth = max(1, Bounds#bounds.width - 1),
            {ContentWidth, calculate_content_height(Children, Bounds#bounds{width = ContentWidth})};
        false ->
            {Bounds#bounds.width, TotalHeight}
    end.

%%====================================================================
%% Internal functions
%%====================================================================

calculate_content_height(Children, Bounds) ->
    lists:foldl(fun(Child, Acc) ->
        Acc + height_value(nit_element:height(Child, Bounds))
    end, 0, Children).

render_children_with_offset(Children, Width, TotalHeight, Offset, ViewHeight, Opts, DestX, DestY) ->
    ContentHeight = max(ViewHeight, TotalHeight),
    LayoutBounds = #bounds{x = 0, y = 0, width = Width, height = ContentHeight},
    ChildHeights = nit_layout:calculate_vbox_heights(Children, LayoutBounds, 0),
    render_stack_window(Children, ChildHeights, 0, 0, Offset, Offset + ViewHeight,
                        DestX, DestY, Width, Opts, []).

render_stack_window([], _Heights, _StartY, _Spacing, _ClipTop, _ClipBottom,
                    _DestX, _DestY, _Width, _Opts, Acc) ->
    lists:reverse(Acc);
render_stack_window([Child | RestChildren], [Height | RestHeights], CurrentY, Spacing,
                    ClipTop, ClipBottom, DestX, DestY, Width, Opts, Acc) ->
    ChildEnd = CurrentY + Height,
    NewAcc = case ChildEnd =< ClipTop orelse CurrentY >= ClipBottom of
        true ->
            Acc;
        false ->
            Output = render_child_window(Child, CurrentY, Height, ClipTop, ClipBottom,
                                         DestX, DestY, Width, Opts),
            [Output | Acc]
    end,
    render_stack_window(RestChildren, RestHeights, ChildEnd + Spacing, Spacing,
                        ClipTop, ClipBottom, DestX, DestY, Width, Opts, NewAcc).

render_child_window(Child, ChildY, Height, ClipTop, ClipBottom, DestX, DestY, Width, Opts) ->
    case ChildY >= ClipTop andalso ChildY + Height =< ClipBottom of
        true ->
            ChildBounds = #bounds{x = DestX, y = DestY + ChildY - ClipTop,
                                  width = Width, height = Height},
            render_child(Child, ChildBounds, Opts);
        false ->
            render_clipped_child(Child, ChildY, Height, ClipTop, ClipBottom,
                                 DestX, DestY, Width, Opts)
    end.

render_clipped_child(#vbox{visible = false}, _ChildY, _Height, _ClipTop, _ClipBottom,
                     _DestX, _DestY, _Width, _Opts) ->
    [];
render_clipped_child(#vbox{children = Children, spacing = Spacing, x = X, y = Y},
                     ChildY, Height, ClipTop, ClipBottom, DestX, DestY, Width, Opts) ->
    LayoutBounds = #bounds{x = 0, y = 0, width = Width, height = Height},
    ChildHeights = nit_layout:calculate_vbox_heights(Children, LayoutBounds, Spacing, Y),
    render_stack_window(Children, ChildHeights, ChildY + Y, Spacing, ClipTop, ClipBottom,
                        DestX + X, DestY, Width, Opts, []);
render_clipped_child(Child, ChildY, Height, ClipTop, ClipBottom, DestX, DestY, Width, Opts) ->
    OffscreenBounds = #bounds{x = 0, y = 0, width = Width, height = Height},
    OffscreenOutput = render_child(Child, OffscreenBounds, Opts),
    OffscreenScreen = nit_screen:from_ansi(OffscreenOutput, Width, Height),
    VisibleTop = max(ChildY, ClipTop),
    VisibleBottom = min(ChildY + Height, ClipBottom),
    VisibleHeight = max(0, VisibleBottom - VisibleTop),
    RelativeOffset = VisibleTop - ChildY,
    TargetY = DestY + VisibleTop - ClipTop,
    viewport_to_ansi(OffscreenScreen, Width, VisibleHeight, RelativeOffset, DestX, TargetY).

%% Internal render hook lets focus-aware renderers retain their focus context
%% through both direct and offscreen paths. Plain element rendering is unchanged.
render_child(Child, Bounds, Opts) ->
    Render = maps:get(render_child, Opts, fun nit_element:render/3),
    Render(Child, Bounds, Opts).

height_value({flex, Min}) ->
    Min;
height_value(Height) when is_integer(Height) ->
    Height.

viewport_to_ansi(Screen, Width, ViewHeight, Offset, DestX, DestY) ->
    [render_viewport_row(Screen, Width, Offset + Row, DestX, DestY + Row)
     || Row <- lists:seq(0, ViewHeight - 1)].

render_viewport_row(Screen, Width, SourceRow, DestX, DestY) ->
    [
        nit_ansi:move_to(DestY, DestX),
        render_viewport_cells(Screen, Width, SourceRow, 0, #{}, []),
        nit_ansi:reset_style()
    ].

render_viewport_cells(_Screen, Width, _SourceRow, Col, _LastStyle, Acc) when Col >= Width ->
    lists:reverse(Acc);
render_viewport_cells(Screen, Width, SourceRow, Col, LastStyle, Acc) ->
    {Char, Style} = nit_screen:get_cell(Screen, Col, SourceRow),
    StyleChange = style_change(LastStyle, Style),
    CharBin = char_to_binary(Char),
    render_viewport_cells(
        Screen, Width, SourceRow, Col + 1, Style,
        [[StyleChange, CharBin] | Acc]).

style_change(OldStyle, NewStyle) when OldStyle =:= NewStyle ->
    [];
style_change(_OldStyle, NewStyle) ->
    [nit_ansi:reset_style(), nit_ansi:style_to_ansi(NewStyle)].

char_to_binary(Char) when is_integer(Char) ->
    unicode:characters_to_binary([Char]);
char_to_binary(Bin) when is_binary(Bin) ->
    Bin.

clamp_offset(Offset, TotalHeight, ViewHeight) ->
    min(max(0, Offset), max(0, TotalHeight - ViewHeight)).

render_scrollbar(Bounds, Offset, TotalHeight, ViewHeight, BaseStyle) ->
    %% Calculate scrollbar position and size
    BarX = Bounds#bounds.x + Bounds#bounds.width - 1,
    BarY = Bounds#bounds.y,
    
    %% Scrollbar thumb size (minimum 1)
    ThumbSize = max(1, (ViewHeight * ViewHeight) div TotalHeight),
    
    %% Scrollbar thumb position
    MaxOffset = TotalHeight - ViewHeight,
    ThumbPos = if MaxOffset > 0 ->
                      (Offset * (ViewHeight - ThumbSize)) div MaxOffset;
                  true ->
                      0
               end,
    
    %% Render scrollbar track and thumb
    Style = maps:merge(#{fg => gray}, BaseStyle),
    render_scrollbar_lines(BarX, BarY, ViewHeight, ThumbPos, ThumbSize, Style, []).

render_scrollbar_lines(_X, _Y, 0, _ThumbPos, _ThumbSize, _Style, Acc) ->
    lists:reverse(Acc);
render_scrollbar_lines(X, Y, Remaining, ThumbPos, ThumbSize, Style, Acc) ->
    LineIdx = length(Acc),
    Char = if LineIdx >= ThumbPos andalso LineIdx < ThumbPos + ThumbSize ->
                  <<"█"/utf8>>;  %% Thumb
              true ->
                  <<"░"/utf8>>   %% Track
           end,
    Line = [nit_ansi:move_to(Y + LineIdx, X),
            nit_ansi:style_to_ansi(Style),
            Char,
            nit_ansi:reset_style()],
    render_scrollbar_lines(X, Y, Remaining - 1, ThumbPos, ThumbSize, Style, [Line | Acc]).
