%%%-------------------------------------------------------------------
%%% @doc NitUI HBox Element
%%%
%%% Renders children horizontally with optional spacing.
%%% @end
%%%-------------------------------------------------------------------
-module(nit_el_hbox).

-behaviour(nit_element).

-include("nit_elements.hrl").

-export([render/3, height/2, width/2, fixed_width/1]).

%%====================================================================
%% nit_element callbacks
%%====================================================================

-spec render(#hbox{}, #bounds{}, map()) -> iolist().
render(#hbox{visible = false}, _Bounds, _Opts) ->
    [];
render(#hbox{children = Children, spacing = Spacing, x = X, y = Y}, Bounds, Opts) ->
    StartBounds = Bounds#bounds{
        x = Bounds#bounds.x + X,
        y = Bounds#bounds.y + Y
    },
    ChildWidths = nit_layout:calculate_hbox_widths(Children, Bounds, Spacing, X),
    {Output, _FinalX} = lists:foldl(
        fun({Child, ChildWidth}, {Acc, CurrentX}) ->
            ChildBounds = StartBounds#bounds{x = CurrentX, width = ChildWidth},
            ChildOutput = nit_element:render(Child, ChildBounds, Opts),
            {[Acc, ChildOutput], CurrentX + ChildWidth + Spacing}
        end,
        {[], StartBounds#bounds.x},
        lists:zip(Children, ChildWidths)
    ),
    Output.

-spec height(#hbox{}, #bounds{}) -> pos_integer() | {flex, non_neg_integer()}.
height(#hbox{height = fill}, _Bounds) ->
    {flex, 0};
height(#hbox{height = H}, _Bounds) when is_integer(H) ->
    H;
height(#hbox{children = Children, spacing = Spacing, x = X}, Bounds) ->
    case Children of
        [] -> 1;
        _ ->
            %% Measure each child against the width it will actually receive,
            %% otherwise wrapped text reports its single-line parent-width
            %% height instead of its wrapped height.
            ChildWidths = nit_layout:calculate_hbox_widths(Children, Bounds, Spacing, X),
            Heights = [nit_element:height(C, Bounds#bounds{width = W})
                       || {C, W} <- lists:zip(Children, ChildWidths)],
            case lists:any(fun({flex, _}) -> true; (_) -> false end, Heights) of
                true ->
                    MaxMin = lists:max([case H of {flex, M} -> M; N -> N end || H <- Heights]),
                    {flex, MaxMin};
                false ->
                    lists:max(Heights)
            end
    end.

-spec width(#hbox{}, #bounds{}) -> pos_integer().
width(#hbox{width = W, children = Children, spacing = Spacing}, Bounds) ->
    case W of
        auto ->
            case Children of
                [] -> 1;
                _ ->
                    Widths = [nit_element:width(C, Bounds) || C <- Children],
                    TotalSpacing = max(0, (length(Children) - 1) * Spacing),
                    lists:sum(Widths) + TotalSpacing
            end;
        fill -> Bounds#bounds.width;
        _ -> W
    end.

-spec fixed_width(#hbox{}) -> auto | pos_integer().
fixed_width(#hbox{width = auto}) -> auto;
fixed_width(#hbox{width = fill}) -> auto;
fixed_width(#hbox{width = W}) -> W.
