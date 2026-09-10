%%%-------------------------------------------------------------------
%%% @doc NitUI Renderer
%%%
%%% Renders element trees to ANSI escape sequences.
%%% Each element is rendered within its calculated bounds.
%%% @end
%%%-------------------------------------------------------------------
-module(nit_render).

-include("nit_elements.hrl").

-export([render/2, render_dimmed/3]).
-export([render_two_level/4, render_two_level/5]).
-export([render_text_view/5]).

%%====================================================================
%% API
%%====================================================================

%% @doc Render an element tree to iolist within given bounds.
%% Dispatches to element modules via nit_element behaviour.
-spec render(tuple(), #bounds{}) -> iolist().
render(Element, Bounds) ->
    render_with_opts(Element, Bounds, #{}).

%% @doc Render an element with options (focused, base_style, etc.)
%% This is the main dispatch function to element modules.
-spec render_with_opts(tuple(), #bounds{}, map()) -> iolist().
render_with_opts(Element, Bounds, Opts) when is_tuple(Element) ->
    nit_element:render(Element, Bounds, Opts);
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
    render_two_level(Element, Bounds, FocusedContainer, FocusedChild, #{}).

%% @doc Render with two-level focus and additional options (e.g., cursor_visible).
-spec render_two_level(tuple(), #bounds{}, term(), term(), map()) -> iolist().
render_two_level(Element, Bounds, FocusedContainer, FocusedChild, Opts) ->
    Child = case nit_focus:text_view_target(Element, FocusedContainer, FocusedChild) of
        #text_view{id = Id} -> Id;
        _ -> FocusedChild
    end,
    render_two_level_impl(Element, Bounds, FocusedContainer, Child, Opts).

%% Redraw only an existing viewer's allocation. Ancestors provide layout and
%% scroll clipping, but unrelated virtual tables must not fetch new rows.
render_text_view(Tree, Bounds, Container, Child, Id) ->
    Focused = case nit_focus:text_view_target(Tree, Container, Child) of
        #text_view{id = Id} -> true;
        _ -> false
    end,
    render_text_view_only(Tree, Bounds, Bounds, Id, #{focused => Focused}).

render_text_view_only(Element, Bounds, Clip, Id, Opts) ->
    case lists:any(fun(#text_view{id = VId}) -> VId =:= Id end,
                   nit_focus:visible_text_views(Element)) of
        false -> [];
        true -> render_text_view_branch(Element, Bounds, Clip, Id, Opts)
    end.

render_text_view_branch(#text_view{} = View, Bounds, Clip, _Id, Opts) ->
    Resolved = nit_el_text_view:bounds(View, Bounds),
    case intersect_bounds(Resolved, Clip) of
        #bounds{width = W, height = H} when W =< 0; H =< 0 -> [];
        Resolved -> nit_el_text_view:render(View, Bounds, Opts);
        Visible -> render_clipped_text_view(View, Resolved, Visible, Opts)
    end;
render_text_view_branch(#scroll{} = Scroll, Bounds, Clip, Id, Opts) ->
    {Width, _Height} = nit_el_scroll:content_size(Scroll, Bounds),
    ChildClip = intersect_bounds(Clip, Bounds#bounds{width = Width}),
    [render_text_view_only(E, B, ChildClip, Id, Opts)
     || {E, B} <- nit_bounds:child_layout(Scroll, Bounds)];
render_text_view_branch(Element, Bounds, Clip, Id, Opts) ->
    [render_text_view_only(E, B, Clip, Id, Opts)
     || {E, B} <- nit_bounds:child_layout(Element, Bounds)].

%% Match the scroll renderer's cell-based clipping, but only paint this
%% viewer's intersection, never blank sibling allocations in the viewport.
render_clipped_text_view(View, #bounds{x = X, y = Y, width = W, height = H},
                         #bounds{x = CX, y = CY, width = CW, height = CH}, Opts) ->
    LocalView = View#text_view{x = 0, y = 0, width = W, height = H},
    Screen = nit_screen:from_ansi(nit_el_text_view:render(LocalView,
                                  #bounds{width = W, height = H}, Opts), W, H),
    [[begin
        {Char, Style} = nit_screen:get_cell(Screen, Col - X, Row - Y),
        [nit_ansi:move_to(Row, Col), nit_ansi:reset_style(),
         nit_ansi:style_to_ansi(Style), unicode:characters_to_binary([Char])]
      end || Col <- lists:seq(CX, CX + CW - 1)] || Row <- lists:seq(CY, CY + CH - 1)]
        ++ [nit_ansi:reset_style()].

%%====================================================================
%% Internal - Two-Level Focus Rendering
%% FocusedContainer: ID of container that has Tab focus (box/tabs)
%% FocusedChild: ID of element within container that has arrow focus
%% Opts: optional map with cursor_visible, etc.
%%====================================================================

%% All UI records share the visible field in ELEMENT_BASE.
render_two_level_impl(Element, _Bounds, _Container, _Child, _Opts)
  when element(#box.visible, Element) =:= false ->
    [];
render_two_level_impl(#panel{children = Children}, Bounds, Container, Child, Opts) ->
    render_children_two_level(Children, Bounds, Container, Child, Opts);
render_two_level_impl(#vbox{children = Children, spacing = Spacing, x = X, y = Y}, Bounds, Container, Child, Opts) ->
    StartBounds = Bounds#bounds{x = Bounds#bounds.x + X, y = Bounds#bounds.y + Y},
    %% Calculate heights with flex support for spacers (uses shared helper)
    ChildHeights = nit_layout:calculate_vbox_heights(Children, Bounds, Spacing, Y),
    {Output, _} = lists:foldl(
        fun({Elem, Height}, {Acc, CurrentY}) ->
            ElemBounds = StartBounds#bounds{y = CurrentY, height = Height},
            ElemOutput = render_two_level_impl(Elem, ElemBounds, Container, Child, Opts),
            {[Acc, ElemOutput], CurrentY + Height + Spacing}
        end, {[], StartBounds#bounds.y}, lists:zip(Children, ChildHeights)),
    Output;
render_two_level_impl(#hbox{children = Children, spacing = Spacing, x = X, y = Y}, Bounds, Container, Child, Opts) ->
    StartBounds = Bounds#bounds{x = Bounds#bounds.x + X, y = Bounds#bounds.y + Y},
    ChildWidths = nit_layout:calculate_hbox_widths(Children, Bounds, Spacing, X),
    {Output, _} = lists:foldl(
        fun({Elem, ElemWidth}, {Acc, CurrentX}) ->
            ElemBounds = StartBounds#bounds{x = CurrentX, width = ElemWidth},
            ElemOutput = render_two_level_impl(Elem, ElemBounds, Container, Child, Opts),
            {[Acc, ElemOutput], CurrentX + ElemWidth + Spacing}
        end, {[], StartBounds#bounds.x}, lists:zip(Children, ChildWidths)),
    Output;
render_two_level_impl(#box{border = none, children = Children} = Box,
                     Bounds, Container, Child, Opts) ->
    ChildBounds = borderless_child_bounds(Box, Bounds),
    render_children_two_level(Children, ChildBounds, Container, Child, Opts);
render_two_level_impl(#box{id = Id, children = Children, border = Border, title = Title,
                           style = Style, x = X, y = Y, width = W, height = H,
                           focus_within = FocusWithin, focused_border = FocusedBorder,
                           focused_style = FocusedStyle}, Bounds, Container, Child, Opts) ->
    ActualX = Bounds#bounds.x + X,
    ActualY = Bounds#bounds.y + Y,
    Width = case W of auto -> Bounds#bounds.width - X; fill -> Bounds#bounds.width - X; _ -> W end,
    Height = case H of auto -> Bounds#bounds.height - Y; fill -> Bounds#bounds.height - Y; _ -> H end,
    ChildBounds = #bounds{x = ActualX + 1, y = ActualY + 1,
                          width = max(0, Width - 2), height = max(0, Height - 2)},
    %% Focus-within is visual only: it does not make this box a Tab stop.
    IsContainerFocused = focus_matches(Id, Container) orelse
        (FocusWithin andalso lists:any(fun(Elem) ->
            visible_focus(Elem, ChildBounds, ChildBounds, Container, Child)
        end, Children)),
    DisplayBorder = case IsContainerFocused andalso FocusedBorder =/= undefined of
        true -> FocusedBorder;
        false -> Border
    end,
    {TL, TR, BL, BR, HZ, VT} = nit_ansi:border_chars(DisplayBorder),
    BorderStyle = case IsContainerFocused of
        true -> maps:merge(Style, FocusedStyle);
        false -> Style
    end,
    [
        nit_ansi:style_to_ansi(BorderStyle),
        nit_ansi:move_to(ActualY, ActualX),
        TL, nit_ansi:render_title_line(Title, HZ, Width - 2), TR,
        [[nit_ansi:move_to(ActualY + Row, ActualX),
          VT, lists:duplicate(Width - 2, $\s), VT]
         || Row <- lists:seq(1, Height - 2)],
        nit_ansi:move_to(ActualY + Height - 1, ActualX),
        BL, nit_ansi:repeat_bin(HZ, Width - 2), BR,
        nit_ansi:reset_style(),
        render_children_two_level(Children, ChildBounds, Container, Child, Opts)
    ];
render_two_level_impl(#button{id = Id} = Button, Bounds, _Container, Child, Opts) ->
    HoveredId = maps:get(hovered_id, Opts, undefined),
    render_button(Button, Bounds, focus_matches(Id, Child), focus_matches(Id, HoveredId));
render_two_level_impl(#input{id = Id} = Input, Bounds, _Container, Child, Opts) ->
    CursorVisible = maps:get(cursor_visible, Opts, true),
    render_input(Input, Bounds, focus_matches(Id, Child), CursorVisible);
render_two_level_impl(#table{id = Id} = Table, Bounds, Container, Child, Opts) ->
    %% Use nit_el_table:render which supports row_provider for virtual scrolling
    Focused = focus_matches(Id, Container) orelse focus_matches(Id, Child),
    nit_el_table:render(Table, Bounds, Opts#{focused => Focused});
render_two_level_impl(#text_view{id = Id} = View, Bounds, Container, Child, Opts) ->
    Focused = focus_matches(Id, Container) orelse focus_matches(Id, Child),
    nit_el_text_view:render(View, Bounds, Opts#{focused => Focused});
render_two_level_impl(#tabs{} = Tabs, Bounds, Container, Child, Opts) ->
    render_tabs_two_level(Tabs, Bounds, Container, Child, Opts);
render_two_level_impl(#tree{id = Id} = Tree, Bounds, Container, Child, Opts) ->
    %% Tree is a container - pass focus info to element renderer
    Focused = focus_matches(Id, Container) orelse focus_matches(Id, Child),
    render_with_opts(Tree, Bounds, Opts#{focused => Focused});
render_two_level_impl(#modal{} = Modal, Bounds, _Container, Child, Opts) ->
    render_modal(Modal, Bounds, Child, Opts);
render_two_level_impl(#scroll{} = Scroll, Bounds, Container, Child, Opts) ->
    %% The viewport owns clipping/layout; its child renderer retains focus IDs
    %% rather than applying a single focused flag to the whole subtree.
    RenderChild = fun(Element, ChildBounds, _ChildOpts) ->
        render_two_level_impl(Element, ChildBounds, Container, Child, Opts)
    end,
    nit_el_scroll:render(Scroll, Bounds, Opts#{render_child => RenderChild});
render_two_level_impl(Element, Bounds, _Container, _Child, _Opts) ->
    render(Element, Bounds).

render_children_two_level(Children, Bounds, Container, Child, Opts) ->
    [render_two_level_impl(C, Bounds, Container, Child, Opts) || C <- Children].

focus_matches(undefined, _FocusedId) -> false;
focus_matches(Id, FocusedId) -> Id =:= FocusedId.

%% Search only the rendered subtree, including visible ancestors and the active
%% tab. Keep this separate from navigation so focus visuals add no Tab stops.
visible_focus(_Element, _Bounds, _Clip, undefined, undefined) -> false;
visible_focus(Element, _Bounds, _Clip, _Container, _Child)
  when element(#box.visible, Element) =:= false -> false;
visible_focus(Element, Bounds, Clip, Container, Child)
  when is_tuple(Element), tuple_size(Element) >= #box.on_unmount ->
    Region = focus_region(Element, Bounds),
    case intersect_bounds(Region, Clip) of
        #bounds{width = W, height = H} when W =< 0; H =< 0 -> false;
        _ ->
            Id = element(#box.id, Element),
            focus_matches(Id, Container) orelse focus_matches(Id, Child) orelse
                visible_focus_children(Element, Bounds, Clip, Container, Child)
    end;
visible_focus(_, _, _, _, _) -> false.

focus_region(#scroll{}, Bounds) -> Bounds;
focus_region(#text_view{} = View, Bounds) -> nit_el_text_view:bounds(View, Bounds);
focus_region(Element, Bounds) ->
    X = element(#box.x, Element),
    Y = element(#box.y, Element),
    Bounds#bounds{x = Bounds#bounds.x + X, y = Bounds#bounds.y + Y,
        width = nit_ansi:resolve_size(element(#box.width, Element), Bounds#bounds.width - X),
        height = nit_ansi:resolve_size(element(#box.height, Element), Bounds#bounds.height - Y)}.

visible_focus_children(#box{border = none} = Box, Bounds, Clip, Container, Child) ->
    ChildBounds = borderless_child_bounds(Box, Bounds),
    visible_focus_children_at(Box, ChildBounds, Clip, Container, Child);
visible_focus_children(#box{} = Box, Bounds, Clip, Container, Child) ->
    Region = focus_region(Box, Bounds),
    ChildBounds = Region#bounds{x = Region#bounds.x + 1, y = Region#bounds.y + 1,
        width = max(0, Region#bounds.width - 2), height = max(0, Region#bounds.height - 2)},
    visible_focus_children_at(Box, ChildBounds, Clip, Container, Child);
visible_focus_children(#tabs{x = X, y = Y, width = W, height = H} = Tabs,
                       Bounds, Clip, Container, Child) ->
    Width = tabs_size(W, Bounds#bounds.width - X),
    Height = tabs_size(H, Bounds#bounds.height - Y),
    ChildBounds = #bounds{x = Bounds#bounds.x + X + 1, y = Bounds#bounds.y + Y + 2,
        width = max(0, Width - 2), height = max(1, Height - 3)},
    Width > 2 andalso Height >= 3 andalso
        visible_focus_children_at(Tabs, ChildBounds, Clip, Container, Child);
visible_focus_children(#vbox{children = Children, spacing = Spacing, x = X, y = Y},
                       Bounds, Clip, Container, Child) ->
    Heights = nit_layout:calculate_vbox_heights(Children, Bounds, Spacing, Y),
    Start = Bounds#bounds{x = Bounds#bounds.x + X, y = Bounds#bounds.y + Y},
    visible_focus_stack(Children, Heights, Start, Spacing, vertical, Clip, Container, Child);
visible_focus_children(#hbox{children = Children, spacing = Spacing, x = X, y = Y},
                       Bounds, Clip, Container, Child) ->
    Widths = nit_layout:calculate_hbox_widths(Children, Bounds, Spacing, X),
    Start = Bounds#bounds{x = Bounds#bounds.x + X, y = Bounds#bounds.y + Y},
    visible_focus_stack(Children, Widths, Start, Spacing, horizontal, Clip, Container, Child);
visible_focus_children(#scroll{children = Children, offset = Offset} = Scroll,
                       Bounds, Clip, Container, Child) ->
    ViewHeight = max(1, Bounds#bounds.height),
    {Width, TotalHeight} = nit_el_scroll:content_size(Scroll, Bounds),
    SafeOffset = min(max(0, Offset), max(0, TotalHeight - ViewHeight)),
    LayoutBounds = #bounds{width = Width, height = max(ViewHeight, TotalHeight)},
    Heights = nit_layout:calculate_vbox_heights(Children, LayoutBounds, 0),
    Start = LayoutBounds#bounds{x = Bounds#bounds.x, y = Bounds#bounds.y - SafeOffset},
    visible_focus_stack(Children, Heights, Start, 0, vertical,
                        intersect_bounds(Bounds, Clip), Container, Child);
visible_focus_children(Element, Bounds, Clip, Container, Child) ->
    visible_focus_children_at(Element, Bounds, Clip, Container, Child).

visible_focus_children_at(Element, Bounds, Clip, Container, Child) ->
    lists:any(fun(Elem) -> visible_focus(Elem, Bounds, Clip, Container, Child) end,
              nit_element:children(Element)).

visible_focus_stack([], [], _Bounds, _Spacing, _Axis, _Clip, _Container, _Child) -> false;
visible_focus_stack([Elem | Rest], [Size | Sizes], Bounds, Spacing, Axis, Clip, Container, Child) ->
    {ChildBounds, NextBounds} = case Axis of
        vertical -> {Bounds#bounds{height = Size}, Bounds#bounds{y = Bounds#bounds.y + Size + Spacing}};
        horizontal -> {Bounds#bounds{width = Size}, Bounds#bounds{x = Bounds#bounds.x + Size + Spacing}}
    end,
    visible_focus(Elem, ChildBounds, Clip, Container, Child) orelse
        visible_focus_stack(Rest, Sizes, NextBounds, Spacing, Axis, Clip, Container, Child).

intersect_bounds(A, B) ->
    X = max(A#bounds.x, B#bounds.x),
    Y = max(A#bounds.y, B#bounds.y),
    #bounds{x = X, y = Y,
        width = max(0, min(A#bounds.x + A#bounds.width, B#bounds.x + B#bounds.width) - X),
        height = max(0, min(A#bounds.y + A#bounds.height, B#bounds.y + B#bounds.height) - Y)}.

%% Tabs with two-level focus
render_tabs_two_level(#tabs{id = Id, tabs = TabList, active_tab = ActiveTab0,
                            style = Style, x = X, y = Y, width = W, height = H},
                      Bounds, Container, FocusedChild, Opts) ->
    IsContainerFocused = focus_matches(Id, Container),
    ActualX = Bounds#bounds.x + X,
    ActualY = Bounds#bounds.y + Y,
    Width = tabs_size(W, Bounds#bounds.width - X),
    Height = tabs_size(H, Bounds#bounds.height - Y),
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
    Border = render_tabs_border(ActualX, ActualY, Width, Height, BorderStyle),
    %% Tab headers with focus indicator (inside the top border)
    TabHeaders = case Width > 1 andalso Height > 0 of
        true -> render_tab_headers_two_level(TabList, ActiveTab, FocusedChild,
                    ActualX + 1, ActualY, Style, IsContainerFocused,
                    ActualX + Width);
        false -> []
    end,
    %% Active tab content (inside the border, below tab bar which is on row 1)
    ContentBounds = #bounds{x = ActualX + 1, y = ActualY + 2,
                            width = max(0, Width - 2), height = max(1, Height - 3)},
    ActiveContent = case lists:keyfind(ActiveTab, #tab.id, TabList) of
        #tab{content = Content} -> Content;
        false -> []
    end,
    %% Heights 1/2 are header-only bars: never render children outside them.
    ContentOutput = case Width > 2 andalso Height >= 3 of
        true -> [render_two_level_impl(C, ContentBounds, Container, FocusedChild, Opts) || C <- ActiveContent];
        false -> []
    end,
    [Border, TabHeaders, ContentOutput].

render_tab_headers_two_level(Tabs, ActiveTab, FocusedChild, X, Y, Style, IsContainerFocused, RightEdge) ->
    {Headers, _} = lists:foldl(
        fun(#tab{id = Id, label = Label}, {Acc, CurX}) ->
            IsActive = Id =:= ActiveTab,
            IsFocused = focus_matches(Id, FocusedChild) andalso IsContainerFocused,
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
            Header = render_tab_header(LabelBin, CurX, Y, TabStyle, RightEdge),
            {[Acc, Header], CurX + LabelLen + 1}
        end, {[], X}, Tabs),
    Headers.

%% Clamp exhausted/invalid bounds without changing the normal tab layout.
tabs_size(Size, Available) ->
    max(0, min(nit_ansi:resolve_size(Size, Available), Available)).

render_tabs_border(X, Y, Width, Height, Style) when Width >= 2, Height >= 3 ->
    nit_ansi:render_box_border(X, Y, Width, Height, Style, undefined, single);
render_tabs_border(_X, _Y, _Width, _Height, _Style) ->
    [].

render_tab_header(Label, X, Y, Style, RightEdge) ->
    VisibleLabel = nit_ansi:truncate_content(Label, RightEdge - X),
    case VisibleLabel of
        <<>> -> [];
        _ -> [nit_ansi:move_to(Y, X), nit_ansi:style_to_ansi(Style),
              VisibleLabel, nit_ansi:reset_style()]
    end.

%%====================================================================
%% Internal - Styled Rendering (with base style modifier for dimming)
%%====================================================================

render_focused_styled(Element, _Bounds, _FocusedId, _BaseStyle)
  when element(#box.visible, Element) =:= false ->
    [];
render_focused_styled(#panel{children = Children}, Bounds, FocusedId, BaseStyle) ->
    render_children_styled(Children, Bounds, FocusedId, BaseStyle);
render_focused_styled(#vbox{children = Children, spacing = Spacing, x = X, y = Y}, Bounds, FocusedId, BaseStyle) ->
    StartBounds = Bounds#bounds{x = Bounds#bounds.x + X, y = Bounds#bounds.y + Y},
    %% Calculate heights with flex support for spacers (uses shared helper)
    ChildHeights = nit_layout:calculate_vbox_heights(Children, Bounds, Spacing, Y),
    {Output, _} = lists:foldl(
        fun({Child, Height}, {Acc, CurrentY}) ->
            ChildBounds = StartBounds#bounds{y = CurrentY, height = Height},
            ChildOutput = render_focused_styled(Child, ChildBounds, FocusedId, BaseStyle),
            {[Acc, ChildOutput], CurrentY + Height + Spacing}
        end, {[], StartBounds#bounds.y}, lists:zip(Children, ChildHeights)),
    Output;
render_focused_styled(#hbox{children = Children, spacing = Spacing, x = X, y = Y}, Bounds, FocusedId, BaseStyle) ->
    StartBounds = Bounds#bounds{x = Bounds#bounds.x + X, y = Bounds#bounds.y + Y},
    ChildWidths = nit_layout:calculate_hbox_widths(Children, Bounds, Spacing, X),
    {Output, _} = lists:foldl(
        fun({Child, ChildWidth}, {Acc, CurrentX}) ->
            ChildBounds = StartBounds#bounds{x = CurrentX, width = ChildWidth},
            ChildOutput = render_focused_styled(Child, ChildBounds, FocusedId, BaseStyle),
            {[Acc, ChildOutput], CurrentX + ChildWidth + Spacing}
        end, {[], StartBounds#bounds.x}, lists:zip(Children, ChildWidths)),
    Output;
render_focused_styled(#box{border = none, children = Children} = Box,
                     Bounds, FocusedId, BaseStyle) ->
    ChildBounds = borderless_child_bounds(Box, Bounds),
    render_children_styled(Children, ChildBounds, FocusedId, BaseStyle);
render_focused_styled(#box{border = Border, title = Title, children = Children,
                    style = Style, x = X, y = Y, width = W, height = H}, Bounds, FocusedId, BaseStyle) ->
    ActualX = Bounds#bounds.x + X,
    ActualY = Bounds#bounds.y + Y,
    Width = nit_ansi:resolve_size(W, Bounds#bounds.width - X),
    Height = nit_ansi:resolve_size(H, Bounds#bounds.height - Y),
    {TL, TR, BL, BR, HZ, VT} = nit_ansi:border_chars(Border),
    ChildBounds = #bounds{x = ActualX + 1, y = ActualY + 1,
                          width = max(1, Width - 2), height = max(1, Height - 2)},
    MergedStyle = maps:merge(Style, BaseStyle),
    [
        nit_ansi:style_to_ansi(MergedStyle),
        nit_ansi:move_to(ActualY, ActualX),
        TL, nit_ansi:render_title_line(Title, HZ, Width - 2), TR,
        [[nit_ansi:move_to(ActualY + Row, ActualX),
          VT, lists:duplicate(Width - 2, $\s), VT]
         || Row <- lists:seq(1, Height - 2)],
        nit_ansi:move_to(ActualY + Height - 1, ActualX),
        BL, nit_ansi:repeat_bin(HZ, Width - 2), BR,
        nit_ansi:reset_style(),
        render_children_styled(Children, ChildBounds, FocusedId, BaseStyle)
    ];
render_focused_styled(#text{} = Text, Bounds, _FocusedId, BaseStyle) ->
    nit_el_text:render(Text, Bounds, #{base_style => BaseStyle});
render_focused_styled(#button{id = Id} = Button, Bounds, FocusedId, BaseStyle) ->
    render_button_styled(Button, Bounds, focus_matches(Id, FocusedId), BaseStyle);
render_focused_styled(#input{id = Id} = Input, Bounds, FocusedId, BaseStyle) ->
    render_input_styled(Input, Bounds, Id =:= FocusedId, BaseStyle);
render_focused_styled(#tabs{} = Tabs, Bounds, FocusedId, BaseStyle) ->
    render_tabs_styled(Tabs, Bounds, FocusedId, BaseStyle);
render_focused_styled(#table{} = Table, Bounds, _FocusedId, BaseStyle) ->
    render_table_styled(Table, Bounds, BaseStyle);
render_focused_styled(#scroll{} = Scroll, Bounds, FocusedId, BaseStyle) ->
    %% Keep the focused ID through direct and clipped child rendering.
    RenderChild = fun(Element, ChildBounds, _ChildOpts) ->
        render_focused_styled(Element, ChildBounds, FocusedId, BaseStyle)
    end,
    render_with_opts(Scroll, Bounds, #{base_style => BaseStyle, render_child => RenderChild});
render_focused_styled(Element, Bounds, FocusedId, BaseStyle) ->
    Focused = is_tuple(Element) andalso tuple_size(Element) >= #box.on_unmount andalso
        focus_matches(element(#box.id, Element), FocusedId),
    render_with_opts(Element, Bounds, #{base_style => BaseStyle, focused => Focused}).

render_children_styled(Children, Bounds, FocusedId, BaseStyle) ->
    [render_focused_styled(Child, Bounds, FocusedId, BaseStyle) || Child <- Children].

borderless_child_bounds(#box{x = X, y = Y} = Box, Bounds) ->
    case nit_focus:visible_text_views(Box) of
        [] -> Bounds#bounds{x = Bounds#bounds.x + X, y = Bounds#bounds.y + Y};
        _ ->
            %% Viewer layout must agree with hit testing and resolved input
            %% bounds. Leave legacy borderless layouts without viewers alone.
            [{_, ChildBounds} | _] = nit_bounds:child_layout(Box, Bounds),
            ChildBounds
    end.

render_button_styled(Button, Bounds, Focused, BaseStyle) ->
    nit_el_button:render(Button, Bounds, #{focused => Focused, base_style => BaseStyle}).

render_input_styled(Input, Bounds, Focused, BaseStyle) ->
    nit_el_input:render(Input, Bounds, #{focused => Focused, base_style => BaseStyle}).

%% Render tabs with base style (for dimmed background)
render_tabs_styled(#tabs{tabs = TabList, active_tab = ActiveTab0,
                         style = Style, x = X, y = Y, width = W, height = H},
                   Bounds, _FocusedId, BaseStyle) ->
    ActualX = Bounds#bounds.x + X,
    ActualY = Bounds#bounds.y + Y,
    Width = tabs_size(W, Bounds#bounds.width - X),
    Height = tabs_size(H, Bounds#bounds.height - Y),
    ActiveTab = case ActiveTab0 of
        undefined -> case TabList of [#tab{id = First}|_] -> First; [] -> undefined end;
        _ -> ActiveTab0
    end,
    MergedStyle = maps:merge(Style, BaseStyle),
    %% Draw border
    Border = render_tabs_border(ActualX, ActualY, Width, Height, MergedStyle),
    %% Tab headers
    TabHeaders = case Width > 1 andalso Height > 0 of
        true -> render_tab_headers_styled(TabList, ActiveTab, ActualX + 1, ActualY,
                    MergedStyle, ActualX + Width);
        false -> []
    end,
    %% Content
    ContentBounds = #bounds{x = ActualX + 1, y = ActualY + 2,
                            width = max(0, Width - 2), height = max(1, Height - 3)},
    ActiveContent = case lists:keyfind(ActiveTab, #tab.id, TabList) of
        #tab{content = Content} -> Content;
        false -> []
    end,
    ContentOutput = case Width > 2 andalso Height >= 3 of
        true -> render_children_styled(ActiveContent, ContentBounds, undefined, BaseStyle);
        false -> []
    end,
    [Border, TabHeaders, ContentOutput].

render_tab_headers_styled(Tabs, ActiveTab, X, Y, Style, RightEdge) ->
    {Headers, _} = lists:foldl(
        fun(#tab{id = Id, label = Label}, {Acc, CurX}) ->
            LabelBin = iolist_to_binary([Label]),
            LabelLen = byte_size(LabelBin),
            TabStyle = if
                Id =:= ActiveTab -> maps:merge(Style, #{bg => cyan, fg => black});
                true -> Style
            end,
            Header = render_tab_header(iolist_to_binary([<<" ">>, LabelBin, <<" ">>]),
                                       CurX, Y, TabStyle, RightEdge),
            {[Acc, Header], CurX + LabelLen + 3}
        end, {[], X}, Tabs),
    Headers.

%% Render table with base style (for dimmed background)
render_table_styled(#table{} = Table, Bounds, BaseStyle) ->
    nit_el_table:render(Table, Bounds, #{base_style => BaseStyle}).

%%====================================================================
%% Internal - Button Rendering
%%====================================================================

render_button(Button, Bounds, Focused, Hovered) ->
    nit_el_button:render(Button, Bounds, #{focused => Focused, hovered => Hovered}).

%%====================================================================
%% Internal - Input Rendering
%%====================================================================

%% Render input with cursor visibility control for blinking cursor support
render_input(Input, Bounds, Focused, CursorVisible) ->
    nit_el_input:render(Input, Bounds, #{focused => Focused, cursor_visible => CursorVisible}).

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
            {TL, TR, BL, BR, HZ, VT} = nit_ansi:border_chars(Border),
            ChildBounds = #bounds{x = ModalX + 1, y = ModalY + 1,
                                  width = max(1, Width - 2), height = max(1, Height - 2)},
            %% Draw modal box (background dimming is handled by caller)
            ModalBox = [
                nit_ansi:reset_style(),  %% Reset any dim styling from background
                nit_ansi:style_to_ansi(Style),
                nit_ansi:move_to(ModalY, ModalX),
                TL, nit_ansi:render_title_line(Title, HZ, Width - 2), TR,
                [[nit_ansi:move_to(ModalY + Row, ModalX),
                  VT, lists:duplicate(Width - 2, $\s), VT]
                 || Row <- lists:seq(1, Height - 2)],
                nit_ansi:move_to(ModalY + Height - 1, ModalX),
                BL, nit_ansi:repeat_bin(HZ, Width - 2), BR,
                nit_ansi:reset_style()
            ],
            %% Render children inside modal (pass Opts for cursor visibility)
            ChildOutput = render_children_two_level(Children, ChildBounds, undefined, FocusedId, Opts),
            [ModalBox, ChildOutput]
    end.