%%%-------------------------------------------------------------------
%%% @doc NitUI Layout Utilities
%%%
%%% Centralized size calculation functions for elements.
%%% Dispatches to element modules via iso_element behaviour.
%%% @end
%%%-------------------------------------------------------------------
-module(iso_layout).

-include("iso_elements.hrl").

-export([element_height/2, element_width/2, element_fixed_width/1]).
-export([calculate_vbox_heights/3, calculate_vbox_heights/4]).
-export([calculate_hbox_widths/3, calculate_hbox_widths/4]).

%%====================================================================
%% API
%%====================================================================

%% @doc Calculate the height of an element given bounds.
%% Dispatches to element module's height/2 callback.
%% Returns pos_integer() for fixed heights, or {flex, Min} for flexible elements.
-spec element_height(tuple(), #bounds{}) -> pos_integer() | {flex, non_neg_integer()}.
element_height(Element, Bounds) when is_tuple(Element) ->
    iso_element:height(Element, Bounds);
element_height(_, _) ->
    1.

%% @doc Calculate the width of an element given bounds.
%% Dispatches to element module's width/2 callback.
-spec element_width(tuple(), #bounds{}) -> pos_integer().
element_width(Element, Bounds) when is_tuple(Element) ->
    iso_element:width(Element, Bounds);
element_width(_, _) ->
    1.

%% @doc Returns the fixed width of an element, or 'auto' if it should fill remaining space.
%% Used by hbox layout to distribute space among children.
%% Dispatches to element module's fixed_width/1 callback.
-spec element_fixed_width(tuple()) -> auto | pos_integer().
element_fixed_width(Element) when is_tuple(Element) ->
    iso_element:fixed_width(Element);
element_fixed_width(_) ->
    auto.

%%====================================================================
%% VBox Layout Helpers
%%====================================================================

%% @doc Calculate heights for vbox children, distributing remaining space to flex elements.
%% Flex elements (like spacer) return {flex, MinHeight} from their height/2 callback.
%% This function resolves those to actual pixel heights based on available space.
-spec calculate_vbox_heights([tuple()], #bounds{}, non_neg_integer()) -> [pos_integer()].
calculate_vbox_heights(Children, Bounds, Spacing) ->
    calculate_vbox_heights(Children, Bounds, Spacing, 0).

%% @doc Calculate heights for vbox children with an explicit local Y offset.
%% The local offset is needed because bounds.y is absolute in nested layouts.
-spec calculate_vbox_heights([tuple()], #bounds{}, non_neg_integer(), non_neg_integer()) ->
    [pos_integer()].
calculate_vbox_heights(Children, Bounds, Spacing, LocalY) ->
    %% First pass: get raw heights and identify flex elements
    RawHeights = [element_height(C, Bounds) || C <- Children],

    %% Calculate fixed height total and count flex elements
    {FixedTotal, FlexCount} = lists:foldl(
        fun(H, {Fixed, Count}) ->
            case H of
                {flex, _Min} -> {Fixed, Count + 1};
                N when is_integer(N) -> {Fixed + N, Count}
            end
        end,
        {0, 0},
        RawHeights
    ),

    %% Calculate spacing
    TotalSpacing = max(0, (length(Children) - 1) * Spacing),

    %% Calculate remaining space for flex elements
    %% Bounds height is relative to the current container, while LocalY is the
    %% element's offset within that container.
    AvailableHeight = max(0, Bounds#bounds.height - LocalY),
    RemainingSpace = max(0, AvailableHeight - FixedTotal - TotalSpacing),

    %% Distribute remaining space to flex elements
    FlexHeight = case FlexCount of
        0 -> 0;
        _ -> max(0, RemainingSpace div FlexCount)
    end,

    %% Second pass: resolve flex heights to actual values
    [case H of
        {flex, Min} -> max(Min, FlexHeight);
        N -> N
    end || H <- RawHeights].

%%====================================================================
%% HBox Layout Helpers
%%====================================================================

%% @doc Calculate widths for hbox children, sharing remaining width between auto children.
-spec calculate_hbox_widths([tuple()], #bounds{}, non_neg_integer()) -> [pos_integer()].
calculate_hbox_widths(Children, Bounds, Spacing) ->
    calculate_hbox_widths(Children, Bounds, Spacing, 0).

%% @doc Calculate widths for hbox children with an explicit local X offset.
%% The local offset is needed because bounds.x is absolute in nested layouts.
-spec calculate_hbox_widths([tuple()], #bounds{}, non_neg_integer(), non_neg_integer()) ->
    [pos_integer()].
calculate_hbox_widths(Children, Bounds, Spacing, LocalX) ->
    TotalSpacing = max(0, (length(Children) - 1) * Spacing),
    FixedWidths = [element_fixed_width(C) || C <- Children],
    FixedTotal = lists:sum([case W of auto -> 0; N -> N end || W <- FixedWidths]),
    AutoCount = length([ok || auto <- FixedWidths]),
    AvailableWidth = max(0, Bounds#bounds.width - LocalX),
    RemainingWidth = max(0, AvailableWidth - FixedTotal - TotalSpacing),
    {Widths, _AutoIdx} = lists:mapfoldl(
        fun(FixedWidth, AutoIdx) ->
            case FixedWidth of
                auto ->
                    {auto_width(RemainingWidth, AutoCount, AutoIdx), AutoIdx + 1};
                Width ->
                    {Width, AutoIdx}
            end
        end,
        0,
        FixedWidths
    ),
    Widths.

auto_width(RemainingWidth, AutoCount, AutoIdx) when AutoCount > 0 ->
    BaseWidth = RemainingWidth div AutoCount,
    ExtraWidth = case AutoIdx < (RemainingWidth rem AutoCount) of
        true -> 1;
        false -> 0
    end,
    max(1, BaseWidth + ExtraWidth).
