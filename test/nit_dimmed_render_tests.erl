%%% Regression tests for the background renderer used behind modals.
-module(nit_dimmed_render_tests).

-include_lib("eunit/include/eunit.hrl").
-include("nit_elements.hrl").

stat_row_cells_and_clipping_test() ->
    Row = #stat_row{x = 1, y = 1, width = 100,
        items = [{<<"CPU">>, <<"12">>}, {<<"Mem">>, <<"9">>}],
        style = #{fg => yellow}, label_style = #{fg => cyan}},
    Bounds = #bounds{x = 2, y = 1, width = 12, height = 3},
    Output = nit_render:render_dimmed(Row, Bounds, undefined),
    Screen = screen(Output),
    assert_cells(Screen, 3, 2, "CPU: ", #{fg => cyan, dim => true}),
    assert_cells(Screen, 8, 2, "12", #{fg => yellow, bold => true, dim => true}),
    assert_cells(Screen, 10, 2, " | ", #{dim => true}),
    assert_cells(Screen, 13, 2, "M", #{fg => cyan, dim => true}),
    assert_outside_blank(Screen, #bounds{x = 3, y = 2, width = 11, height = 1}),
    ?assertEqual({$!, #{}}, nit_screen:get_cell(
        screen([Output, nit_ansi:move_to(0, 0), <<"!">>]), 0, 0)).

tree_cells_and_focus_test_() ->
    [?_test(begin
        Tree = (tree())#tree{id = Id, width = 20},
        Bounds = #bounds{x = 2, y = 1, width = 8, height = 2},
        Screen = screen(nit_render:render_dimmed(Tree, Bounds, FocusedId)),
        Selection = case Id =/= undefined andalso Id =:= FocusedId of
            true -> Tree#tree.focused_selected_style;
            false -> Tree#tree.selected_style
        end,
        assert_cells(Screen, 2, 1, "    T   ", Selection#{dim => true}),
        assert_cells(Screen, 2, 2, "    U", #{fg => green, dim => true}),
        assert_outside_blank(Screen, Bounds)
    end) || {Id, FocusedId} <- [{tree, tree}, {tree, missing},
                                {tree, undefined}, {undefined, undefined}]].

list_cells_styles_and_clipping_test() ->
    List = #list{x = 1, offset = 1, selected = 1,
        items = [<<"Above">>, <<"ChosenLong">>, <<"tail">>, <<"Below">>],
        item_style = #{fg => green}, selected_style = #{bg => blue, fg => white}},
    Bounds = #bounds{x = 2, y = 1, width = 6, height = 2},
    Screen = screen(nit_render:render_dimmed(List, Bounds, undefined)),
    assert_cells(Screen, 3, 1, "Chos…", #{bg => blue, fg => white, dim => true}),
    assert_cells(Screen, 3, 2, "tail ", #{fg => green, dim => true}),
    assert_outside_blank(Screen, #bounds{x = 3, y = 1, width = 5, height = 2}),
    %% Adding base_style support must leave ordinary list rendering unchanged.
    Plain = screen(nit_render:render(List, Bounds)),
    assert_cells(Plain, 3, 1, "Chos…", #{bg => blue, fg => white}),
    assert_cells(Plain, 3, 2, "tail ", #{fg => green}).

nested_scroll_focus_and_clipping_test_() ->
    [?_test(begin
        Button = #button{id = action, label = <<"Go">>, width = 8,
            style = #{fg => blue}, focused_style = #{bg => black, fg => cyan}},
        Tree = tree(),
        Columns = #hbox{children = [
            #vbox{width = 8, children = [Button, Tree]},
            #vbox{width = 8, children = [Button#button{id = undefined},
                                        Tree#tree{id = undefined}]}]},
        Inner = #scroll{height = 4, show_scrollbar = false,
            children = [#text{content = <<"Inner">>}, Columns]},
        Scroll = #scroll{id = scroll, offset = Offset, show_scrollbar = false,
            children = [#vbox{children = [#text{content = <<"Top">>}, Inner,
                                         #text{content = <<"End">>}]}]},
        Bounds = #bounds{x = 2, y = 2, width = 16, height = Height},
        SafeOffset = min(Offset, 6 - Height),
        Screen = screen(nit_render:render_dimmed(Scroll, Bounds, FocusedId)),
        Plain = screen(nit_render:render(Scroll, Bounds)),
        ?assertEqual([C || {C, _} <- cells(Plain)], [C || {C, _} <- cells(Screen)]),
        Selection = case FocusedId of
            tree -> Tree#tree.focused_selected_style;
            _ -> Tree#tree.selected_style
        end,
        SelectedY = 5 - SafeOffset,
        assert_cells(Screen, 2, SelectedY, "    T   ", Selection#{dim => true}),
        assert_cells(Screen, 10, SelectedY, "    T   ",
                     (Tree#tree.selected_style)#{dim => true}),
        ButtonY = 4 - SafeOffset,
        case ButtonY >= 2 andalso ButtonY < 2 + Height of
            true ->
                ButtonStyle = case FocusedId of
                    action -> Button#button.focused_style;
                    _ -> Button#button.style
                end,
                assert_cells(Screen, 2, ButtonY, "   Go   ", ButtonStyle#{dim => true}),
                assert_cells(Screen, 10, ButtonY, "   Go   ", #{fg => blue, dim => true});
            false -> ok
        end,
        %% Includes both direct callbacks and offscreen/clipped nested scrolls.
        assert_outside_blank(Screen, Bounds)
    end) || {Height, Offset} <- [{6, 0}, {4, 0}, {4, 1}, {3, 2}, {3, 99}],
            FocusedId <- [action, tree, scroll, missing, undefined]].

scrollbar_cells_are_dimmed_test_() ->
    [?_test(begin
        Scroll = #scroll{offset = Offset, children = [
            #text{content = <<"A">>}, #text{content = <<"B">>},
            #text{content = <<"C">>}, #text{content = <<"D">>}]},
        Bounds = #bounds{x = 2, y = 1, width = 5, height = 2},
        Screen = screen(nit_render:render_dimmed(Scroll, Bounds, undefined)),
        Plain = screen(nit_render:render(Scroll, Bounds)),
        ?assertEqual({4, 4}, nit_el_scroll:content_size(Scroll, Bounds)),
        lists:foreach(fun(Row) ->
            ?assertEqual({$A + Offset + Row, #{dim => true}},
                         nit_screen:get_cell(Screen, 2, 1 + Row)),
            {Bar, Style} = nit_screen:get_cell(Plain, 6, 1 + Row),
            ExpectedBar = case Row =:= Offset div 2 of true -> $█; false -> $░ end,
            ?assertEqual(ExpectedBar, Bar),
            ?assertEqual(false, maps:get(dim, Style, false)),
            ?assertEqual({Bar, Style#{dim => true}},
                         nit_screen:get_cell(Screen, 6, 1 + Row))
        end, [0, 1]),
        assert_outside_blank(Screen, Bounds)
    end) || Offset <- [0, 2]].

hidden_elements_and_subtrees_test_() ->
    Text = #text{content = <<"Hidden">>},
    Hidden = [Text#text{visible = false},
        #button{visible = false, label = <<"Hidden">>},
        #input{visible = false, value = <<"Hidden">>},
        #panel{visible = false, children = [Text]},
        #vbox{visible = false, children = [Text]},
        #hbox{visible = false, children = [Text]},
        #box{visible = false, border = none, children = [Text]},
        #box{visible = false, border = single, width = 12, height = 4, children = [Text]},
        #tabs{visible = false, tabs = [#tab{id = one, label = <<"Hidden">>, content = [Text]}]},
        #scroll{visible = false, children = [Text]},
        (tree())#tree{visible = false},
        #list{visible = false, items = [<<"Hidden">>]},
        #stat_row{visible = false, items = [{<<"Hidden">>, <<"1">>}]}],
    [?_test(begin
        Bounds = #bounds{x = 2, y = 1, width = 20, height = 3},
        ?assertEqual(<<>>, iolist_to_binary(nit_render:render_dimmed(Element, Bounds, tree))),
        %% A clipped container must not reintroduce hidden descendants.
        Scroll = #scroll{show_scrollbar = false, children = [
            #box{height = 8, border = none, children = [Element]}]},
        Screen = screen(nit_render:render_dimmed(Scroll, Bounds, tree)),
        ?assertEqual(cells(screen([])), cells(Screen))
    end) || Element <- Hidden].

unsupported_elements_remain_empty_test_() ->
    [?_assertEqual(<<>>, iolist_to_binary(nit_render:render_dimmed(
        Element, #bounds{}, undefined))) || Element <- [undefined, {unknown}]].

tree() ->
    #tree{id = tree, width = 8, selected = selected, full_row_selection = true,
        style = #{fg => green}, selected_style = #{bg => blue, fg => white},
        focused_selected_style = #{bg => black, fg => cyan, bold => true},
        nodes = [#tree_node{id = selected, label = <<"T">>},
                 #tree_node{id = other, label = <<"U">>}]}.

screen(Output) -> nit_screen:from_ansi(Output, 32, 12).

cells(Screen) ->
    [nit_screen:get_cell(Screen, X, Y) || Y <- lists:seq(0, 11), X <- lists:seq(0, 31)].

assert_cells(Screen, X, Y, Chars, Style) ->
    lists:foreach(fun({Offset, Char}) ->
        ?assertEqual({Char, Style}, nit_screen:get_cell(Screen, X + Offset, Y))
    end, lists:zip(lists:seq(0, length(Chars) - 1), Chars)).

assert_outside_blank(Screen, #bounds{x = X, y = Y, width = Width, height = Height}) ->
    lists:foreach(fun({Col, Row}) ->
        ?assertEqual({$\s, #{}}, nit_screen:get_cell(Screen, Col, Row))
    end, [{Col, Row} || Row <- lists:seq(0, 11), Col <- lists:seq(0, 31),
        Col < X orelse Col >= X + Width orelse Row < Y orelse Row >= Y + Height]).