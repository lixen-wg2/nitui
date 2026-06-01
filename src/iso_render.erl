%%%-------------------------------------------------------------------
%%% @doc NitUI Renderer
%%%
%%% Renders element trees to ANSI escape sequences.
%%% Each element is rendered within its calculated bounds.
%%% @end
%%%-------------------------------------------------------------------
-module(iso_render).

-include("iso_elements.hrl").

-export([render/2, render_dimmed/3]).
-export([render_two_level/4, render_two_level/5]).

%%====================================================================
%% API
%%====================================================================

%% @doc Render an element tree to iolist within given bounds.
%% Dispatches to element modules via iso_element behaviour.
-spec render(tuple(), #bounds{}) -> iolist().
render(Element, Bounds) ->
    render_with_opts(Element, Bounds, #{}).

%% @doc Render an element with options (focused, base_style, etc.)
%% This is the main dispatch function to element modules.
-spec render_with_opts(tuple(), #bounds{}, map()) -> iolist().
render_with_opts(Element, Bounds, Opts) when is_tuple(Element) ->
    iso_element:render(Element, Bounds, Opts);
render_with_opts(_, _, _) ->
    [].

%% @doc Render element tree with dim styling (for background behind modal).
-spec render_dimmed(tuple(), #bounds{}, term()) -> iolist().
render_dimmed(Element, Bounds, FocusedId) ->
    render_focused_styled(Element, Bounds, FocusedId, #{dim => true}).

%% @doc Render with two-level focus: container and child.
%% Container gets a highlighted border, child gets element focus.
-spec render_two_level(tuple(), #bounds{}, term(), term()) -> iolist().
render_two_level(Element, Bounds, FocusedContainer, FocusedChild) ->
    render_two_level_impl(Element, Bounds, FocusedContainer, FocusedChild, #{}).

%% @doc Render with two-level focus and additional options (e.g., cursor_visible).
-spec render_two_level(tuple(), #bounds{}, term(), term(), map()) -> iolist().
render_two_level(Element, Bounds, FocusedContainer, FocusedChild, Opts) ->
    render_two_level_impl(Element, Bounds, FocusedContainer, FocusedChild, Opts).

%%====================================================================
%% Internal - Two-Level Focus Rendering
%% FocusedContainer: ID of container that has Tab focus (box/tabs)
%% FocusedChild: ID of element within container that has arrow focus
%% Opts: optional map with cursor_visible, etc.
%%====================================================================

render_two_level_impl(#panel{children = Children}, Bounds, Container, Child, Opts) ->
    render_children_two_level(Children, Bounds, Container, Child, Opts);
render_two_level_impl(#vbox{children = Children, spacing = Spacing, x = X, y = Y}, Bounds, Container, Child, Opts) ->
    StartBounds = Bounds#bounds{x = Bounds#bounds.x + X, y = Bounds#bounds.y + Y},
    %% Calculate heights with flex support for spacers (uses shared helper)
    ChildHeights = iso_layout:calculate_vbox_heights(Children, Bounds, Spacing, Y),
    {Output, _} = lists:foldl(
        fun({Elem, Height}, {Acc, CurrentY}) ->
            ElemBounds = StartBounds#bounds{y = CurrentY, height = Height},
            ElemOutput = render_two_level_impl(Elem, ElemBounds, Container, Child, Opts),
            {[Acc, ElemOutput], CurrentY + Height + Spacing}
        end, {[], StartBounds#bounds.y}, lists:zip(Children, ChildHeights)),
    Output;
render_two_level_impl(#hbox{children = Children, spacing = Spacing, x = X, y = Y}, Bounds, Container, Child, Opts) ->
    StartBounds = Bounds#bounds{x = Bounds#bounds.x + X, y = Bounds#bounds.y + Y},
    ChildWidths = iso_layout:calculate_hbox_widths(Children, Bounds, Spacing, X),
    {Output, _} = lists:foldl(
        fun({Elem, ElemWidth}, {Acc, CurrentX}) ->
            ElemBounds = StartBounds#bounds{x = CurrentX, width = ElemWidth},
            ElemOutput = render_two_level_impl(Elem, ElemBounds, Container, Child, Opts),
            {[Acc, ElemOutput], CurrentX + ElemWidth + Spacing}
        end, {[], StartBounds#bounds.x}, lists:zip(Children, ChildWidths)),
    Output;
render_two_level_impl(#box{id = Id, children = Children, border = Border, title = Title,
                           style = Style, x = X, y = Y, width = W, height = H}, Bounds, Container, Child, Opts) ->
    ActualX = Bounds#bounds.x + X,
    ActualY = Bounds#bounds.y + Y,
    Width = case W of auto -> Bounds#bounds.width - X; fill -> Bounds#bounds.width - X; _ -> W end,
    Height = case H of auto -> Bounds#bounds.height - Y; fill -> Bounds#bounds.height - Y; _ -> H end,
    ChildBounds = #bounds{x = ActualX + 1, y = ActualY + 1,
                          width = max(0, Width - 2), height = max(0, Height - 2)},
    {TL, TR, BL, BR, HZ, VT} = iso_ansi:border_chars(Border),
    %% Container focus: highlight border if this box is the focused container
    IsContainerFocused = Id =:= Container,
    BorderStyle = case IsContainerFocused of
        true -> maps:merge(Style, #{bold => true, fg => yellow});
        false -> Style
    end,
    [
        iso_ansi:style_to_ansi(BorderStyle),
        iso_ansi:move_to(ActualY + 1, ActualX + 1),
        TL, iso_ansi:render_title_line(Title, HZ, Width - 2), TR,
        [[iso_ansi:move_to(ActualY + 1 + Row, ActualX + 1),
          VT, lists:duplicate(Width - 2, $\s), VT]
         || Row <- lists:seq(1, Height - 2)],
        iso_ansi:move_to(ActualY + Height, ActualX + 1),
        BL, iso_ansi:repeat_bin(HZ, Width - 2), BR,
        iso_ansi:reset_style(),
        render_children_two_level(Children, ChildBounds, Container, Child, Opts)
    ];
render_two_level_impl(#button{id = Id} = Button, Bounds, _Container, Child, Opts) ->
    HoveredId = maps:get(hovered_id, Opts, undefined),
    render_button(Button, Bounds, Id =:= Child, Id =:= HoveredId);
render_two_level_impl(#input{id = Id} = Input, Bounds, _Container, Child, Opts) ->
    CursorVisible = maps:get(cursor_visible, Opts, true),
    render_input(Input, Bounds, Id =:= Child, CursorVisible);
render_two_level_impl(#table{id = Id} = Table, Bounds, _Container, Child, _Opts) ->
    %% Use iso_el_table:render which supports row_provider for virtual scrolling
    iso_el_table:render(Table, Bounds, #{focused => Id =:= Child});
render_two_level_impl(#tabs{id = Id} = Tabs, Bounds, Container, Child, Opts) ->
    IsContainerFocused = Id =:= Container,
    render_tabs_two_level(Tabs, Bounds, IsContainerFocused, Child, Opts);
render_two_level_impl(#tree{id = Id} = Tree, Bounds, Container, _Child, _Opts) ->
    %% Tree is a container - pass focus info to element renderer
    IsContainerFocused = Id =:= Container,
    render_with_opts(Tree, Bounds, #{focused => IsContainerFocused});
render_two_level_impl(#modal{} = Modal, Bounds, _Container, Child, Opts) ->
    render_modal(Modal, Bounds, Child, Opts);
render_two_level_impl(Element, Bounds, _Container, _Child, _Opts) ->
    render(Element, Bounds).

render_children_two_level(Children, Bounds, Container, Child, Opts) ->
    [render_two_level_impl(C, Bounds, Container, Child, Opts) || C <- Children].

%% Tabs with two-level focus
render_tabs_two_level(#tabs{tabs = TabList, active_tab = ActiveTab0,
                            style = Style, x = X, y = Y, width = W, height = H},
                      Bounds, IsContainerFocused, FocusedChild, Opts) ->
    ActualX = Bounds#bounds.x + X,
    ActualY = Bounds#bounds.y + Y,
    Width = case W of auto -> Bounds#bounds.width - X; fill -> Bounds#bounds.width - X; _ -> W end,
    Height = case H of auto -> Bounds#bounds.height - Y; fill -> Bounds#bounds.height - Y; _ -> H end,
    %% Default active tab to first if undefined
    ActiveTab = case ActiveTab0 of
        undefined -> case TabList of [#tab{id = First}|_] -> First; [] -> undefined end;
        _ -> ActiveTab0
    end,
    %% Draw border around the entire tabs widget
    BorderStyle = if
        IsContainerFocused -> maps:merge(Style, #{fg => yellow, bold => true});
        true -> Style
    end,
    Border = iso_ansi:render_box_border(ActualX, ActualY, Width, Height, BorderStyle, undefined, single),
    %% Tab headers with focus indicator (inside the top border)
    TabHeaders = render_tab_headers_two_level(TabList, ActiveTab, FocusedChild,
                                               ActualX + 1, ActualY, Style, IsContainerFocused),
    %% Active tab content (inside the border, below tab bar which is on row 1)
    ContentBounds = #bounds{x = ActualX + 1, y = ActualY + 2,
                            width = Width - 2, height = max(1, Height - 3)},
    ActiveContent = case lists:keyfind(ActiveTab, #tab.id, TabList) of
        #tab{content = Content} -> Content;
        false -> []
    end,
    ContentOutput = [render_two_level_impl(C, ContentBounds, undefined, undefined, Opts) || C <- ActiveContent],
    [Border, TabHeaders, ContentOutput].

render_tab_headers_two_level(Tabs, ActiveTab, FocusedChild, X, Y, Style, IsContainerFocused) ->
    {Headers, _} = lists:foldl(
        fun(#tab{id = Id, label = Label}, {Acc, CurX}) ->
            IsActive = Id =:= ActiveTab,
            IsFocused = Id =:= FocusedChild andalso IsContainerFocused,
            TabStyle = if
                IsFocused ->
                    %% Focused tab (arrow navigated to it)
                    maps:merge(Style, #{bg => white, fg => black, bold => true});
                IsActive ->
                    %% Active but not focused - darker background
                    maps:merge(Style, #{bg => cyan, fg => black});
                true ->
                    %% Inactive tabs - dimmed
                    maps:merge(Style, #{dim => true})
            end,
            LabelBin = iolist_to_binary([<<" ">>, Label, <<" ">>]),
            LabelLen = byte_size(LabelBin),
            Header = [
                iso_ansi:move_to(Y + 1, CurX + 1),
                iso_ansi:style_to_ansi(TabStyle),
                LabelBin,
                iso_ansi:reset_style()
            ],
            {[Acc, Header], CurX + LabelLen + 1}
        end, {[], X}, Tabs),
    Headers.

%%====================================================================
%% Internal - Styled Rendering (with base style modifier for dimming)
%%====================================================================

render_focused_styled(#panel{children = Children}, Bounds, FocusedId, BaseStyle) ->
    render_children_styled(Children, Bounds, FocusedId, BaseStyle);
render_focused_styled(#vbox{children = Children, spacing = Spacing, x = X, y = Y}, Bounds, FocusedId, BaseStyle) ->
    StartBounds = Bounds#bounds{x = Bounds#bounds.x + X, y = Bounds#bounds.y + Y},
    %% Calculate heights with flex support for spacers (uses shared helper)
    ChildHeights = iso_layout:calculate_vbox_heights(Children, Bounds, Spacing, Y),
    {Output, _} = lists:foldl(
        fun({Child, Height}, {Acc, CurrentY}) ->
            ChildBounds = StartBounds#bounds{y = CurrentY, height = Height},
            ChildOutput = render_focused_styled(Child, ChildBounds, FocusedId, BaseStyle),
            {[Acc, ChildOutput], CurrentY + Height + Spacing}
        end, {[], StartBounds#bounds.y}, lists:zip(Children, ChildHeights)),
    Output;
render_focused_styled(#hbox{children = Children, spacing = Spacing, x = X, y = Y}, Bounds, FocusedId, BaseStyle) ->
    StartBounds = Bounds#bounds{x = Bounds#bounds.x + X, y = Bounds#bounds.y + Y},
    ChildWidths = iso_layout:calculate_hbox_widths(Children, Bounds, Spacing, X),
    {Output, _} = lists:foldl(
        fun({Child, ChildWidth}, {Acc, CurrentX}) ->
            ChildBounds = StartBounds#bounds{x = CurrentX, width = ChildWidth},
            ChildOutput = render_focused_styled(Child, ChildBounds, FocusedId, BaseStyle),
            {[Acc, ChildOutput], CurrentX + ChildWidth + Spacing}
        end, {[], StartBounds#bounds.x}, lists:zip(Children, ChildWidths)),
    Output;
render_focused_styled(#box{border = Border, title = Title, children = Children,
                    style = Style, x = X, y = Y, width = W, height = H}, Bounds, FocusedId, BaseStyle) ->
    ActualX = Bounds#bounds.x + X,
    ActualY = Bounds#bounds.y + Y,
    Width = iso_ansi:resolve_size(W, Bounds#bounds.width - X),
    Height = iso_ansi:resolve_size(H, Bounds#bounds.height - Y),
    {TL, TR, BL, BR, HZ, VT} = iso_ansi:border_chars(Border),
    ChildBounds = #bounds{x = ActualX + 1, y = ActualY + 1,
                          width = max(1, Width - 2), height = max(1, Height - 2)},
    MergedStyle = maps:merge(Style, BaseStyle),
    [
        iso_ansi:style_to_ansi(MergedStyle),
        iso_ansi:move_to(ActualY + 1, ActualX + 1),
        TL, iso_ansi:render_title_line(Title, HZ, Width - 2), TR,
        [[iso_ansi:move_to(ActualY + 1 + Row, ActualX + 1),
          VT, lists:duplicate(Width - 2, $\s), VT]
         || Row <- lists:seq(1, Height - 2)],
        iso_ansi:move_to(ActualY + Height, ActualX + 1),
        BL, iso_ansi:repeat_bin(HZ, Width - 2), BR,
        iso_ansi:reset_style(),
        render_children_styled(Children, ChildBounds, FocusedId, BaseStyle)
    ];
render_focused_styled(#text{} = Text, Bounds, _FocusedId, BaseStyle) ->
    iso_el_text:render(Text, Bounds, #{base_style => BaseStyle});
render_focused_styled(#button{id = Id} = Button, Bounds, FocusedId, BaseStyle) ->
    render_button_styled(Button, Bounds, Id =:= FocusedId, BaseStyle);
render_focused_styled(#input{id = Id} = Input, Bounds, FocusedId, BaseStyle) ->
    render_input_styled(Input, Bounds, Id =:= FocusedId, BaseStyle);
render_focused_styled(#tabs{} = Tabs, Bounds, FocusedId, BaseStyle) ->
    render_tabs_styled(Tabs, Bounds, FocusedId, BaseStyle);
render_focused_styled(#table{} = Table, Bounds, _FocusedId, BaseStyle) ->
    render_table_styled(Table, Bounds, BaseStyle);
render_focused_styled(_Element, _Bounds, _FocusedId, _BaseStyle) ->
    [].

render_children_styled(Children, Bounds, FocusedId, BaseStyle) ->
    [render_focused_styled(Child, Bounds, FocusedId, BaseStyle) || Child <- Children].

render_button_styled(#button{label = Label, style = Style, x = X, y = Y, width = W}, Bounds, Focused, BaseStyle) ->
    ActualX = Bounds#bounds.x + X,
    ActualY = Bounds#bounds.y + Y,
    LabelBin = iolist_to_binary([Label]),
    LabelLen = string:length(unicode:characters_to_list(LabelBin)),
    Width = case W of
        auto -> LabelLen + button_padding_width();
        fill -> Bounds#bounds.width - X;
        _ -> W
    end,
    FocusStyle = button_state_style(Style, Focused, false),
    MergedStyle = maps:merge(FocusStyle, BaseStyle),
    Padding = max(0, Width - LabelLen),
    LeftPad = Padding div 2,
    RightPad = Padding - LeftPad,
    [
        iso_ansi:move_to(ActualY + 1, ActualX + 1),
        iso_ansi:style_to_ansi(MergedStyle),
        lists:duplicate(LeftPad, $\s), LabelBin, lists:duplicate(RightPad, $\s),
        iso_ansi:reset_style()
    ].

render_input_styled(Input, Bounds, Focused, BaseStyle) ->
    iso_el_input:render(Input, Bounds, #{focused => Focused, base_style => BaseStyle}).

%% Render tabs with base style (for dimmed background)
render_tabs_styled(#tabs{tabs = TabList, active_tab = ActiveTab0,
                         style = Style, x = X, y = Y, width = W, height = H},
                   Bounds, _FocusedId, BaseStyle) ->
    ActualX = Bounds#bounds.x + X,
    ActualY = Bounds#bounds.y + Y,
    Width = case W of auto -> Bounds#bounds.width - X; fill -> Bounds#bounds.width - X; _ -> W end,
    Height = case H of auto -> Bounds#bounds.height - Y; fill -> Bounds#bounds.height - Y; _ -> H end,
    ActiveTab = case ActiveTab0 of
        undefined -> case TabList of [#tab{id = First}|_] -> First; [] -> undefined end;
        _ -> ActiveTab0
    end,
    MergedStyle = maps:merge(Style, BaseStyle),
    %% Draw border
    Border = iso_ansi:render_box_border(ActualX, ActualY, Width, Height, MergedStyle, undefined, single),
    %% Tab headers
    TabHeaders = render_tab_headers_styled(TabList, ActiveTab, ActualX + 1, ActualY, MergedStyle),
    %% Content
    ContentBounds = #bounds{x = ActualX + 1, y = ActualY + 2,
                            width = Width - 2, height = max(1, Height - 3)},
    ActiveContent = case lists:keyfind(ActiveTab, #tab.id, TabList) of
        #tab{content = Content} -> Content;
        false -> []
    end,
    ContentOutput = render_children_styled(ActiveContent, ContentBounds, undefined, BaseStyle),
    [Border, TabHeaders, ContentOutput].

render_tab_headers_styled(Tabs, ActiveTab, X, Y, Style) ->
    {Headers, _} = lists:foldl(
        fun(#tab{id = Id, label = Label}, {Acc, CurX}) ->
            LabelBin = iolist_to_binary([Label]),
            LabelLen = byte_size(LabelBin),
            TabStyle = if
                Id =:= ActiveTab -> maps:merge(Style, #{bg => cyan, fg => black});
                true -> Style
            end,
            Header = [
                iso_ansi:move_to(Y + 1, CurX + 1),
                iso_ansi:style_to_ansi(TabStyle),
                <<" ">>, LabelBin, <<" ">>,
                iso_ansi:reset_style()
            ],
            {[Acc, Header], CurX + LabelLen + 3}
        end, {[], X}, Tabs),
    Headers.

%% Render table with base style (for dimmed background)
render_table_styled(#table{columns = Columns, rows = Rows, selected_row = SelectedRow,
                           scroll_offset = ScrollOffset, border = Border, show_header = ShowHeader,
                           style = Style, x = X, y = Y, width = W, height = H,
                           visible = Visible} = Table, Bounds, BaseStyle) ->
    case Visible of
        false -> [];
        true ->
            ActualX = Bounds#bounds.x + X,
            ActualY = Bounds#bounds.y + Y,
            Width = case W of auto -> Bounds#bounds.width - X; fill -> Bounds#bounds.width - X; _ -> W end,
            MergedStyle = maps:merge(Style, BaseStyle),
            BorderOffset = case Border of none -> 0; _ -> 1 end,
            HeaderOffset2 = case ShowHeader of true -> 2; false -> 0 end,
            Overhead = 2 * BorderOffset + HeaderOffset2,
            Height = case H of
                auto -> min(length(Rows) + Overhead, Bounds#bounds.height - Y);
                fill -> max(Overhead + 1, Bounds#bounds.height - Y);
                _ -> H
            end,
            VisibleHeight = Height - 2 * BorderOffset - HeaderOffset2,
            VisibleRows = lists:sublist(
                lists:nthtail(min(ScrollOffset, max(0, length(Rows) - 1)), Rows),
                max(0, VisibleHeight)),
            HeaderValues = iso_el_table:header_values(Table),
            ColWidths = calculate_column_widths(HeaderValues, Columns, VisibleRows,
                                                Width - 2 * BorderOffset),
            %% Header
            HeaderRow = case ShowHeader of
                true ->
                    HeaderText = render_table_row_text(
                        HeaderValues, ColWidths, Columns),
                    HeaderY = ActualY + BorderOffset + 1,
                    SepY = ActualY + BorderOffset + 2,
                    [
                        iso_ansi:move_to(HeaderY, ActualX + BorderOffset + 1),
                        iso_ansi:style_to_ansi(maps:merge(MergedStyle, #{bold => true})),
                        HeaderText,
                        iso_ansi:reset_style(),
                        iso_ansi:move_to(SepY, ActualX + BorderOffset + 1),
                        iso_ansi:style_to_ansi(MergedStyle),
                        iso_ansi:repeat_bin(<<"─"/utf8>>, Width - 2 * BorderOffset),
                        iso_ansi:reset_style()
                    ];
                false -> []
            end,
            DataRows = lists:map(
                fun({RowIdx, RowData}) ->
                    AbsRowIdx = ScrollOffset + RowIdx,
                    IsSelected = AbsRowIdx =:= SelectedRow,
                    RowStyle = if
                        IsSelected -> maps:merge(MergedStyle, #{bg => cyan, fg => black});
                        true -> MergedStyle
                    end,
                    RowText = render_table_row_text(RowData, ColWidths, Columns),
                    RowY = ActualY + BorderOffset + HeaderOffset2 + RowIdx,
                    [
                        iso_ansi:move_to(RowY, ActualX + BorderOffset + 1),
                        iso_ansi:style_to_ansi(RowStyle),
                        RowText,
                        iso_ansi:reset_style()
                    ]
                end,
                lists:zip(lists:seq(1, length(VisibleRows)), VisibleRows)),
            BorderOutput = case Border of
                none -> [];
                _ ->
                    {TL, TR, BL, BR, HZ, VT} = iso_ansi:border_chars(Border),
                    [
                        iso_ansi:style_to_ansi(MergedStyle),
                        iso_ansi:move_to(ActualY + 1, ActualX + 1),
                        TL, iso_ansi:repeat_bin(HZ, Width - 2), TR,
                        [[iso_ansi:move_to(ActualY + 1 + Row, ActualX + 1),
                          VT, lists:duplicate(Width - 2, $\s), VT]
                         || Row <- lists:seq(1, Height - 2)],
                        iso_ansi:move_to(ActualY + Height, ActualX + 1),
                        BL, iso_ansi:repeat_bin(HZ, Width - 2), BR,
                        iso_ansi:reset_style()
                    ]
            end,
            [BorderOutput, HeaderRow, DataRows]
    end.

%%====================================================================
%% Internal - Button Rendering
%%====================================================================

render_button(#button{label = Label, style = Style, x = X, y = Y, width = W}, Bounds, Focused, Hovered) ->
    ActualX = Bounds#bounds.x + X,
    ActualY = Bounds#bounds.y + Y,
    LabelBin = iolist_to_binary([Label]),
    LabelLen = string:length(unicode:characters_to_list(LabelBin)),
    Width = case W of
        auto -> LabelLen + button_padding_width();
        fill -> Bounds#bounds.width - X;
        _ -> W
    end,
    FocusStyle = button_state_style(Style, Focused, Hovered),
    Padding = max(0, Width - LabelLen),
    LeftPad = Padding div 2,
    RightPad = Padding - LeftPad,
    [
        iso_ansi:move_to(ActualY + 1, ActualX + 1),
        iso_ansi:style_to_ansi(FocusStyle),
        lists:duplicate(LeftPad, $\s), LabelBin, lists:duplicate(RightPad, $\s),
        iso_ansi:reset_style()
    ].

%%====================================================================
%% Internal - Input Rendering
%%====================================================================

%% Render input with cursor visibility control for blinking cursor support
render_input(Input, Bounds, Focused, CursorVisible) ->
    iso_el_input:render(Input, Bounds, #{focused => Focused, cursor_visible => CursorVisible}).

%%====================================================================
%% Internal - Modal Rendering (centered overlay)
%%====================================================================

render_modal(#modal{title = Title, children = Children, border = Border,
                    style = Style, width = W, height = H, visible = Visible},
             Bounds, FocusedId, Opts) ->
    case Visible of
        false -> [];
        true ->
            %% Calculate modal size
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
            %% Center the modal
            ModalX = (Bounds#bounds.width - Width) div 2,
            ModalY = (Bounds#bounds.height - Height) div 2,
            {TL, TR, BL, BR, HZ, VT} = iso_ansi:border_chars(Border),
            ChildBounds = #bounds{x = ModalX + 1, y = ModalY + 1,
                                  width = max(1, Width - 2), height = max(1, Height - 2)},
            %% Draw modal box (background dimming is handled by caller)
            ModalBox = [
                iso_ansi:reset_style(),  %% Reset any dim styling from background
                iso_ansi:style_to_ansi(Style),
                iso_ansi:move_to(ModalY + 1, ModalX + 1),
                TL, iso_ansi:render_title_line(Title, HZ, Width - 2), TR,
                [[iso_ansi:move_to(ModalY + 1 + Row, ModalX + 1),
                  VT, lists:duplicate(Width - 2, $\s), VT]
                 || Row <- lists:seq(1, Height - 2)],
                iso_ansi:move_to(ModalY + Height, ModalX + 1),
                BL, iso_ansi:repeat_bin(HZ, Width - 2), BR,
                iso_ansi:reset_style()
            ],
            %% Render children inside modal (pass Opts for cursor visibility)
            ChildOutput = render_children_two_level(Children, ChildBounds, undefined, FocusedId, Opts),
            [ModalBox, ChildOutput]
    end.

%%====================================================================
%% Internal - Table Rendering
%%====================================================================

calculate_column_widths(Headers, Columns, Rows, AvailableWidth) ->
    %% Calculate content widths in row-major order to avoid repeated nth scans.
    WidthSpecs = width_specs(Columns, Headers),
    ContentWidths0 = initial_content_widths(WidthSpecs),
    ContentWidths = lists:foldl(
        fun(Row, Widths) ->
            update_content_widths(Widths, WidthSpecs, Row)
        end,
        ContentWidths0,
        Rows),
    NumCols = length(ContentWidths),
    %% Distribute remaining space or truncate
    TotalWidth = lists:sum(ContentWidths) + NumCols - 1,  %% +separators
    if
        TotalWidth =< AvailableWidth -> ContentWidths;
        true ->
            %% Proportionally shrink columns
            Scale = AvailableWidth / max(1, TotalWidth),
            [max(3, round(W * Scale)) || W <- ContentWidths]
    end.

width_specs(Columns, Headers) ->
    width_specs(Columns, Headers, []).

width_specs([], _Headers, Acc) ->
    lists:reverse(Acc);
width_specs([Col | RestCols], [Header | RestHeaders], Acc) ->
    HeaderLen = string:length(to_string(Header)),
    width_specs(RestCols, RestHeaders, [{Col#table_col.width, HeaderLen} | Acc]);
width_specs([Col | RestCols], [], Acc) ->
    width_specs(RestCols, [], [{Col#table_col.width, 0} | Acc]).

initial_content_widths(WidthSpecs) ->
    [case Width of
         auto -> HeaderLen;
         W -> W
     end || {Width, HeaderLen} <- WidthSpecs].

update_content_widths(Widths, WidthSpecs, Row) ->
    lists:reverse(update_content_widths(Widths, WidthSpecs, Row, [])).

update_content_widths([], _Specs, _Row, Acc) ->
    Acc;
update_content_widths([Width | RestWidths], [{auto, _} | RestSpecs], [Cell | RestCells], Acc) ->
    CellWidth = string:length(to_string(Cell)),
    update_content_widths(RestWidths, RestSpecs, RestCells, [max(Width, CellWidth) | Acc]);
update_content_widths([Width | RestWidths], [{auto, _} | RestSpecs], [], Acc) ->
    update_content_widths(RestWidths, RestSpecs, [], [Width | Acc]);
update_content_widths([Width | RestWidths], [_Fixed | RestSpecs], [_Cell | RestCells], Acc) ->
    update_content_widths(RestWidths, RestSpecs, RestCells, [Width | Acc]);
update_content_widths([Width | RestWidths], [_Fixed | RestSpecs], [], Acc) ->
    update_content_widths(RestWidths, RestSpecs, [], [Width | Acc]).

render_table_row_text(RowData, ColWidths, Columns) ->
    Cells = render_table_cells(RowData, ColWidths, Columns, []),
    lists:join(<<" ">>, Cells).

render_table_cells(_RowData, [], _Columns, Acc) ->
    lists:reverse(Acc);
render_table_cells([Data | RestData], [Width | RestWidths], [Col | RestCols], Acc) ->
    Cell = format_cell(to_string(Data), Width, Col#table_col.align),
    render_table_cells(RestData, RestWidths, RestCols, [Cell | Acc]);
render_table_cells([], [Width | RestWidths], [Col | RestCols], Acc) ->
    Cell = format_cell(to_string(<<>>), Width, Col#table_col.align),
    render_table_cells([], RestWidths, RestCols, [Cell | Acc]);
render_table_cells([Data | RestData], [Width | RestWidths], [], Acc) ->
    Cell = format_cell(to_string(Data), Width, left),
    render_table_cells(RestData, RestWidths, [], [Cell | Acc]);
render_table_cells([], [Width | RestWidths], [], Acc) ->
    Cell = format_cell(to_string(<<>>), Width, left),
    render_table_cells([], RestWidths, [], [Cell | Acc]).

format_cell(Text, Width, Align) ->
    Len = string:length(Text),
    if
        Len >= Width -> string:slice(Text, 0, Width);
        true ->
            Padding = Width - Len,
            case Align of
                left -> [Text, lists:duplicate(Padding, $\s)];
                right -> [lists:duplicate(Padding, $\s), Text];
                center ->
                    Left = Padding div 2,
                    Right = Padding - Left,
                    [lists:duplicate(Left, $\s), Text, lists:duplicate(Right, $\s)]
            end
    end.

to_string(Bin) when is_binary(Bin) -> unicode:characters_to_list(Bin);
to_string(List) when is_list(List) -> List;
to_string(Atom) when is_atom(Atom) -> atom_to_list(Atom);
to_string(Int) when is_integer(Int) -> integer_to_list(Int);
to_string(Float) when is_float(Float) -> float_to_list(Float, [{decimals, 2}]);
to_string(Other) -> io_lib:format("~p", [Other]).

%%====================================================================
%% Internal - Tabs Rendering
%%====================================================================

%%====================================================================
%% Internal - Box Rendering
%%====================================================================

%% Render just the border of a box (used by box and tabs)


button_padding_width() ->
    4.

button_state_style(Style, true, _Hovered) ->
    maps:merge(Style, #{bold => true, underline => true});
button_state_style(Style, false, true) ->
    case maps:is_key(bg, Style) of
        true -> maps:merge(Style, #{bold => true, underline => true});
        false -> maps:merge(Style, #{bg => bright_black, bold => true})
    end;
button_state_style(Style, false, false) ->
    Style.
