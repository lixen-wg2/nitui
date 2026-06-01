%%%-------------------------------------------------------------------
%%% @doc NitUI Box Element
%%%
%%% Renders a container with optional border and title.
%%% @end
%%%-------------------------------------------------------------------
-module(iso_el_box).

-behaviour(iso_element).

-include("iso_elements.hrl").

-export([render/3, height/2, width/2, fixed_width/1]).

%%====================================================================
%% iso_element callbacks
%%====================================================================

-spec render(#box{}, #bounds{}, map()) -> iolist().
render(#box{visible = false}, _Bounds, _Opts) ->
    [];
render(#box{border = none, children = Children, x = X, y = Y}, Bounds, Opts) ->
    ChildBounds = Bounds#bounds{
        x = Bounds#bounds.x + X,
        y = Bounds#bounds.y + Y
    },
    render_children(Children, ChildBounds, Opts);

render(#box{border = Border, title = Title, children = Children,
            style = Style, x = X, y = Y, width = W, height = H}, Bounds, Opts) ->
    ActualX = Bounds#bounds.x + X,
    ActualY = Bounds#bounds.y + Y,
    Width = iso_ansi:resolve_size(W, Bounds#bounds.width - X),
    Height = iso_ansi:resolve_size(H, Bounds#bounds.height - Y),
    
    %% Check if this container is focused (for focus highlighting)
    Focused = maps:get(focused, Opts, false),
    BaseStyle = maps:get(base_style, Opts, #{}),
    
    %% Merge focus style if this container has focus
    BorderStyle = case Focused of
        true -> maps:merge(maps:merge(Style, BaseStyle), #{fg => yellow, bold => true});
        false -> maps:merge(Style, BaseStyle)
    end,
    
    %% Child bounds (inside the border)
    ChildBounds = #bounds{
        x = ActualX + 1,
        y = ActualY + 1,
        width = max(1, Width - 2),
        height = max(1, Height - 2)
    },

    [
        iso_ansi:render_box_border(ActualX, ActualY, Width, Height, BorderStyle, Title, Border),
        render_children(Children, ChildBounds, Opts)
    ].

-spec height(#box{}, #bounds{}) -> pos_integer() | {flex, non_neg_integer()}.
height(#box{height = fill, border = Border}, _Bounds) ->
    Min = case Border of none -> 0; _ -> 3 end,
    {flex, Min};
height(#box{height = H, border = Border}, Bounds) ->
    BaseHeight = iso_ansi:resolve_size(H, Bounds#bounds.height),
    case Border of
        none -> BaseHeight;
        _ -> max(3, BaseHeight)  %% Minimum 3 for border
    end.

-spec width(#box{}, #bounds{}) -> pos_integer().
width(#box{width = W}, Bounds) ->
    iso_ansi:resolve_size(W, Bounds#bounds.width).

-spec fixed_width(#box{}) -> auto | pos_integer().
fixed_width(#box{width = auto}) -> auto;
fixed_width(#box{width = fill}) -> auto;
fixed_width(#box{width = W}) -> W.

%%====================================================================
%% Internal
%%====================================================================

render_children(Children, Bounds, Opts) ->
    [iso_element:render(Child, Bounds, Opts) || Child <- Children].

