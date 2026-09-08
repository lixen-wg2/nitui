%%% Opt-in focus visuals must not affect navigation, geometry or sibling styles.
-module(nit_focus_visuals_tests).

-include_lib("eunit/include/eunit.hrl").
-include("nit_elements.hrl").

record_defaults_test() ->
    Box = #box{},
    ?assertEqual(false, Box#box.focus_within),
    ?assertEqual(undefined, Box#box.focused_border),
    ?assertEqual(#{fg => yellow, bold => true}, Box#box.focused_style),
    Table = #table{},
    ?assertEqual(#{bg => cyan, fg => black}, Table#table.selected_style),
    ?assertEqual(#{bg => white, fg => black, bold => true}, Table#table.focused_selected_style),
    Tree = #tree{},
    ?assertEqual(#{bg => white, fg => black}, Tree#tree.selected_style),
    ?assertEqual(Tree#tree.selected_style, Tree#tree.focused_selected_style),
    ?assertEqual(false, Tree#tree.full_row_selection),
    ?assertEqual(#{bold => true, underline => true}, (#button{})#button.focused_style).

default_box_focus_is_direct_only_test() ->
    Box = (pane(tree()))#box{focus_within = false, focused_border = undefined,
                            focused_style = #{fg => yellow, bold => true}},
    ?assertEqual({$┌, #{fg => blue}}, corner(Box, tree, undefined)),
    ?assertEqual({$┌, #{fg => yellow, bold => true}}, corner(Box, pane, undefined)),
    ?assertEqual({$┌, #{fg => blue}}, corner(Box#box{id = undefined}, undefined, undefined)),
    ?assertEqual({$┌, #{fg => blue}}, corner(Box, undefined, undefined)).

nested_focus_within_test_() ->
    Widgets = [tree(), table(),
        #scroll{id = scroll, focusable = true, height = 4,
                children = [#text{content = <<"Log">>}]}],
    [?_test(begin
        Id = element(#box.id, Widget),
        Nested = #panel{children = [#vbox{children = [
            #hbox{height = 4, children = [Widget]}]}]},
        Box = pane(Nested),
        ?assertEqual([Id], nit_focus:collect_containers(Box)),
        ?assertEqual(Id, nit_focus:next_focus(nit_focus:collect_containers(Box), undefined)),
        ?assertEqual({$╔, focus_style()}, corner(Box, Id, undefined)),
        ?assertEqual({$╔, focus_style()}, corner(Box, other, Id)),
        ?assertEqual({$┌, #{fg => blue}}, corner(Box, other, undefined))
    end) || Widget <- Widgets].

unframed_settings_focus_and_geometry_test() ->
    Button = #button{id = action, focusable = true, label = <<"Apply">>, width = 10,
                     focused_style = #{bg => black, fg => cyan}},
    Settings = #box{id = settings, focusable = true, border = none,
        focused_border = double, focus_within = true,
        children = [#vbox{children = [Button, #text{content = <<"Help">>}]}]},
    Box = pane(Settings),
    ?assertEqual([settings], nit_focus:collect_containers(Box)),
    ?assertEqual([action], nit_focus:collect_children(Box, settings)),
    ?assertEqual({$╔, focus_style()}, corner(Box, settings, action)),
    Plain = render(Box#box{focus_within = false}, settings, action),
    Focused = render(Box, settings, action),
    ?assertEqual(cursor_positions(Plain), cursor_positions(Focused)),
    ?assertEqual(nit_bounds:find_element_bounds(Box, action, bounds()),
                 nit_bounds:find_element_bounds(Box#box{focus_within = false}, action, bounds())),
    Screen = screen(Focused),
    ?assertEqual(#{bg => black, fg => cyan}, cell_style(Screen, 1, 1)),
    ?assertEqual({$H, #{}}, nit_screen:get_cell(Screen, 1, 2)),
    %% Even direct focus must not create a border or inset on an unframed box.
    ?assertEqual(iolist_to_binary(nit_render:render_two_level(Settings, bounds(), settings, action)),
        iolist_to_binary(nit_render:render_two_level(
            Settings#box{focused_border = undefined, focus_within = false}, bounds(), settings, action))).

border_glyphs_do_not_change_geometry_test_() ->
    [?_test(begin
        Box = (pane(tree()))#box{focused_border = Border},
        Normal = render(Box, other, undefined),
        Focused = render(Box, tree, undefined),
        ?assertEqual(cursor_positions(Normal), cursor_positions(Focused)),
        ?assertEqual({Corner, focus_style()}, nit_screen:get_cell(screen(Focused), 0, 0)),
        ?assertEqual(cell_chars(screen(Normal), 1, 1, 22, 8), cell_chars(screen(Focused), 1, 1, 22, 8)),
        ?assertEqual(nit_element:height(Box, bounds()),
                     nit_element:height(Box#box{focused_border = undefined}, bounds())),
        ?assertEqual(nit_element:width(Box, bounds()),
                     nit_element:width(Box#box{focused_border = undefined}, bounds()))
    end) || {Border, Corner} <- [{undefined, $┌}, {single, $┌}, {double, $╔}, {rounded, $╭}]].

focus_does_not_leak_into_sibling_pane_test() ->
    Left = (pane(table()))#box{width = 24},
    RightTable = (table())#table{id = right_table},
    Right = (pane(RightTable))#box{id = right, width = 24},
    UI = #hbox{spacing = 1, children = [Left, Right]},
    Screen = nit_screen:from_ansi(nit_render:render_two_level(
        UI, #bounds{width = 49, height = 10}, table, undefined), 49, 10),
    ?assertEqual({$╔, focus_style()}, nit_screen:get_cell(Screen, 0, 0)),
    ?assertEqual({$┌, #{fg => blue}}, nit_screen:get_cell(Screen, 25, 0)),
    ?assertEqual(#{bg => white, fg => black, bold => true}, cell_style(Screen, 1, 3)),
    ?assertEqual(#{bg => cyan, fg => black}, cell_style(Screen, 26, 3)),
    ?assertEqual(#{fg => green, bold => true}, cell_style(Screen, 1, 1)),
    ?assertEqual(#{fg => green}, cell_style(Screen, 1, 4)).

undefined_and_missing_focus_test_() ->
    [?_test(?assertEqual({$┌, #{fg => blue}}, corner(pane(tree()), Container, Child)))
     || {Container, Child} <- [{undefined, undefined}, {missing, undefined},
                               {undefined, missing}, {missing, missing}]].

hidden_focus_subtrees_test_() ->
    Hidden = [(tree())#tree{visible = false}, (table())#table{visible = false},
        #panel{visible = false, children = [tree()]},
        #vbox{visible = false, children = [tree()]},
        #hbox{visible = false, children = [tree()]},
        #box{visible = false, border = none, children = [tree()]},
        #box{visible = false, border = single, children = [tree()]},
        #scroll{visible = false, children = [tree()]},
        #tabs{visible = false, tabs = [#tab{id = one, content = [tree()]}]}],
    [?_test(begin
        Box = pane(Element),
        ?assertEqual({$┌, #{fg => blue}}, corner(Box, tree, table)),
        ?assertEqual(<<>>, iolist_to_binary(nit_render:render_two_level(Element, bounds(), tree, table)))
    end) || Element <- Hidden].

hidden_direct_container_test() ->
    ?assertEqual(<<>>, iolist_to_binary(render((pane(tree()))#box{visible = false}, pane, tree))).

active_tabs_only_test() ->
    Tabs = #tabs{id = tabs, height = 6, tabs = [
        #tab{id = first, label = <<"First">>, content = [tree()]},
        #tab{id = second, label = <<"Second">>, content = [table()]}]},
    ?assertEqual({$╔, focus_style()}, corner(pane(Tabs), tree, undefined)),
    ?assertEqual({$┌, #{fg => blue}}, corner(pane(Tabs), table, undefined)),
    ?assertEqual({$┌, #{fg => blue}}, corner(pane(Tabs), other, table)),
    Switched = pane(Tabs#tabs{active_tab = second}),
    ?assertEqual({$╔, focus_style()}, corner(Switched, table, undefined)),
    ?assertEqual({$┌, #{fg => blue}}, corner(Switched, tree, undefined)),
    ?assertEqual({$┌, #{fg => blue}}, corner(pane(Tabs#tabs{active_tab = missing}), tree, undefined)),
    %% A frame inside active content also sees the real focus, not undefined IDs.
    Inner = (pane(tree()))#box{id = inner, width = 18, height = 4},
    NestedTabs = Tabs#tabs{tabs = [#tab{id = first, content = [Inner]}]},
    ?assertEqual({$╔, focus_style()}, nit_screen:get_cell(screen(render(pane(NestedTabs), tree, undefined)), 2, 3)).

compact_tabs_do_not_expose_content_focus_test_() ->
    [?_test(begin
        Tabs = #tabs{id = tabs, height = Height, width = Width,
                     tabs = [#tab{id = first, label = <<"First">>, content = [tree()]}]},
        ?assertEqual({$┌, #{fg => blue}}, corner(pane(Tabs), tree, undefined))
    end) || {Height, Width} <- [{1, auto}, {2, auto}, {6, 2}]].

scroll_focus_ignores_offscreen_children_test() ->
    Scroll = #scroll{id = scroll, offset = 1, show_scrollbar = false, children = [
        #button{id = offscreen, label = <<"Off">>},
        #button{id = onscreen, label = <<"On">>}, #text{content = <<"End">>}]},
    Box = (pane(Scroll))#box{height = 4},
    ?assertEqual({$┌, #{fg => blue}}, corner(Box, other, offscreen)),
    ?assertEqual({$╔, focus_style()}, corner(Box, other, onscreen)),
    ?assertEqual({$╔, focus_style()}, corner(Box, scroll, undefined)),
    ?assertEqual({$╔, focus_style()}, corner(
        Box#box{children = [Scroll#scroll{offset = 0}]}, other, offscreen)).

table_default_selection_styles_test() ->
    lists:foreach(fun({Focused, Expected}) ->
        Screen = screen(nit_el_table:render(table(), bounds(), #{focused => Focused})),
        ?assertEqual(Expected, cell_style(Screen, 0, 2)),
        ?assertEqual(Expected, cell_style(Screen, 11, 2)),
        ?assertEqual(#{fg => green, bold => true}, cell_style(Screen, 0, 0)),
        ?assertEqual(#{fg => green}, cell_style(Screen, 0, 3)),
        ?assertEqual(#{fg => green}, cell_style(Screen, 0, 4))
    end, [{false, #{bg => cyan, fg => black}},
          {true, #{bg => white, fg => black, bold => true}}]).

custom_table_styles_and_virtual_rows_test() ->
    Table = (table())#table{selected_style = #{bg => blue, fg => white},
        focused_selected_style = #{bg => black, fg => cyan, underline => true}},
    Virtual = Table#table{rows = [], total_rows = 2, row_provider = fun(_, _) -> Table#table.rows end},
    lists:foreach(fun({Focused, Expected}) ->
        Output = nit_el_table:render(Table, bounds(), #{focused => Focused}),
        ?assertEqual(iolist_to_binary(Output),
            iolist_to_binary(nit_el_table:render(Virtual, bounds(), #{focused => Focused}))),
        Screen = screen(Output),
        ?assertEqual(Expected, cell_style(Screen, 0, 2)),
        ?assertEqual(Expected, cell_style(Screen, 11, 2)),
        ?assertEqual(#{fg => green, bold => true}, cell_style(Screen, 0, 0)),
        ?assertEqual(#{fg => green}, cell_style(Screen, 0, 3)),
        ?assertEqual(#{fg => green}, cell_style(Screen, 0, 4))
    end, [{false, Table#table.selected_style}, {true, Table#table.focused_selected_style}]).

standalone_table_container_or_child_focus_test() ->
    Table = table(),
    Focused = iolist_to_binary(nit_el_table:render(Table, bounds(), #{focused => true})),
    ?assertEqual([table], nit_focus:collect_containers(Table)),
    ?assertEqual([], nit_focus:collect_children(Table, table)),
    ?assertEqual(Focused, iolist_to_binary(render(Table, table, undefined))),
    ?assertEqual(Focused, iolist_to_binary(render(Table, other, table))),
    Anonymous = Table#table{id = undefined},
    ?assertEqual(iolist_to_binary(nit_el_table:render(Anonymous, bounds(), #{})),
                 iolist_to_binary(render(Anonymous, undefined, undefined))).

tree_default_and_custom_selection_styles_test() ->
    Tree = tree(),
    Normal = nit_el_tree:render(Tree, bounds(), #{}),
    ?assertEqual(iolist_to_binary(Normal),
        iolist_to_binary(nit_el_tree:render(Tree, bounds(), #{focused => true}))),
    ?assertEqual(#{bg => white, fg => black}, cell_style(screen(Normal), 0, 0)),
    ?assertEqual(#{}, cell_style(screen(Normal), 11, 0)),
    Custom = Tree#tree{selected_style = #{bg => blue, fg => white},
        focused_selected_style = #{bg => black, fg => yellow, bold => true}},
    lists:foreach(fun({Focused, Expected}) ->
        Output = nit_el_tree:render(Custom, bounds(), #{focused => Focused}),
        Screen = screen(Output),
        ?assertEqual(Expected, cell_style(Screen, 0, 0)),
        ?assertEqual(#{fg => green}, cell_style(Screen, 0, 1)),
        ?assertEqual(#{}, cell_style(Screen, 11, 0))
    end, [{false, Custom#tree.selected_style}, {true, Custom#tree.focused_selected_style}]),
    ?assertEqual(iolist_to_binary(nit_el_tree:render(Custom, bounds(), #{focused => true})),
                 iolist_to_binary(render(Custom, tree, undefined))),
    ?assertEqual(iolist_to_binary(nit_el_tree:render(Custom, bounds(), #{})),
                 iolist_to_binary(render(Custom#tree{id = undefined}, undefined, undefined))).

full_tree_row_includes_prefix_and_padding_test() ->
    Tree = #tree{x = 2, width = 40, selected = child, full_row_selection = true,
        show_lines = false, focused_selected_style = #{bg => black, fg => cyan}, nodes = [
            #tree_node{id = root, label = <<"Root">>, children = [
                #tree_node{id = child, label = <<"C">>}, #tree_node{id = sibling, label = <<"S">>}]}]},
    Bounds = #bounds{width = 16, height = 4},
    Output = nit_el_tree:render(Tree, Bounds, #{focused => true}),
    Screen = screen(Output),
    lists:foreach(fun(X) -> ?assertEqual(#{bg => black, fg => cyan}, cell_style(Screen, X, 1)) end,
                  lists:seq(2, 15)),
    ?assertEqual({$C, #{bg => black, fg => cyan}}, nit_screen:get_cell(Screen, 8, 1)),
    ?assertEqual({$\s, #{}}, nit_screen:get_cell(Screen, 16, 1)),
    ?assertEqual(#{}, cell_style(Screen, 8, 2)),
    ?assertEqual(nit_el_tree:height(Tree, Bounds), nit_el_tree:height(Tree#tree{full_row_selection = false}, Bounds)),
    ?assertEqual(nit_el_tree:width(Tree, Bounds), nit_el_tree:width(Tree#tree{full_row_selection = false}, Bounds)).

full_tree_row_clips_deep_prefix_and_label_test_() ->
    [?_test(begin
        Tree = #tree{width = Width, selected = child, full_row_selection = true,
            indent = 8, show_lines = false, nodes = [#tree_node{id = root, children = [
                #tree_node{id = child, label = <<"Long child label">>}]}]},
        Screen = screen(nit_el_tree:render(Tree, bounds(), #{})),
        ?assertEqual({$\s, #{}}, nit_screen:get_cell(Screen, Width, 1)),
        lists:foreach(fun(X) ->
            ?assertEqual(#{bg => white, fg => black}, cell_style(Screen, X, 1))
        end, lists:seq(0, Width - 1))
    end) || Width <- [1, 2, 5, 8, 10]].

button_default_and_custom_focus_styles_test() ->
    Default = #button{id = button, label = <<"OK">>, width = 10},
    Custom = Default#button{style = #{bg => white, fg => black},
        focused_style = #{bg => black, fg => cyan, bold => false, underline => false}},
    lists:foreach(fun({Button, Expected}) ->
        Direct = nit_element:render(Button, bounds(), #{focused => true}),
        TwoLevel = render(Button, other, button),
        ?assertEqual(iolist_to_binary(Direct), iolist_to_binary(TwoLevel)),
        ?assertEqual(Expected, cell_style(screen(Direct), 0, 0)),
        ?assertEqual(iolist_to_binary(Direct), iolist_to_binary(nit_render:render_two_level(
            Button, bounds(), other, button, #{hovered_id => button}))),
        ?assertEqual(Expected#{dim => true}, cell_style(screen(
            nit_render:render_dimmed(Button, bounds(), button)), 0, 0))
    end, [{Default, #{bold => true, underline => true}}, {Custom, #{bg => black, fg => cyan}}]),
    ?assertEqual(Custom#button.style, cell_style(screen(render(Custom, other, undefined)), 0, 0)),
    Anonymous = Custom#button{id = undefined},
    ?assertEqual(Custom#button.style, cell_style(screen(render(Anonymous, undefined, undefined)), 0, 0)),
    UI = #vbox{children = [Custom, #text{content = <<"Next">>, style = #{fg => green}}]},
    ?assertEqual({$N, #{fg => green}}, nit_screen:get_cell(screen(render(UI, other, button)), 0, 1)).

scroll_observer_table_focus_test_() ->
    Table = (table())#table{height = 4},
    Sibling = Table#table{id = sibling},
    UI = pane(#scroll{id = scroll, children = [#vbox{children = [Table, Sibling]}]}),
    Active = Table#table.focused_selected_style,
    Inactive = Table#table.selected_style,
    [?_test(begin
        Normal = render(UI, undefined, undefined),
        ?assertEqual(iolist_to_binary(nit_render:render(UI, bounds())), iolist_to_binary(Normal)),
        Output = render(UI, Container, Child),
        Screen = screen(Output),
        ?assertEqual(FirstStyle, cell_style(Screen, 1, 3)),
        ?assertEqual(SecondStyle, cell_style(Screen, 1, 7)),
        ?assertEqual(#{fg => green, bold => true}, cell_style(Screen, 1, 1)),
        ?assertEqual(#{fg => green}, cell_style(Screen, 1, 4)),
        ?assertEqual(cursor_positions(Normal), cursor_positions(Output)),
        ?assertEqual(cell_chars(screen(Normal), 1, 1, 22, 8), cell_chars(Screen, 1, 1, 22, 8))
    end) || {Container, Child, FirstStyle, SecondStyle} <- [
        {table, undefined, Active, Inactive}, {scroll, table, Active, Inactive},
        {sibling, undefined, Inactive, Active}, {scroll, undefined, Inactive, Inactive},
        {missing, missing, Inactive, Inactive}]].

nested_scroll_clipped_table_focus_test_() ->
    Table = table(),
    Inner = #scroll{height = 5, show_scrollbar = false,
                    children = [#vbox{children = [Table]}]},
    [?_test(begin
        Bounds = #bounds{x = 2, y = 1, width = 15, height = Height},
        Scroll = #scroll{offset = Offset, children = [#vbox{children = [
            #text{content = <<"Top">>}, Inner, #text{content = <<"End">>}]}]},
        Normal = nit_render:render(Scroll, Bounds),
        ?assertEqual(iolist_to_binary(Normal), iolist_to_binary(
            nit_render:render_two_level(Scroll, Bounds, undefined, undefined))),
        Output = nit_render:render_two_level(Scroll, Bounds, table, undefined),
        Screen = screen(Output),
        SelectedY = 4 - min(Offset, 7 - Height),
        ?assertEqual({$o, Table#table.focused_selected_style}, nit_screen:get_cell(Screen, 2, SelectedY)),
        ?assertEqual(Table#table.selected_style, cell_style(screen(Normal), 2, SelectedY)),
        ?assertEqual(cursor_positions(Normal), cursor_positions(Output)),
        ?assertEqual(cell_chars(screen(Normal), 0, 0, 20, 10), cell_chars(Screen, 0, 0, 20, 10)),
        %% Nonzero destination, reserved scrollbar column and unchanged clipping.
        ContentWidth = case Height of 7 -> 15; _ -> 14 end,
        ?assertEqual({ContentWidth, 7}, nit_el_scroll:content_size(Scroll, Bounds)),
        ?assertEqual({$\s, #{}}, nit_screen:get_cell(Screen, 1, SelectedY)),
        ?assertEqual({$\s, #{}}, nit_screen:get_cell(Screen, 17, SelectedY)),
        ?assertEqual({$\s, #{}}, nit_screen:get_cell(Screen, 2, 0)),
        ?assertEqual({$\s, #{}}, nit_screen:get_cell(Screen, 2, 1 + Height))
    end) || {Height, Offset} <- [{7, 0}, {4, 0}, {4, 2}, {4, 99}]].

scroll_clipped_table_sibling_focus_test_() ->
    Table = table(),
    Anonymous = Table#table{id = undefined},
    Bounds = #bounds{width = 24, height = 2},
    Scroll = #scroll{offset = 2, show_scrollbar = false, children = [
        #vbox{children = [#hbox{children = [Table, Anonymous]}]}]},
    [?_test(begin
        Output = nit_render:render_two_level(Scroll, Bounds, Container, Child),
        Screen = screen(Output),
        ?assertEqual({$o, Expected}, nit_screen:get_cell(Screen, 0, 0)),
        ?assertEqual({$o, Table#table.selected_style}, nit_screen:get_cell(Screen, 12, 0)),
        ?assertEqual(#{fg => green}, cell_style(Screen, 0, 1)),
        ?assertEqual(#{fg => green}, cell_style(Screen, 12, 1)),
        ?assertEqual({$\s, #{}}, nit_screen:get_cell(Screen, 0, 2))
    end) || {Container, Child, Expected} <- [
        {table, undefined, Table#table.focused_selected_style},
        {other, table, Table#table.focused_selected_style},
        {undefined, undefined, Table#table.selected_style}]].

scroll_tree_focus_test_() ->
    Tree = (tree())#tree{width = 12, selected = b, full_row_selection = true,
        focused_selected_style = #{bg => black, fg => yellow, bold => true}},
    [?_test(begin
        Bounds = #bounds{width = 24, height = Height},
        Scroll = #scroll{offset = Offset, show_scrollbar = false, children = [
            #vbox{children = [#hbox{children = [Tree, Tree#tree{id = sibling}]}]}]},
        Screen = screen(nit_render:render_two_level(Scroll, Bounds, tree, undefined)),
        ?assertEqual(Tree#tree.focused_selected_style, cell_style(Screen, 0, 1 - Offset)),
        ?assertEqual(Tree#tree.focused_selected_style, cell_style(Screen, 11, 1 - Offset)),
        ?assertEqual(Tree#tree.selected_style, cell_style(Screen, 12, 1 - Offset)),
        ?assertEqual(Tree#tree.selected_style, cell_style(Screen, 23, 1 - Offset))
    end) || {Height, Offset} <- [{2, 0}, {1, 1}]].

scroll_button_and_frame_focus_test_() ->
    Button = #button{id = action, width = 8, label = <<"Go">>, style = #{fg => blue},
                     focused_style = #{bg => black, fg => cyan}},
    Frame = (pane(#vbox{children = [Button, Button#button{id = inactive}]}))#box{
        id = frame, width = 12, height = 4},
    Sibling = Frame#box{id = sibling, children = [Button#button{id = sibling_action}]},
    [?_test(begin
        Bounds = #bounds{width = 24, height = Height},
        Scroll = #scroll{offset = Offset, show_scrollbar = false,
            children = [#vbox{children = [#hbox{children = [Frame, Sibling]}]}]},
        Normal = nit_render:render(Scroll, Bounds),
        ?assertEqual(iolist_to_binary(Normal), iolist_to_binary(
            nit_render:render_two_level(Scroll, Bounds, undefined, undefined))),
        Output = nit_render:render_two_level(Scroll, Bounds, Container, Child),
        Screen = screen(Output),
        ExpectedButton = case Child of
            action -> maps:merge(Button#button.style, Button#button.focused_style);
            undefined -> Button#button.style
        end,
        ?assertEqual(ExpectedButton, cell_style(Screen, 1, 1 - Offset)),
        ?assertEqual(Button#button.style, cell_style(Screen, 1, 2 - Offset)),
        ?assertEqual(Button#button.style, cell_style(Screen, 13, 1 - Offset)),
        ?assertEqual({FocusedBorder, focus_style()}, nit_screen:get_cell(Screen, 0, 0)),
        ?assertEqual({NormalBorder, #{fg => blue}}, nit_screen:get_cell(Screen, 12, 0)),
        ?assertEqual(cursor_positions(Normal), cursor_positions(Output)),
        ?assertEqual({$\s, #{}}, nit_screen:get_cell(Screen, 0, Height))
    end) || {Height, Offset, FocusedBorder, NormalBorder} <- [
                {4, 0, $╔, $┌}, {3, 0, $╔, $┌}, {3, 1, $║, $│}],
            {Container, Child} <- [{frame, action}, {other, action}, {frame, undefined}]].

scroll_preserves_render_options_test() ->
    Input = #input{id = input, value = <<"Edit">>, width = 8},
    Button = #button{id = hovered, label = <<"Hover">>, width = 8},
    Children = #vbox{children = [Input, Button]},
    Scroll = #scroll{show_scrollbar = false, children = [Children]},
    Opts = #{cursor_visible => false, hovered_id => hovered},
    Direct = nit_render:render_two_level(Children, bounds(), other, input, Opts),
    ?assertEqual(iolist_to_binary(Direct), iolist_to_binary(
        nit_render:render_two_level(Scroll, bounds(), other, input, Opts))),
    %% The behaviour entry point still forwards plain element options unchanged.
    PlainOpts = #{focused => true, base_style => #{dim => true}},
    ?assertEqual(iolist_to_binary(nit_element:render(Children, bounds(), PlainOpts)),
                 iolist_to_binary(nit_element:render(Scroll, bounds(), PlainOpts))).

bounds() -> #bounds{width = 24, height = 10}.

focus_style() -> #{fg => magenta, bold => true}.

pane(Child) ->
    #box{id = pane, border = single, width = 24, height = 10, style = #{fg => blue},
         focus_within = true, focused_border = double, focused_style = focus_style(), children = [Child]}.

tree() ->
    #tree{id = tree, focusable = true, selected = a, style = #{fg => green}, nodes = [
        #tree_node{id = a, label = <<"A">>}, #tree_node{id = b, label = <<"B">>}]}.

table() ->
    #table{id = table, focusable = true, width = 12, height = 5, zebra = false,
        selected_row = 1, style = #{fg => green}, columns = [#table_col{header = <<"Col">>}],
        rows = [[<<"one">>], [<<"two">>]]}.

render(Element, Container, Child) -> nit_render:render_two_level(Element, bounds(), Container, Child).

screen(Output) -> nit_screen:from_ansi(Output, 32, 12).

corner(Element, Container, Child) -> nit_screen:get_cell(screen(render(Element, Container, Child)), 0, 0).

cell_style(Screen, X, Y) -> element(2, nit_screen:get_cell(Screen, X, Y)).

cell_chars(Screen, X, Y, Width, Height) ->
    [element(1, nit_screen:get_cell(Screen, Col, Row)) || Row <- lists:seq(Y, Y + Height - 1),
                                                       Col <- lists:seq(X, X + Width - 1)].

cursor_positions(Output) ->
    case re:run(iolist_to_binary(Output), <<"\e\\[([0-9]+);([0-9]+)H">>,
                [global, {capture, [1, 2], binary}]) of
        nomatch -> [];
        {match, Matches} -> Matches
    end.