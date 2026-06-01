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

%%====================================================================
%% nit_element callbacks
%%====================================================================

-spec render(#scroll{}, #bounds{}, map()) -> iolist().
render(#scroll{visible = false}, _Bounds, _Opts) ->
    [];
render(#scroll{children = Children, offset = Offset, show_scrollbar = ShowBar}, Bounds, Opts) ->
    ViewHeight = max(1, Bounds#bounds.height),
    TotalHeight0 = calculate_content_height(Children, Bounds),
    NeedsScrollbar0 = ShowBar andalso TotalHeight0 > ViewHeight,

    %% Adjust bounds for scrollbar if shown
    ContentWidth = if NeedsScrollbar0 ->
                          max(1, Bounds#bounds.width - 1);
                      true ->
                          Bounds#bounds.width
                   end,
    TotalHeight = case NeedsScrollbar0 of
        true -> calculate_content_height(Children, Bounds#bounds{width = ContentWidth});
        false -> TotalHeight0
    end,
    ClampedOffset = clamp_offset(Offset, TotalHeight, ViewHeight),

    %% Render visible portion of children
    ChildOutput = render_children_with_offset(
        Children, ContentWidth, TotalHeight, ClampedOffset, ViewHeight, Opts,
        Bounds#bounds.x, Bounds#bounds.y),

    %% Render scrollbar if needed
    ScrollbarOutput = if ShowBar andalso TotalHeight > ViewHeight ->
                             render_scrollbar(Bounds, ClampedOffset, TotalHeight, ViewHeight);
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
            nit_element:render(Child, ChildBounds, Opts);
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
    OffscreenOutput = nit_element:render(Child, OffscreenBounds, Opts),
    OffscreenScreen = nit_screen:from_ansi(OffscreenOutput, Width, Height),
    VisibleTop = max(ChildY, ClipTop),
    VisibleBottom = min(ChildY + Height, ClipBottom),
    VisibleHeight = max(0, VisibleBottom - VisibleTop),
    RelativeOffset = VisibleTop - ChildY,
    TargetY = DestY + VisibleTop - ClipTop,
    viewport_to_ansi(OffscreenScreen, Width, VisibleHeight, RelativeOffset, DestX, TargetY).

height_value({flex, Min}) ->
    Min;
height_value(Height) when is_integer(Height) ->
    Height.

viewport_to_ansi(Screen, Width, ViewHeight, Offset, DestX, DestY) ->
    [render_viewport_row(Screen, Width, Offset + Row, DestX, DestY + Row)
     || Row <- lists:seq(0, ViewHeight - 1)].

render_viewport_row(Screen, Width, SourceRow, DestX, DestY) ->
    [
        nit_ansi:move_to(DestY + 1, DestX + 1),
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

render_scrollbar(Bounds, Offset, TotalHeight, ViewHeight) ->
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
    render_scrollbar_lines(BarX, BarY, ViewHeight, ThumbPos, ThumbSize, []).

render_scrollbar_lines(_X, _Y, 0, _ThumbPos, _ThumbSize, Acc) ->
    lists:reverse(Acc);
render_scrollbar_lines(X, Y, Remaining, ThumbPos, ThumbSize, Acc) ->
    LineIdx = length(Acc),
    Char = if LineIdx >= ThumbPos andalso LineIdx < ThumbPos + ThumbSize ->
                  <<"█">>;  %% Thumb
              true ->
                  <<"░">>   %% Track
           end,
    Line = [nit_ansi:move_to(Y + LineIdx + 1, X + 1),
            nit_ansi:style_to_ansi(#{fg => gray}),
            Char,
            nit_ansi:reset_style()],
    render_scrollbar_lines(X, Y, Remaining - 1, ThumbPos, ThumbSize, [Line | Acc]).
