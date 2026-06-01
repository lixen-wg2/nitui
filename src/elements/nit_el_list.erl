%%%-------------------------------------------------------------------
%%% @doc NitUI List Element
%%%
%%% A selectable list of items with keyboard navigation.
%%% Supports both simple binary items and {Id, Label} tuples.
%%% @end
%%%-------------------------------------------------------------------
-module(nit_el_list).

-behaviour(nit_element).

-include("nit_elements.hrl").

-export([render/3, height/2, width/2, fixed_width/1]).

%%====================================================================
%% nit_element callbacks
%%====================================================================

-spec render(#list{}, #bounds{}, map()) -> iolist().
render(#list{visible = false}, _Bounds, _Opts) ->
    [];
render(#list{items = Items, selected = Selected, offset = Offset,
             item_style = ItemStyle, selected_style = SelectedStyle,
             x = X, y = Y}, Bounds, _Opts) ->
    ActualX = Bounds#bounds.x + X,
    ActualY = Bounds#bounds.y + Y,
    AvailableHeight = Bounds#bounds.height - Y,
    AvailableWidth = Bounds#bounds.width - X,
    
    %% Get visible items based on offset and available height
    VisibleItems = get_visible_items(Items, Offset, AvailableHeight),
    
    %% Render each visible item
    render_items(VisibleItems, ActualX, ActualY, AvailableWidth, 
                 Selected, Offset, ItemStyle, SelectedStyle, []).

-spec height(#list{}, #bounds{}) -> pos_integer() | {flex, non_neg_integer()}.
height(#list{height = auto, items = Items}, Bounds) ->
    min(length(Items), Bounds#bounds.height);
height(#list{height = fill}, _Bounds) -> {flex, 1};
height(#list{height = H}, _Bounds) -> H.

-spec width(#list{}, #bounds{}) -> pos_integer().
width(#list{width = auto}, Bounds) -> Bounds#bounds.width;
width(#list{width = fill}, Bounds) -> Bounds#bounds.width;
width(#list{width = W}, _Bounds) -> W.

-spec fixed_width(#list{}) -> auto | pos_integer().
fixed_width(#list{width = fill}) -> auto;
fixed_width(#list{width = W}) -> W.

%%====================================================================
%% Internal functions
%%====================================================================

get_visible_items(Items, Offset, MaxVisible) ->
    %% Skip items before offset, take up to MaxVisible
    Dropped = lists:nthtail(min(Offset, length(Items)), Items),
    lists:sublist(Dropped, MaxVisible).

render_items([], _X, _Y, _Width, _Selected, _Offset, _ItemStyle, _SelectedStyle, Acc) ->
    lists:reverse(Acc);
render_items([Item | Rest], X, Y, Width, Selected, Offset, ItemStyle, SelectedStyle, Acc) ->
    LineIdx = length(Acc),
    ActualIdx = Offset + LineIdx,
    IsSelected = ActualIdx =:= Selected,
    
    %% Get label from item
    Label = get_item_label(Item),
    
    %% Choose style based on selection
    Style = if IsSelected -> SelectedStyle; true -> ItemStyle end,
    
    %% Render the line
    Line = render_item_line(X, Y + LineIdx, Width, Label, Style),
    
    render_items(Rest, X, Y, Width, Selected, Offset, ItemStyle, SelectedStyle, [Line | Acc]).

get_item_label(Item) when is_binary(Item) -> Item;
get_item_label(Item) when is_list(Item) -> list_to_binary(Item);
get_item_label({_Id, Label}) when is_binary(Label) -> Label;
get_item_label({_Id, Label}) when is_list(Label) -> list_to_binary(Label).

render_item_line(X, Y, Width, Label, Style) ->
    %% Truncate label to fit
    MaxLabelLen = Width,
    TruncatedLabel = truncate_label(Label, MaxLabelLen),
    
    %% Pad to full width for consistent highlighting
    LabelLen = string:length(unicode:characters_to_list(TruncatedLabel)),
    Padding = binary:copy(<<" ">>, max(0, MaxLabelLen - LabelLen)),
    
    [
        nit_ansi:move_to(Y, X),
        nit_ansi:style_to_ansi(Style),
        TruncatedLabel,
        Padding,
        nit_ansi:reset_style()
    ].

truncate_label(_Label, MaxLen) when MaxLen =< 0 ->
    <<>>;
truncate_label(Label, MaxLen) ->
    LabelList = unicode:characters_to_list(Label),
    case string:length(LabelList) > MaxLen of
        true ->
            Truncated = string:slice(LabelList, 0, MaxLen - 1),
            unicode:characters_to_binary(Truncated ++ "…");
        false ->
            Label
    end.
