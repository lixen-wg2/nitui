%%%-------------------------------------------------------------------
%%% @doc NitUI Hit Testing - Find elements at screen coordinates.
%%% @end
%%%-------------------------------------------------------------------
-module(nit_hit).

-include("nit_elements.hrl").

-export([find_at/4]).

%% Find interactive element at given screen coordinates
-spec find_at(term(), integer(), integer(), #bounds{}) ->
    {tab, term(), term()} | {button, term()} | {input, term()} |
    {box, term()} | {tabs_container, term()} | {table, term()} |
    {table_header, term(), term()} | {table_row, term(), integer()} | {list, term()} |
    {tree, term()} | {tree_node, term(), term()} | {tree_toggle, term(), term()} |
    {status_bar_item, binary() | string()} |
    {list_item, term(), integer()} | not_found.
find_at(Tree, Col, Row, Bounds) ->
    find_at_impl(Tree, Col, Row, Bounds).

find_at_impl(#panel{children = Children}, Col, Row, Bounds) ->
    find_in_children(Children, Col, Row, Bounds);

find_at_impl(#tabs{id = Id, tabs = TabList, active_tab = ActiveTab0, x = X, y = Y, width = W, height = H, focusable = Focusable}, Col, Row, Bounds) ->
    ActualX = Bounds#bounds.x + X,
    ActualY = Bounds#bounds.y + Y,
    Width = case W of auto -> Bounds#bounds.width - X; fill -> Bounds#bounds.width - X; _ -> W end,
    Height = case H of auto -> Bounds#bounds.height - Y; fill -> Bounds#bounds.height - Y; _ -> H end,
    %% Check if click is on tab bar (first row of tabs widget)
    if
        Row =:= ActualY + 1, Col >= ActualX + 1, Col =< ActualX + Width ->
            case find_clicked_tab(TabList, Col - ActualX, 0) of
                {ok, TabId} -> {tab, Id, TabId};
                not_found when Focusable -> {tabs_container, Id};
                not_found -> not_found
            end;
        %% Click in content area - check active tab's content
        Row > ActualY + 1, Row =< ActualY + Height,
        Col >= ActualX + 1, Col =< ActualX + Width ->
            %% Find active tab and check its content
            ActiveTab = case ActiveTab0 of
                undefined -> case TabList of [#tab{id = First}|_] -> First; [] -> undefined end;
                _ -> ActiveTab0
            end,
            ContentBounds = #bounds{x = ActualX + 1, y = ActualY + 2,
                                    width = Width - 2, height = Height - 3},
            case find_tab_content(TabList, ActiveTab) of
                {ok, Content} ->
                    case find_in_children(Content, Col, Row, ContentBounds) of
                        not_found when Focusable -> {tabs_container, Id};
                        not_found -> not_found;
                        Found -> Found
                    end;
                not_found when Focusable -> {tabs_container, Id};
                not_found -> not_found
            end;
        true -> not_found
    end;

find_at_impl(#button{id = Id, x = X, y = Y, width = W, label = Label}, Col, Row, Bounds) ->
    ActualX = Bounds#bounds.x + X,
    ActualY = Bounds#bounds.y + Y,
    LabelLen = string:length(unicode:characters_to_list(iolist_to_binary([Label]))),
    Width = case W of auto -> LabelLen + 4; fill -> Bounds#bounds.width - X; _ -> W end,
    if
        Row =:= ActualY + 1, Col >= ActualX + 1, Col =< ActualX + Width ->
            {button, Id};
        true -> not_found
    end;

find_at_impl(#input{id = Id, x = X, y = Y, width = W}, Col, Row, Bounds) ->
    ActualX = Bounds#bounds.x + X,
    ActualY = Bounds#bounds.y + Y,
    Width = case W of auto -> 20; fill -> Bounds#bounds.width - X; _ -> W end,
    if
        Row =:= ActualY + 1, Col >= ActualX + 1, Col =< ActualX + Width ->
            {input, Id};
        true -> not_found
    end;

find_at_impl(#box{id = Id, children = Children, x = X, y = Y, width = W, height = H,
                  border = Border, focusable = Focusable}, Col, Row, Bounds) ->
    ActualX = Bounds#bounds.x + X,
    ActualY = Bounds#bounds.y + Y,
    Width = case W of auto -> Bounds#bounds.width - X; fill -> Bounds#bounds.width - X; _ -> W end,
    Height = case H of auto -> Bounds#bounds.height - Y; fill -> Bounds#bounds.height - Y; _ -> H end,
    %% Mirror nit_el_box:render/3: borderless boxes pass bounds through, bordered
    %% boxes shrink by one cell on each side so children can't claim the border row.
    ChildBounds = case Border of
        none ->
            Bounds#bounds{x = ActualX, y = ActualY, width = Width, height = Height};
        _ ->
            Bounds#bounds{x = ActualX + 1, y = ActualY + 1,
                          width = max(1, Width - 2), height = max(1, Height - 2)}
    end,
    %% First check if we hit a child element
    case find_in_children(Children, Col, Row, ChildBounds) of
        not_found when Focusable,
                       Row > ActualY, Row =< ActualY + Height,
                       Col > ActualX, Col =< ActualX + Width ->
            %% Click is inside the box but not on a child - return box container
            {box, Id};
        not_found -> not_found;
        Found -> Found
    end;

find_at_impl(#vbox{children = Children, spacing = Spacing, x = X, y = Y}, Col, Row, Bounds) ->
    ChildBounds = Bounds#bounds{x = Bounds#bounds.x + X, y = Bounds#bounds.y + Y},
    ChildHeights = nit_layout:calculate_vbox_heights(Children, Bounds, Spacing, Y),
    find_in_children_vbox(lists:zip(Children, ChildHeights), Col, Row, ChildBounds, Spacing);

find_at_impl(#hbox{children = Children, spacing = Spacing, x = X, y = Y}, Col, Row, Bounds) ->
    StartBounds = Bounds#bounds{x = Bounds#bounds.x + X, y = Bounds#bounds.y + Y},
    ChildWidths = nit_layout:calculate_hbox_widths(Children, Bounds, Spacing, X),
    find_in_children_hbox(lists:zip(Children, ChildWidths), Col, Row, StartBounds, Spacing);

find_at_impl(#table{id = Id, x = X, y = Y, width = W, height = H, border = Border,
                    show_header = ShowHeader,
                    columns = Columns, rows = Rows, total_rows = TotalRows} = Table, Col, Row, Bounds) ->
    ActualX = Bounds#bounds.x + X,
    ActualY = Bounds#bounds.y + Y,
    Width = case W of auto -> Bounds#bounds.width - X; fill -> Bounds#bounds.width - X; _ -> W end,
    ActualTotalRows = case TotalRows of
        undefined -> length(Rows);
        N -> N
    end,
    Overhead = nit_el_table:overhead(Table),
    Height = case H of
        auto -> min(ActualTotalRows + Overhead, Bounds#bounds.height - Y);
        fill -> max(Overhead + 1, Bounds#bounds.height - Y);
        _ -> H
    end,
    BorderOffset = case Border of none -> 0; _ -> 1 end,
    HeaderOffset = nit_el_table:header_height(Table),
    VisibleHeight = max(0, Height - 2 * BorderOffset - HeaderOffset),
    ScrollOffset = nit_el_table:clamp_scroll_offset(Table, VisibleHeight),
    VisibleRows = nit_el_table:visible_rows(Table, VisibleHeight),
    ColWidths = nit_el_table:column_widths(Table, VisibleRows, Width - 2 * BorderOffset),
    SeparatorWidth = nit_el_table:column_separator_width(Table),
    HeaderRow = ActualY + BorderOffset + 1,
    %% Check if click is within table bounds
    if
        ShowHeader =:= true,
        Col >= ActualX + BorderOffset + 1, Col =< ActualX + Width - BorderOffset,
        Row =:= HeaderRow ->
            case find_clicked_table_column(Columns, ColWidths, Col - ActualX - BorderOffset,
                                           SeparatorWidth) of
                {ok, ColumnId} -> {table_header, Id, ColumnId};
                not_found -> {table, Id}
            end;
        Col >= ActualX + BorderOffset, Col =< ActualX + Width - BorderOffset,
        Row > ActualY + BorderOffset + HeaderOffset, Row =< ActualY + Height - BorderOffset ->
            %% Calculate which row was clicked
            ClickedRowIdx = Row - ActualY - BorderOffset - HeaderOffset + ScrollOffset,
            if
                ClickedRowIdx >= 1, ClickedRowIdx =< ActualTotalRows ->
                    {table_row, Id, ClickedRowIdx};
                true ->
                    {table, Id}
            end;
        Col >= ActualX, Col =< ActualX + Width,
        Row >= ActualY, Row =< ActualY + Height ->
            {table, Id};
        true ->
            not_found
    end;

find_at_impl(#list{id = Id, x = X, y = Y, height = H, items = Items, offset = Offset}, Col, Row, Bounds) ->
    ActualX = Bounds#bounds.x + X,
    ActualY = Bounds#bounds.y + Y,
    Height = case H of auto -> min(length(Items), Bounds#bounds.height - Y); fill -> Bounds#bounds.height - Y; _ -> H end,
    Width = Bounds#bounds.width - X,
    if
        Col >= ActualX + 1, Col =< ActualX + Width,
        Row > ActualY, Row =< ActualY + Height ->
            %% Calculate which item was clicked
            ClickedIdx = Row - ActualY - 1 + Offset,
            if
                ClickedIdx >= 0, ClickedIdx < length(Items) ->
                    {list_item, Id, ClickedIdx};
                true ->
                    {list, Id}
            end;
        true ->
            not_found
    end;

find_at_impl(#tree{id = Id, x = X, y = Y, width = W} = Tree, Col, Row, Bounds) ->
    ActualX = Bounds#bounds.x + X,
    ActualY = Bounds#bounds.y + Y,
    Width = case W of auto -> Bounds#bounds.width - X; fill -> Bounds#bounds.width - X; _ -> W end,
    Height = nit_tree_nav:resolved_height(Tree, Bounds),
    if
        Col >= ActualX + 1, Col =< ActualX + Width,
        Row > ActualY, Row =< ActualY + Height ->
            case tree_row_hit(Tree, Bounds, Row - ActualY, Col - ActualX - 1) of
                {ok, toggle, NodeId} -> {tree_toggle, Id, NodeId};
                {ok, node, NodeId} -> {tree_node, Id, NodeId};
                not_found -> {tree, Id}
            end;
        true ->
            not_found
    end;

find_at_impl(#status_bar{} = StatusBar, Col, Row, Bounds) ->
    case nit_el_status_bar:item_at(StatusBar, Col, Row, Bounds) of
        {ok, Key} -> {status_bar_item, Key};
        not_found -> not_found
    end;

find_at_impl(#scroll{children = Children, x = X, y = Y, width = W, height = H,
                     offset = Offset, show_scrollbar = ShowBar}, Col, Row, Bounds) ->
    ActualX = Bounds#bounds.x + X,
    ActualY = Bounds#bounds.y + Y,
    Width = case W of
        auto -> Bounds#bounds.width - X;
        fill -> Bounds#bounds.width - X;
        _ -> W
    end,
    Height = case H of
        auto -> Bounds#bounds.height - Y;
        fill -> Bounds#bounds.height - Y;
        _ -> H
    end,
    case Col >= ActualX + 1 andalso Col =< ActualX + Width andalso
         Row >= ActualY + 1 andalso Row =< ActualY + Height of
        false ->
            not_found;
        true ->
            ScrollBounds = #bounds{x = ActualX, y = ActualY, width = Width, height = Height},
            TotalHeight = lists:sum([nit_element:height(Child, ScrollBounds) || Child <- Children]),
            ContentWidth = case ShowBar andalso TotalHeight > Height of
                true -> max(1, Width - 1);
                false -> Width
            end,
            ClampedOffset = min(max(0, Offset), max(0, TotalHeight - Height)),
            ContentHeight = max(Height, TotalHeight),
            ContentBounds = #bounds{x = ActualX, y = ActualY - ClampedOffset,
                                    width = ContentWidth, height = ContentHeight},
            ChildHeights = nit_layout:calculate_vbox_heights(Children, ContentBounds, 0),
            find_in_children_vbox(lists:zip(Children, ChildHeights), Col, Row, ContentBounds, 0)
    end;

find_at_impl(#modal{children = Children, width = W, height = H}, Col, Row, Bounds) ->
    %% Modal is centered - calculate actual position (same as in nit_render)
    Width = case W of
        auto -> min(60, Bounds#bounds.width - 4);
        fill -> min(60, Bounds#bounds.width - 4);
        _ -> min(W, Bounds#bounds.width - 2)
    end,
    Height = case H of
        auto -> min(10, Bounds#bounds.height - 4);
        fill -> min(10, Bounds#bounds.height - 4);
        _ -> min(H, Bounds#bounds.height - 2)
    end,
    ModalX = (Bounds#bounds.width - Width) div 2,
    ModalY = (Bounds#bounds.height - Height) div 2,
    %% Check if click is inside modal bounds
    if
        Col >= ModalX + 1, Col =< ModalX + Width,
        Row >= ModalY + 1, Row =< ModalY + Height ->
            %% Inside modal - check children with adjusted bounds
            ChildBounds = #bounds{x = ModalX + 1, y = ModalY + 1,
                                  width = max(1, Width - 2), height = max(1, Height - 2)},
            find_in_children(Children, Col, Row, ChildBounds);
        true ->
            not_found
    end;

find_at_impl(_, _, _, _) -> not_found.

tree_row_hit(Tree = #tree{indent = Indent}, Bounds, Row, RelCol) ->
    case nth_visible_tree_row(Row, nit_tree_nav:visible_nodes(Tree, Bounds)) of
        {Depth, _IsLast, #tree_node{id = NodeId, children = Children}} ->
            PrefixWidth = Depth * Indent,
            case Children =/= [] andalso
                 RelCol >= PrefixWidth andalso RelCol =< PrefixWidth + 2 of
                true -> {ok, toggle, NodeId};
                false -> {ok, node, NodeId}
            end;
        false ->
            not_found
    end.

nth_visible_tree_row(1, [Row | _]) ->
    Row;
nth_visible_tree_row(N, [_ | Rest]) when N > 1 ->
    nth_visible_tree_row(N - 1, Rest);
nth_visible_tree_row(_, []) ->
    false.

find_in_children([], _, _, _) -> not_found;
find_in_children([Child | Rest], Col, Row, Bounds) ->
    case find_at_impl(Child, Col, Row, Bounds) of
        not_found -> find_in_children(Rest, Col, Row, Bounds);
        Found -> Found
    end.

find_clicked_tab([], _, _) -> not_found;
find_clicked_tab([#tab{id = Id, label = Label} | Rest], ClickCol, CurrentX) ->
    LabelLen = string:length(unicode:characters_to_list(iolist_to_binary([Label]))),
    TabWidth = LabelLen + 3,  %% " Label " + separator
    if
        ClickCol >= CurrentX, ClickCol < CurrentX + TabWidth ->
            {ok, Id};
        true ->
            find_clicked_tab(Rest, ClickCol, CurrentX + TabWidth)
    end.

%% Find content of active tab
find_tab_content([], _) -> not_found;
find_tab_content([#tab{id = Id, content = Content} | _], Id) -> {ok, Content};
find_tab_content([_ | Rest], ActiveTab) -> find_tab_content(Rest, ActiveTab).

%% Find in hbox children with proper width calculation
find_in_children_hbox([], _, _, _, _) -> not_found;
find_in_children_hbox([{Child, ChildWidth} | Rest], Col, Row, Bounds, Spacing) ->
    ChildBounds = Bounds#bounds{width = ChildWidth},
    case find_at_impl(Child, Col, Row, ChildBounds) of
        not_found ->
            NextBounds = Bounds#bounds{x = Bounds#bounds.x + ChildWidth + Spacing},
            find_in_children_hbox(Rest, Col, Row, NextBounds, Spacing);
        Found -> Found
    end.

%% Find in vbox children with the same resolved heights as rendering.
find_in_children_vbox([], _, _, _, _) -> not_found;
find_in_children_vbox([{Child, ChildHeight} | Rest], Col, Row, Bounds, Spacing) ->
    ChildBounds = Bounds#bounds{height = ChildHeight},
    case find_at_impl(Child, Col, Row, ChildBounds) of
        not_found ->
            NextBounds = Bounds#bounds{y = Bounds#bounds.y + ChildHeight + Spacing},
            find_in_children_vbox(Rest, Col, Row, NextBounds, Spacing);
        Found -> Found
    end.

find_clicked_table_column([], [], _ClickCol, _SeparatorWidth) ->
    not_found;
find_clicked_table_column([#table_col{id = Id}], [Width], ClickCol, _SeparatorWidth) ->
    if
        ClickCol >= 1, ClickCol =< Width -> {ok, Id};
        true -> not_found
    end;
find_clicked_table_column([#table_col{id = Id} | Rest], [Width | RestWidths], ClickCol,
                           SeparatorWidth) ->
    if
        ClickCol >= 1, ClickCol =< Width + SeparatorWidth ->
            {ok, Id};
        true ->
            find_clicked_table_column(Rest, RestWidths, ClickCol - Width - SeparatorWidth,
                                      SeparatorWidth)
    end.
