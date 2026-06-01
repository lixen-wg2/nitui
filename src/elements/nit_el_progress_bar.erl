%%%-------------------------------------------------------------------
%%% @doc Progress Bar Element
%%%
%%% Displays a progress bar with value/max, optional percentage,
%%% and threshold-based coloring.
%%% @end
%%%-------------------------------------------------------------------
-module(nit_el_progress_bar).

-behaviour(nit_element).

-include("nit_elements.hrl").

-export([render/3, height/2, width/2, fixed_width/1]).

%%====================================================================
%% nit_element callbacks
%%====================================================================

render(#progress_bar{visible = false}, _Bounds, _Opts) ->
    [];
render(#progress_bar{value = Value, max = Max, width = W, x = X, y = Y,
                     show_percent = ShowPct, show_value = ShowVal,
                     bar_char = BarChar, empty_char = EmptyChar,
                     color = Color, threshold_warn = WarnT, threshold_crit = CritT,
                     style = Style}, Bounds, Opts) ->
    ActualX = Bounds#bounds.x + X,
    ActualY = Bounds#bounds.y + Y,
    
    %% Calculate ratio
    Ratio = case Max of
        0 -> 0.0;
        _ -> min(1.0, max(0.0, Value / Max))
    end,
    
    %% Determine bar width
    BarWidth = case W of
        auto -> min(20, Bounds#bounds.width - X);
        fill -> Bounds#bounds.width - X;
        _ -> W
    end,
    
    %% Build suffix text
    Suffix = build_suffix(ShowPct, ShowVal, Ratio, Value, Max),
    SuffixLen = byte_size(Suffix),
    
    %% Actual bar width (minus suffix space)
    ActualBarWidth = max(1, BarWidth - SuffixLen),
    FilledWidth = round(Ratio * ActualBarWidth),
    EmptyWidth = ActualBarWidth - FilledWidth,
    
    %% Determine color based on thresholds
    BarColor = case Color of
        auto ->
            if
                Ratio >= CritT -> red;
                Ratio >= WarnT -> yellow;
                true -> green
            end;
        _ -> Color
    end,
    
    %% Build bar
    FilledPart = list_to_binary(lists:duplicate(FilledWidth, BarChar)),
    EmptyPart = list_to_binary(lists:duplicate(EmptyWidth, EmptyChar)),
    
    %% Merge styles
    BaseStyle = maps:get(base_style, Opts, #{}),
    BarStyle = maps:merge(maps:merge(BaseStyle, Style), #{fg => BarColor}),
    
    [
        nit_ansi:move_to(ActualY, ActualX),
        nit_ansi:style_to_ansi(BarStyle),
        FilledPart,
        nit_ansi:reset_style(),
        nit_ansi:style_to_ansi(maps:merge(BaseStyle, #{dim => true})),
        EmptyPart,
        nit_ansi:reset_style(),
        nit_ansi:style_to_ansi(maps:merge(BaseStyle, Style)),
        Suffix,
        nit_ansi:reset_style()
    ].

-spec height(#progress_bar{}, #bounds{}) -> pos_integer().
height(#progress_bar{}, _Bounds) -> 1.

-spec width(#progress_bar{}, #bounds{}) -> pos_integer().
width(#progress_bar{width = auto}, _Bounds) -> 20;
width(#progress_bar{width = fill}, Bounds) -> Bounds#bounds.width;
width(#progress_bar{width = W}, _Bounds) -> W.

-spec fixed_width(#progress_bar{}) -> auto | pos_integer().
fixed_width(#progress_bar{width = fill}) -> auto;
fixed_width(#progress_bar{width = W}) -> W.

%%====================================================================
%% Internal functions
%%====================================================================

build_suffix(true, true, Ratio, Value, Max) ->
    Pct = round(Ratio * 100),
    iolist_to_binary(io_lib:format(" ~B% (~p/~p)", [Pct, round(Value), round(Max)]));
build_suffix(true, false, Ratio, _Value, _Max) ->
    Pct = round(Ratio * 100),
    iolist_to_binary(io_lib:format(" ~B%", [Pct]));
build_suffix(false, true, _Ratio, Value, Max) ->
    iolist_to_binary(io_lib:format(" ~p/~p", [round(Value), round(Max)]));
build_suffix(false, false, _Ratio, _Value, _Max) ->
    <<>>.
