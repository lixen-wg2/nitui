%%%-------------------------------------------------------------------
%%% @doc Resolve rendered bounds for elements within a tree.
%%% @end
%%%-------------------------------------------------------------------
-module(nit_bounds).

-include("nit_elements.hrl").

-export([find_element_bounds/3]).
-export([child_layout/2, tab_content_bounds/2]).

-spec find_element_bounds(tuple(), term(), #bounds{}) -> {ok, #bounds{}} | not_found.
find_element_bounds(Element, Id, Bounds) ->
    do_find_bounds(Element, Id, Bounds).

%% Bounds passed to each child renderer, before the child's own local offsets.
%% Keep this structural: anonymous records must not need an ID lookup for layout.
-spec child_layout(tuple(), #bounds{}) -> [{tuple(), #bounds{}}].
child_layout(#panel{children = Children}, Bounds) ->
    [{Child, Bounds} || Child <- Children];
child_layout(#vbox{children = Children, spacing = Spacing, x = X, y = Y}, Bounds) ->
    StartBounds = Bounds#bounds{x = Bounds#bounds.x + X, y = Bounds#bounds.y + Y},
    ChildHeights = nit_layout:calculate_vbox_heights(Children, Bounds, Spacing, Y),
    stack_layout(Children, ChildHeights, StartBounds, Spacing, vertical);
child_layout(#hbox{children = Children, spacing = Spacing, x = X, y = Y}, Bounds) ->
    StartBounds = Bounds#bounds{x = Bounds#bounds.x + X, y = Bounds#bounds.y + Y},
    ChildWidths = nit_layout:calculate_hbox_widths(Children, Bounds, Spacing, X),
    stack_layout(Children, ChildWidths, StartBounds, Spacing, horizontal);
child_layout(#box{children = Children, border = Border} = Box, Bounds) ->
    Inset = case Border of none -> 0; _ -> 1 end,
    ChildBounds = inset_bounds(resolve_container_bounds(Box, Bounds), Inset),
    [{Child, ChildBounds} || Child <- Children];
child_layout(#tabs{tabs = Tabs, active_tab = ActiveTab0} = Element, Bounds) ->
    {Visible, ChildBounds} = tab_content_bounds(Element, Bounds),
    ActiveTab = resolve_active_tab(ActiveTab0, Tabs),
    case {Visible, lists:keyfind(ActiveTab, #tab.id, Tabs)} of
        {true, #tab{content = Content}} -> [{Child, ChildBounds} || Child <- Content];
        _ -> []
    end;
child_layout(#scroll{children = Children, offset = Offset} = Scroll, Bounds) ->
    %% nit_el_scroll renders into the supplied viewport. Remeasure after reserving
    %% its scrollbar, then distribute flex heights in the full content layout.
    ViewHeight = max(1, Bounds#bounds.height),
    {Width, TotalHeight} = nit_el_scroll:content_size(Scroll, Bounds),
    SafeOffset = min(max(0, Offset), max(0, TotalHeight - ViewHeight)),
    LayoutBounds = #bounds{width = Width, height = max(ViewHeight, TotalHeight)},
    Heights = nit_layout:calculate_vbox_heights(Children, LayoutBounds, 0),
    StartBounds = LayoutBounds#bounds{x = Bounds#bounds.x, y = Bounds#bounds.y - SafeOffset},
    %% Clipped children are rendered offscreen at full height, not resized to the
    %% intersection. Preserve that allocation while translating screen positions.
    stack_layout(Children, Heights, StartBounds, 0, vertical);
child_layout(#modal{children = Children} = Modal, Bounds) ->
    ChildBounds = inset_bounds(resolve_modal_bounds(Modal, Bounds), 1),
    [{Child, ChildBounds} || Child <- Children];
child_layout(_, _) ->
    [].

-spec tab_content_bounds(#tabs{}, #bounds{}) -> {boolean(), #bounds{}}.
tab_content_bounds(Tabs, Bounds) ->
    #bounds{x = X, y = Y, width = Width, height = Height} = resolve_tabs_bounds(Tabs, Bounds),
    {Width > 2 andalso Height >= 3,
     #bounds{x = X + 1, y = Y + 2, width = max(0, Width - 2), height = max(1, Height - 3)}}.

resolve_container_bounds(Element, Bounds) ->
    X = element(#box.x, Element),
    Y = element(#box.y, Element),
    #bounds{x = Bounds#bounds.x + X, y = Bounds#bounds.y + Y,
            width = resolve_dimension(element(#box.width, Element), Bounds#bounds.width - X),
            height = resolve_dimension(element(#box.height, Element), Bounds#bounds.height - Y)}.

resolve_tabs_bounds(#tabs{x = X, y = Y} = Tabs, Bounds) ->
    Resolved = resolve_container_bounds(Tabs, Bounds),
    Resolved#bounds{width = max(0, min(Resolved#bounds.width, Bounds#bounds.width - X)),
                    height = max(0, min(Resolved#bounds.height, Bounds#bounds.height - Y))}.

inset_bounds(#bounds{x = X, y = Y, width = W, height = H}, Inset) ->
    #bounds{x = X + Inset, y = Y + Inset,
            width = max(1, W - 2 * Inset), height = max(1, H - 2 * Inset)}.

resolve_modal_bounds(#modal{width = W, height = H}, Bounds) ->
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
    #bounds{x = ModalX, y = ModalY, width = Width, height = Height}.

do_find_bounds(Element, Id, Bounds)
  when is_record(Element, panel); is_record(Element, vbox); is_record(Element, hbox) ->
    find_in_layout(child_layout(Element, Bounds), Id);
do_find_bounds(#box{id = ElementId} = Element, Id, Bounds) ->
    find_container_bounds(Element, ElementId, Id, Bounds, resolve_container_bounds(Element, Bounds));
do_find_bounds(#tabs{id = ElementId} = Element, Id, Bounds) ->
    find_container_bounds(Element, ElementId, Id, Bounds, resolve_tabs_bounds(Element, Bounds));
do_find_bounds(#scroll{id = ElementId} = Element, Id, Bounds) ->
    find_container_bounds(Element, ElementId, Id, Bounds, resolve_container_bounds(Element, Bounds));
do_find_bounds(#modal{id = ElementId} = Element, Id, Bounds) ->
    find_container_bounds(Element, ElementId, Id, Bounds, resolve_modal_bounds(Element, Bounds));
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

find_container_bounds(_Element, Id, Id, _Bounds, ElementBounds) ->
    {ok, ElementBounds};
find_container_bounds(Element, _ElementId, Id, Bounds, _ElementBounds) ->
    find_in_layout(child_layout(Element, Bounds), Id).

find_in_layout([], _Id) ->
    not_found;
find_in_layout([{Child, Bounds} | Rest], Id) ->
    case do_find_bounds(Child, Id, Bounds) of
        not_found -> find_in_layout(Rest, Id);
        Found -> Found
    end.

stack_layout(Children, Sizes, Bounds, Spacing, Direction) ->
    {Layout, _} = lists:mapfoldl(fun({Child, Size}, CurrentBounds) ->
        {ChildBounds, NextBounds} = case Direction of
            vertical ->
                {CurrentBounds#bounds{height = Size},
                 CurrentBounds#bounds{y = CurrentBounds#bounds.y + Size + Spacing}};
            horizontal ->
                {CurrentBounds#bounds{width = Size},
                 CurrentBounds#bounds{x = CurrentBounds#bounds.x + Size + Spacing}}
        end,
        {{Child, ChildBounds}, NextBounds}
    end, Bounds, lists:zip(Children, Sizes)),
    Layout.

resolve_table_bounds(#table{x = X, y = Y, width = W, height = H,
                            rows = Rows, total_rows = TotalRows} = Table, Bounds) ->
    ActualX = Bounds#bounds.x + X,
    ActualY = Bounds#bounds.y + Y,
    Width = resolve_dimension(W, Bounds#bounds.width - X),
    ActualTotalRows = case TotalRows of
        undefined -> length(Rows);
        N -> N
    end,
    Overhead = nit_el_table:overhead(Table),
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
