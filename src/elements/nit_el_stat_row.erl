%%%-------------------------------------------------------------------
%%% @doc Stat Row Element
%%%
%%% Displays a horizontal row of key-value pairs with separators.
%%% @end
%%%-------------------------------------------------------------------
-module(nit_el_stat_row).

-behaviour(nit_element).

-include("nit_elements.hrl").

-export([render/3, height/2, width/2, fixed_width/1]).

%%====================================================================
%% nit_element callbacks
%%====================================================================

render(#stat_row{visible = false}, _Bounds, _Opts) ->
    [];
render(#stat_row{items = [], x = X, y = Y}, Bounds, _Opts) ->
    ActualX = Bounds#bounds.x + X,
    ActualY = Bounds#bounds.y + Y,
    [nit_ansi:move_to(ActualY, ActualX)];
render(#stat_row{items = Items, separator = Sep, x = X, y = Y,
                 label_style = LabelStyle, value_style = ValueStyle,
                 style = Style}, Bounds, Opts) ->
    ActualX = Bounds#bounds.x + X,
    ActualY = Bounds#bounds.y + Y,
    
    BaseStyle = maps:get(base_style, Opts, #{}),
    MergedLabelStyle = maps:merge(maps:merge(BaseStyle, Style), LabelStyle),
    MergedValueStyle = maps:merge(maps:merge(BaseStyle, Style), ValueStyle),
    
    %% Build output for each item
    ItemOutputs = lists:map(
        fun({Label, Value}) ->
            [
                nit_ansi:style_to_ansi(MergedLabelStyle),
                Label,
                <<": ">>,
                nit_ansi:style_to_ansi(MergedValueStyle),
                Value,
                nit_ansi:reset_style()
            ]
        end,
        Items
    ),
    
    %% Join with separator
    SepOutput = [nit_ansi:style_to_ansi(#{dim => true}), Sep, nit_ansi:reset_style()],
    Joined = lists:join(SepOutput, ItemOutputs),
    
    [
        nit_ansi:move_to(ActualY, ActualX),
        Joined
    ].

height(#stat_row{}, _Bounds) -> 1.

width(#stat_row{items = Items, separator = Sep}, _Bounds) ->
    %% Calculate total width
    ItemWidths = lists:sum([byte_size(L) + 2 + byte_size(V) || {L, V} <- Items]),
    SepWidth = byte_size(Sep) * max(0, length(Items) - 1),
    ItemWidths + SepWidth.

fixed_width(#stat_row{width = fill}) -> auto;
fixed_width(#stat_row{width = W}) -> W.
