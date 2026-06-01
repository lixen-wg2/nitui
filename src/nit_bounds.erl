%%%-------------------------------------------------------------------
%%% @doc Resolve rendered bounds for elements within a tree.
%%% @end
%%%-------------------------------------------------------------------
-module(nit_bounds).

-include("nit_elements.hrl").

-export([find_element_bounds/3]).

-spec find_element_bounds(tuple(), term(), #bounds{}) -> {ok, #bounds{}} | not_found.
find_element_bounds(Element, Id, Bounds) ->
    do_find_bounds(Element, Id, Bounds).

do_find_bounds(#panel{children = Children}, Id, Bounds) ->
    find_in_children(Children, Id, Bounds);
do_find_bounds(#vbox{children = Children, spacing = Spacing, x = X, y = Y}, Id, Bounds) ->
    StartBounds = Bounds#bounds{x = Bounds#bounds.x + X, y = Bounds#bounds.y + Y},
    ChildHeights = nit_layout:calculate_vbox_heights(Children, Bounds, Spacing, Y),
    find_in_vbox(lists:zip(Children, ChildHeights), Id, StartBounds, Spacing,
                 StartBounds#bounds.y);
do_find_bounds(#hbox{children = Children, spacing = Spacing, x = X, y = Y}, Id, Bounds) ->
    StartBounds = Bounds#bounds{x = Bounds#bounds.x + X, y = Bounds#bounds.y + Y},
    ChildWidths = nit_layout:calculate_hbox_widths(Children, Bounds, Spacing, X),
    find_in_hbox(lists:zip(Children, ChildWidths), Id, StartBounds, Spacing,
                 StartBounds#bounds.x);
do_find_bounds(#box{id = ElementId, children = Children,
                    x = X, y = Y, width = W, height = H}, Id, Bounds) ->
    ActualX = Bounds#bounds.x + X,
    ActualY = Bounds#bounds.y + Y,
    Width = resolve_dimension(W, Bounds#bounds.width - X),
    Height = resolve_dimension(H, Bounds#bounds.height - Y),
    ElementBounds = #bounds{x = ActualX, y = ActualY, width = Width, height = Height},
    case ElementId =:= Id of
        true ->
            {ok, ElementBounds};
        false ->
            ChildBounds = #bounds{x = ActualX + 1, y = ActualY + 1,
                                  width = max(1, Width - 2),
                                  height = max(1, Height - 2)},
            find_in_children(Children, Id, ChildBounds)
    end;
do_find_bounds(#tabs{id = ElementId, tabs = TabList, active_tab = ActiveTab0,
                     x = X, y = Y, width = W, height = H}, Id, Bounds) ->
    ActualX = Bounds#bounds.x + X,
    ActualY = Bounds#bounds.y + Y,
    Width = resolve_dimension(W, Bounds#bounds.width - X),
    Height = resolve_dimension(H, Bounds#bounds.height - Y),
    ElementBounds = #bounds{x = ActualX, y = ActualY, width = Width, height = Height},
    case ElementId =:= Id of
        true ->
            {ok, ElementBounds};
        false ->
            ActiveTab = resolve_active_tab(ActiveTab0, TabList),
            ActiveContent = case lists:keyfind(ActiveTab, #tab.id, TabList) of
                #tab{content = Content} -> Content;
                false -> []
            end,
            ContentBounds = #bounds{x = ActualX + 1, y = ActualY + 2,
                                    width = max(1, Width - 2),
                                    height = max(1, Height - 3)},
            find_in_children(ActiveContent, Id, ContentBounds)
    end;
do_find_bounds(#scroll{id = ElementId, children = Children,
                       x = X, y = Y, width = W, height = H}, Id, Bounds) ->
    ActualX = Bounds#bounds.x + X,
    ActualY = Bounds#bounds.y + Y,
    Width = resolve_dimension(W, Bounds#bounds.width - X),
    Height = resolve_dimension(H, Bounds#bounds.height - Y),
    ElementBounds = #bounds{x = ActualX, y = ActualY, width = Width, height = Height},
    case ElementId =:= Id of
        true ->
            {ok, ElementBounds};
        false ->
            ChildBounds = #bounds{x = ActualX, y = ActualY, width = Width, height = Height},
            find_in_children(Children, Id, ChildBounds)
    end;
do_find_bounds(#modal{id = ElementId, children = Children, width = W, height = H},
               Id, Bounds) ->
    Width = case W of
        auto -> min(60, max(1, Bounds#bounds.width - 4));
        fill -> min(60, max(1, Bounds#bounds.width - 4));
        _ -> min(W, max(1, Bounds#bounds.width - 2))
    end,
    Height = case H of
        auto -> min(10, max(1, Bounds#bounds.height - 4));
        fill -> min(10, max(1, Bounds#bounds.height - 4));
        _ -> min(H, max(1, Bounds#bounds.height - 2))
    end,
    ModalX = (Bounds#bounds.width - Width) div 2,
    ModalY = (Bounds#bounds.height - Height) div 2,
    ElementBounds = #bounds{x = ModalX, y = ModalY, width = Width, height = Height},
    case ElementId =:= Id of
        true ->
            {ok, ElementBounds};
        false ->
            ChildBounds = #bounds{x = ModalX + 1, y = ModalY + 1,
                                  width = max(1, Width - 2),
                                  height = max(1, Height - 2)},
            find_in_children(Children, Id, ChildBounds)
    end;
do_find_bounds(#table{id = ElementId} = Table, Id, Bounds) ->
    case ElementId =:= Id of
        true -> {ok, resolve_table_bounds(Table, Bounds)};
        false -> not_found
    end;
do_find_bounds(#list{id = ElementId} = List, Id, Bounds) ->
    case ElementId =:= Id of
        true -> {ok, resolve_list_bounds(List, Bounds)};
        false -> not_found
    end;
do_find_bounds(#tree{id = ElementId} = Tree, Id, Bounds) ->
    case ElementId =:= Id of
        true -> {ok, resolve_tree_bounds(Tree, Bounds)};
        false -> not_found
    end;
do_find_bounds(#button{id = ElementId, x = X, y = Y, width = W, label = Label}, Id, Bounds) ->
    case ElementId =:= Id of
        true ->
            LabelLen = string:length(unicode:characters_to_list(iolist_to_binary([Label]))),
            Width = case W of
                auto -> LabelLen + 4;
                _ -> W
            end,
            {ok, #bounds{x = Bounds#bounds.x + X, y = Bounds#bounds.y + Y,
                         width = Width, height = 1}};
        false ->
            not_found
    end;
do_find_bounds(#input{id = ElementId, x = X, y = Y, width = W}, Id, Bounds) ->
    case ElementId =:= Id of
        true ->
            Width = case W of
                auto -> 20;
                _ -> W
            end,
            {ok, #bounds{x = Bounds#bounds.x + X, y = Bounds#bounds.y + Y,
                         width = Width, height = 1}};
        false ->
            not_found
    end;
do_find_bounds(_, _, _) ->
    not_found.

find_in_children([], _Id, _Bounds) ->
    not_found;
find_in_children([Child | Rest], Id, Bounds) ->
    case do_find_bounds(Child, Id, Bounds) of
        not_found -> find_in_children(Rest, Id, Bounds);
        Found -> Found
    end.

find_in_vbox([], _Id, _Bounds, _Spacing, _CurrentY) ->
    not_found;
find_in_vbox([{Child, Height} | Rest], Id, Bounds, Spacing, CurrentY) ->
    ChildBounds = Bounds#bounds{y = CurrentY, height = Height},
    case do_find_bounds(Child, Id, ChildBounds) of
        not_found ->
            find_in_vbox(Rest, Id, Bounds, Spacing, CurrentY + Height + Spacing);
        Found ->
            Found
    end.

find_in_hbox([], _Id, _Bounds, _Spacing, _CurrentX) ->
    not_found;
find_in_hbox([{Child, ChildWidth} | Rest], Id, Bounds, Spacing, CurrentX) ->
    ChildBounds = Bounds#bounds{x = CurrentX, width = ChildWidth},
    case do_find_bounds(Child, Id, ChildBounds) of
        not_found ->
            find_in_hbox(Rest, Id, Bounds, Spacing,
                         CurrentX + ChildWidth + Spacing);
        Found ->
            Found
    end.

resolve_table_bounds(#table{x = X, y = Y, width = W, height = H,
                            rows = Rows, total_rows = TotalRows,
                            border = Border, show_header = ShowHeader}, Bounds) ->
    ActualX = Bounds#bounds.x + X,
    ActualY = Bounds#bounds.y + Y,
    Width = resolve_dimension(W, Bounds#bounds.width - X),
    ActualTotalRows = case TotalRows of
        undefined -> length(Rows);
        N -> N
    end,
    Overhead = table_overhead(Border, ShowHeader),
    Height = case H of
        auto -> min(ActualTotalRows + Overhead, max(1, Bounds#bounds.height - Y));
        fill -> max(Overhead + 1, Bounds#bounds.height - Y);
        _ -> H
    end,
    #bounds{x = ActualX, y = ActualY, width = Width, height = max(1, Height)}.

resolve_list_bounds(#list{x = X, y = Y, height = H, items = Items}, Bounds) ->
    ActualX = Bounds#bounds.x + X,
    ActualY = Bounds#bounds.y + Y,
    Height = case H of
        auto -> min(length(Items), max(1, Bounds#bounds.height - Y));
        fill -> max(1, Bounds#bounds.height - Y);
        _ -> H
    end,
    #bounds{x = ActualX, y = ActualY,
            width = max(1, Bounds#bounds.width - X),
            height = max(1, Height)}.

resolve_tree_bounds(#tree{x = X, y = Y, width = W} = Tree, Bounds) ->
    ActualX = Bounds#bounds.x + X,
    ActualY = Bounds#bounds.y + Y,
    Width = resolve_dimension(W, Bounds#bounds.width - X),
    Height = nit_tree_nav:resolved_height(Tree, Bounds),
    #bounds{x = ActualX, y = ActualY, width = max(1, Width), height = max(1, Height)}.

resolve_dimension(auto, Available) ->
    max(1, Available);
resolve_dimension(fill, Available) ->
    max(1, Available);
resolve_dimension(Value, _Available) when is_integer(Value) ->
    Value.

resolve_active_tab(undefined, [#tab{id = First} | _]) ->
    First;
resolve_active_tab(undefined, []) ->
    undefined;
resolve_active_tab(ActiveTab, _Tabs) ->
    ActiveTab.

table_overhead(Border, ShowHeader) ->
    BorderOffset = case Border of
        none -> 0;
        _ -> 1
    end,
    HeaderOffset = case ShowHeader of
        true -> 2;
        false -> 0
    end,
    2 * BorderOffset + HeaderOffset.
