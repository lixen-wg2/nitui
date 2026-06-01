%%%-------------------------------------------------------------------
%%% @doc NitUI VBox Element
%%%
%%% Renders children vertically with optional spacing.
%%% @end
%%%-------------------------------------------------------------------
-module(iso_el_vbox).

-behaviour(iso_element).

-include("iso_elements.hrl").

-export([render/3, height/2, width/2, fixed_width/1]).

%%====================================================================
%% iso_element callbacks
%%====================================================================

-spec render(#vbox{}, #bounds{}, map()) -> iolist().
render(#vbox{visible = false}, _Bounds, _Opts) ->
    [];
render(#vbox{children = Children, spacing = Spacing, x = X, y = Y}, Bounds, Opts) ->
    StartBounds = Bounds#bounds{
        x = Bounds#bounds.x + X,
        y = Bounds#bounds.y + Y
    },
    %% Calculate heights with flex support (uses shared helper from iso_layout)
    ChildHeights = iso_layout:calculate_vbox_heights(Children, Bounds, Spacing, Y),
    %% Render children with calculated heights
    {Output, _FinalY} = lists:foldl(
        fun({Child, Height}, {Acc, CurrentY}) ->
            ChildBounds = StartBounds#bounds{y = CurrentY, height = Height},
            ChildOutput = iso_element:render(Child, ChildBounds, Opts),
            {[Acc, ChildOutput], CurrentY + Height + Spacing}
        end,
        {[], StartBounds#bounds.y},
        lists:zip(Children, ChildHeights)
    ),
    Output.

-spec height(#vbox{}, #bounds{}) -> pos_integer().
height(#vbox{children = Children, spacing = Spacing}, Bounds) ->
    case Children of
        [] -> 1;
        _ ->
            Heights = [iso_element:height(C, Bounds) || C <- Children],
            TotalSpacing = max(0, (length(Children) - 1) * Spacing),
            %% Check if any child is flex - if so, use full available height
            HasFlex = lists:any(fun({flex, _}) -> true; (_) -> false end, Heights),
            case HasFlex of
                true -> Bounds#bounds.height;
                false -> lists:sum(Heights) + TotalSpacing
            end
    end.

-spec width(#vbox{}, #bounds{}) -> pos_integer().
width(#vbox{width = W, children = Children}, Bounds) ->
    case W of
        auto ->
            case Children of
                [] -> 1;
                _ -> lists:max([iso_element:width(C, Bounds) || C <- Children])
            end;
        fill -> Bounds#bounds.width;
        _ -> W
    end.

-spec fixed_width(#vbox{}) -> auto | pos_integer().
fixed_width(#vbox{width = auto}) -> auto;
fixed_width(#vbox{width = fill}) -> auto;
fixed_width(#vbox{width = W}) -> W.
