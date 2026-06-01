%%%-------------------------------------------------------------------
%%% @doc NitUI Panel Element
%%%
%%% Renders a simple container without border.
%%% @end
%%%-------------------------------------------------------------------
-module(iso_el_panel).

-behaviour(iso_element).

-include("iso_elements.hrl").

-export([render/3, height/2, width/2, fixed_width/1]).

%%====================================================================
%% iso_element callbacks
%%====================================================================

-spec render(#panel{}, #bounds{}, map()) -> iolist().
render(#panel{visible = false}, _Bounds, _Opts) ->
    [];
render(#panel{children = Children, x = X, y = Y}, Bounds, Opts) ->
    ChildBounds = Bounds#bounds{
        x = Bounds#bounds.x + X,
        y = Bounds#bounds.y + Y
    },
    [iso_element:render(Child, ChildBounds, Opts) || Child <- Children].

-spec height(#panel{}, #bounds{}) -> pos_integer().
height(#panel{height = H, children = Children}, Bounds) ->
    case H of
        auto ->
            case Children of
                [] -> 1;
                _ -> lists:max([iso_element:height(C, Bounds) || C <- Children])
            end;
        fill -> Bounds#bounds.height;
        _ -> H
    end.

-spec width(#panel{}, #bounds{}) -> pos_integer().
width(#panel{width = W, children = Children}, Bounds) ->
    case W of
        auto ->
            case Children of
                [] -> 1;
                _ -> lists:max([iso_element:width(C, Bounds) || C <- Children])
            end;
        fill -> Bounds#bounds.width;
        _ -> W
    end.

-spec fixed_width(#panel{}) -> auto | pos_integer().
fixed_width(#panel{width = auto}) -> auto;
fixed_width(#panel{width = fill}) -> auto;
fixed_width(#panel{width = W}) -> W.

