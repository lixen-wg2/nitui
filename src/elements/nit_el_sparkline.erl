%%%-------------------------------------------------------------------
%%% @doc Sparkline Element
%%%
%%% Displays a mini chart showing trend over time using braille,
%%% block, or ASCII characters.
%%% @end
%%%-------------------------------------------------------------------
-module(nit_el_sparkline).

-behaviour(nit_element).

-include("nit_elements.hrl").

-export([render/3, height/2, width/2, fixed_width/1]).

%% Braille patterns for sparklines (2 dots high per character)
%% Bottom dot = 1, Top dot = 2 (for each column)
-define(BRAILLE_BASE, 16#2800).

%%====================================================================
%% nit_element callbacks
%%====================================================================

render(#sparkline{visible = false}, _Bounds, _Opts) ->
    [];
render(#sparkline{values = [], width = W, x = X, y = Y}, Bounds, _Opts) ->
    %% Empty sparkline - just show placeholder
    ActualX = Bounds#bounds.x + X,
    ActualY = Bounds#bounds.y + Y,
    Width = case W of auto -> 20; fill -> Bounds#bounds.width - X; _ -> W end,
    [
        nit_ansi:move_to(ActualY, ActualX),
        list_to_binary(lists:duplicate(Width, $-))
    ];
render(#sparkline{values = Values, width = W, x = X, y = Y,
                  min_val = MinV, max_val = MaxV,
                  style_type = StyleType, color = Color, style = Style}, Bounds, Opts) ->
    ActualX = Bounds#bounds.x + X,
    ActualY = Bounds#bounds.y + Y,
    
    Width = case W of auto -> min(20, Bounds#bounds.width - X); fill -> Bounds#bounds.width - X; _ -> W end,
    
    %% Get the last N values to fit width
    DisplayValues = take_last(Values, Width),
    
    %% Calculate min/max for scaling
    {Min, Max} = calculate_range(DisplayValues, MinV, MaxV),
    
    %% Normalize values to 0-7 range (for braille) or 0-8 (for block)
    MaxLevel = case StyleType of braille -> 7; block -> 8; ascii -> 4 end,
    Normalized = normalize_values(DisplayValues, Min, Max, MaxLevel),
    
    %% Render based on style
    ChartChars = render_style(StyleType, Normalized),
    
    %% Pad to width if needed
    Padding = max(0, Width - length(ChartChars)),
    PaddedChart = lists:duplicate(Padding, $ ) ++ ChartChars,
    
    BaseStyle = maps:get(base_style, Opts, #{}),
    MergedStyle = maps:merge(maps:merge(BaseStyle, Style), #{fg => Color}),
    
    [
        nit_ansi:move_to(ActualY, ActualX),
        nit_ansi:style_to_ansi(MergedStyle),
        unicode:characters_to_binary(PaddedChart),
        nit_ansi:reset_style()
    ].

height(#sparkline{}, _Bounds) -> 1.

width(#sparkline{width = auto}, _Bounds) -> 20;
width(#sparkline{width = fill}, Bounds) -> Bounds#bounds.width;
width(#sparkline{width = W}, _Bounds) -> W.

fixed_width(#sparkline{width = fill}) -> auto;
fixed_width(#sparkline{width = W}) -> W.

%%====================================================================
%% Internal functions
%%====================================================================

take_last(List, N) when length(List) =< N -> List;
take_last(List, N) -> lists:nthtail(length(List) - N, List).

calculate_range(Values, auto, auto) ->
    {lists:min(Values), lists:max(Values)};
calculate_range(_Values, Min, auto) when is_number(Min) ->
    {Min, lists:max(_Values)};
calculate_range(Values, auto, Max) when is_number(Max) ->
    {lists:min(Values), Max};
calculate_range(_Values, Min, Max) ->
    {Min, Max}.

normalize_values(Values, Min, Max, MaxLevel) ->
    Range = max(1, Max - Min),
    [round((V - Min) / Range * MaxLevel) || V <- Values].

render_style(braille, Values) ->
    %% Pair values for braille (2 rows per char)
    render_braille(Values);
render_style(block, Values) ->
    %% Use block characters ▁▂▃▄▅▆▇█
    Blocks = " ▁▂▃▄▅▆▇█",
    [lists:nth(min(9, V + 1), Blocks) || V <- Values];
render_style(ascii, Values) ->
    %% Use ASCII: _ . - ' ^
    Chars = "_.,-'^",
    [lists:nth(min(5, V + 1), Chars) || V <- Values].

render_braille(Values) ->
    %% For single-row braille, use bottom dots only
    %% Braille dot positions: 1=top-left, 2=mid-left, 3=bot-left, 4=top-right, 5=mid-right, 6=bot-right, 7=extra-bot-left, 8=extra-bot-right
    %% For sparkline, we use dots 7,8,3,6,2,5,1,4 from bottom to top
    DotMap = [0, 16#80, 16#84, 16#44, 16#46, 16#06, 16#07, 16#47],
    [?BRAILLE_BASE + lists:nth(min(8, V + 1), DotMap) || V <- Values].
