%%%-------------------------------------------------------------------
%%% Stat Row Element
%%%-------------------------------------------------------------------
-module(nit_el_stat_row).
-moduledoc """
Stat Row Element.

Displays a horizontal row of key-value pairs with separators.
""".

-behaviour(nit_element).

-include("nit_elements.hrl").

-export([render/3, height/2, width/2, fixed_width/1]).

%%====================================================================
%% nit_element callbacks
%%====================================================================

render(#stat_row{visible = false}, _Bounds, _Opts) ->
    [];
render(#stat_row{items = []}, _Bounds, _Opts) ->
    [];
render(#stat_row{x = X, y = Y}, Bounds, _Opts)
  when X < 0; Y < 0; X >= Bounds#bounds.width; Y >= Bounds#bounds.height ->
    [];
render(#stat_row{items = Items, separator = Sep, x = X, y = Y,
                 label_style = LabelStyle, value_style = ValueStyle,
                 style = Style} = Row, Bounds, Opts) ->
    Available = max(0, Bounds#bounds.width - X),
    MaxWidth = max(0, min(Available, nit_ansi:resolve_size(Row#stat_row.width, Available))),
    BaseStyle = maps:get(base_style, Opts, #{}),
    RowStyle = maps:merge(BaseStyle, Style),
    MergedLabelStyle = maps:merge(RowStyle, LabelStyle),
    MergedValueStyle = maps:merge(RowStyle, ValueStyle),
    ItemSegments = [
        [{[single_line(Label), <<": ">>], MergedLabelStyle},
         {single_line(Value), MergedValueStyle}]
        || {Label, Value} <- Items
    ],
    SepSegment = {single_line(Sep), #{dim => true}},
    Segments = lists:append(lists:join([SepSegment], ItemSegments)),
    case render_segments(Segments, MaxWidth) of
        [] -> [];
        Output ->
            [nit_ansi:move_to(Bounds#bounds.y + Y, Bounds#bounds.x + X),
             nit_ansi:reset_style(), Output]
    end.

height(#stat_row{}, _Bounds) -> 1.

width(#stat_row{width = auto, items = Items, separator = Sep}, _Bounds) ->
    ItemWidths = lists:sum([
        nit_unicode:display_width(single_line(L)) + 2 +
        nit_unicode:display_width(single_line(V)) || {L, V} <- Items
    ]),
    SepWidth = nit_unicode:display_width(single_line(Sep)) * max(0, length(Items) - 1),
    ItemWidths + SepWidth;
width(#stat_row{width = fill, x = X}, Bounds) ->
    max(0, Bounds#bounds.width - X);
width(#stat_row{width = W}, _Bounds) ->
    max(0, W).

fixed_width(#stat_row{width = fill}) -> auto;
fixed_width(#stat_row{width = W}) -> W.

%% Clip plain text before emitting ANSI so escape sequences cannot be split or
%% counted as cells. Reset between segments to keep label/value styles separate.
render_segments([], _Remaining) ->
    [];
render_segments(_Segments, Remaining) when Remaining =< 0 ->
    [];
render_segments([{Content, Style} | Rest], Remaining) ->
    Clipped = nit_ansi:truncate_content(Content, Remaining),
    Output = case Clipped of
        <<>> -> [];
        _ -> [nit_ansi:style_to_ansi(Style), Clipped, nit_ansi:reset_style()]
    end,
    Width = nit_unicode:display_width(Content),
    case Width > Remaining of
        %% A wide character may leave a spare cell. Do not skip it and resume
        %% at the next segment: the visible result must remain a prefix.
        true -> Output;
        false ->
            case render_segments(Rest, Remaining - Width) of
                [] -> Output;
                Tail -> [Output, Tail]
            end
    end.

%% Control characters have zero display width but can move the terminal cursor.
%% Stat rows are single-line text; styles are supplied through the style maps.
single_line(Content) ->
    [Char || Char <- nit_unicode:to_charlist(Content),
             Char >= 32, not (Char >= 16#7F andalso Char =< 16#9F)].
