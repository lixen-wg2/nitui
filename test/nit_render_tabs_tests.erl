%%% Regression coverage for native compact tab bars in the runtime renderer.
-module(nit_render_tabs_tests).

-include_lib("eunit/include/eunit.hrl").
-include("nit_elements.hrl").

two_level_height_one_headers_and_hits_test() ->
    Bounds = #bounds{x = 3, y = 2, width = 30, height = 10},
    Tabs = (tabs(1, []))#tabs{x = 2, y = 1, width = 20},
    Output = nit_render:render_two_level(Tabs, Bounds, tabs, two),
    Screen = nit_screen:from_ansi(Output, 40, 15),
    %% Actual origin is (5,3); padded headers start at x+1, not x.
    ?assertEqual([{3, 6}, {3, 12}], cursor_positions(Output)),
    ?assertEqual(<<" One ">>, cells_text(Screen, 6, 3, 5)),
    ?assertEqual(<<" Two ">>, cells_text(Screen, 12, 3, 5)),
    assert_blank_rows(Screen, 40, lists:seq(0, 2) ++ lists:seq(4, 14)),
    {_, ActiveStyle} = nit_screen:get_cell(Screen, 7, 3),
    {_, FocusStyle} = nit_screen:get_cell(Screen, 13, 3),
    ?assertEqual(cyan, maps:get(bg, ActiveStyle)),
    ?assertEqual(white, maps:get(bg, FocusStyle)),
    ?assertEqual(true, maps:get(bold, FocusStyle)),
    %% nit_hit consumes one-based mouse coordinates; click the label cells.
    lists:foreach(fun(Col) ->
        ?assertEqual({tab, tabs, one}, nit_hit:find_at(Tabs, Col, 4, Bounds))
    end, [8, 9, 10]),
    lists:foreach(fun(Col) ->
        ?assertEqual({tab, tabs, two}, nit_hit:find_at(Tabs, Col, 4, Bounds))
    end, [14, 15, 16]),
    ?assertEqual(not_found, nit_hit:find_at(Tabs, 8, 5, Bounds)).

compact_two_level_and_dimmed_skip_content_test() ->
    Bounds = #bounds{x = 2, y = 3, width = 20, height = 8},
    %% A bordered child would itself crash at tiny heights if dispatched.
    Content = [#box{border = single, height = 1}, #text{content = <<"HIDDEN">>}],
    lists:foreach(fun(Height) ->
        Tabs = tabs(Height, Content),
        lists:foreach(fun(Render) ->
            Output = Render(Tabs, Bounds),
            ?assertEqual([{3, 3}, {3, 9}], cursor_positions(Output)),
            ?assertEqual(nomatch, binary:match(iolist_to_binary(Output), <<"HIDDEN">>)),
            Screen = nit_screen:from_ansi(Output, 30, 12),
            assert_blank_rows(Screen, 30, lists:seq(0, 2) ++ lists:seq(4, 11))
        end, [fun render_two_level/2, fun render_dimmed/2])
    end, [1, 2]).

standalone_vbox_compact_main_and_detail_tabs_test() ->
    Main = #tabs{id = main, height = 1, tabs = [
        #tab{id = home, label = <<"Home(H)">>},
        #tab{id = system, label = <<"System(S)">>}]},
    Detail = #tabs{id = detail, height = 1, tabs = [
        #tab{id = info, label = <<"Info(P)">>},
        #tab{id = stack, label = <<"Stack(C)">>}]},
    Tree = #vbox{children = [Main, #text{content = <<"Title">>}, Detail,
        #box{border = none, height = fill, children = [
            #vbox{children = [#text{content = <<"Body">>}, #spacer{}]}]},
        #text{content = <<"Command>">>}]},
    Bounds = #bounds{width = 50, height = 8},
    ?assertEqual([1, 1, 1, 4, 1],
        nit_layout:calculate_vbox_heights(Tree#vbox.children, Bounds, 0)),
    Output = nit_render:render_two_level(Tree, Bounds, detail, stack, #{cursor_visible => false}),
    Screen = nit_screen:from_ansi(Output, 50, 10),
    ?assertEqual([{0, 1}, {0, 11}, {1, 0}, {2, 1}, {2, 11}, {3, 0}, {7, 0}],
        cursor_positions(Output)),
    ?assertEqual(<<"Home(H)">>, cells_text(Screen, 2, 0, 7)),
    ?assertEqual(<<"System(S)">>, cells_text(Screen, 12, 0, 9)),
    ?assertEqual(<<"Title">>, cells_text(Screen, 0, 1, 5)),
    ?assertEqual(<<"Info(P)">>, cells_text(Screen, 2, 2, 7)),
    ?assertEqual(<<"Stack(C)">>, cells_text(Screen, 12, 2, 8)),
    ?assertEqual(<<"Body">>, cells_text(Screen, 0, 3, 4)),
    ?assertEqual(<<"Command>">>, cells_text(Screen, 0, 7, 8)),
    assert_blank_rows(Screen, 50, [4, 5, 6, 8, 9]),
    ?assertEqual({tab, main, system}, nit_hit:find_at(Tree, 13, 1, Bounds)),
    ?assertEqual({tab, detail, stack}, nit_hit:find_at(Tree, 13, 3, Bounds)).

single_level_compact_stays_within_height_test() ->
    Bounds = #bounds{x = 2, y = 3, width = 20, height = 8},
    lists:foreach(fun(Height) ->
        Tabs = tabs(Height, [#text{content = <<"HIDDEN">>}]),
        Output = nit_render:render(Tabs, Bounds),
        ExpectedPositions = case Height of
            1 -> [{3, 2}, {3, 8}];
            2 -> [{3, 2}, {3, 8}, {4, 2}]
        end,
        ?assertEqual(ExpectedPositions, cursor_positions(Output)),
        ?assertEqual(nomatch, binary:match(iolist_to_binary(Output), <<"HIDDEN">>)),
        Screen = nit_screen:from_ansi(Output, 30, 12),
        ?assertEqual(<<" One ">>, cells_text(Screen, 2, 3, 5)),
        assert_blank_rows(Screen, 30, lists:seq(3 + Height, 11))
    end, [1, 2]).

empty_and_invalid_tab_bounds_test() ->
    Bounds = #bounds{width = 20, height = 8},
    lists:foreach(fun(Render) ->
        lists:foreach(fun({Tabs, B}) ->
            ?assertEqual(<<>>, iolist_to_binary(Render(Tabs, B)))
        end, [{tabs(0, []), Bounds}, {tabs(-1, []), Bounds},
              {(tabs(1, []))#tabs{width = 0}, Bounds},
              {(tabs(1, []))#tabs{width = -1}, Bounds},
              {tabs(1, []), Bounds#bounds{height = 0}},
              {tabs(1, []), Bounds#bounds{width = 0}},
              {(tabs(1, []))#tabs{x = 21}, Bounds},
              {(tabs(1, []))#tabs{y = 9}, Bounds}])
    end, renderers()),
    ?assertEqual(<<>>, iolist_to_binary(render_two_level(#tabs{height = 1}, Bounds))).

tiny_tab_widths_are_clipped_test() ->
    lists:foreach(fun(Render) ->
        lists:foreach(fun({Width, Height}) ->
            Bounds = #bounds{x = 2, y = 1, width = Width, height = Height},
            %% Explicit sizes must also respect the available viewport.
            Output = Render((tabs(8, []))#tabs{width = 40}, Bounds),
            Screen = nit_screen:from_ansi(Output, 30, 10),
            lists:foreach(fun({Row, Col}) ->
                ?assert(Row >= 1 andalso Row < 1 + Height),
                ?assert(Col >= 2 andalso Col < 2 + Width)
            end, cursor_positions(Output)),
            lists:foreach(fun(Row) ->
                ?assertEqual(binary:copy(<<" ">>, 28 - Width),
                    cells_text(Screen, 2 + Width, Row, 28 - Width))
            end, lists:seq(0, 9)),
            assert_blank_rows(Screen, 30, [0 | lists:seq(1 + Height, 9)])
        end, [{W, H} || W <- [1, 2, 5], H <- [1, 2, 3]])
    end, renderers()).

regular_two_level_tabs_preserve_border_and_content_test() ->
    Bounds = #bounds{x = 2, y = 1, width = 20, height = 10},
    lists:foreach(fun(Height) ->
        Tabs = tabs(Height, [#text{content = <<"Body">>}]),
        lists:foreach(fun(Render) ->
            Output = Render(Tabs, Bounds),
            Screen = nit_screen:from_ansi(Output, 30, 12),
            ?assertEqual(<<"┌"/utf8>>, cells_text(Screen, 2, 1, 1)),
            ?assertEqual(<<"┐"/utf8>>, cells_text(Screen, 21, 1, 1)),
            ?assertEqual(<<"└"/utf8>>, cells_text(Screen, 2, Height, 1)),
            ?assertEqual(<<"┘"/utf8>>, cells_text(Screen, 21, Height, 1)),
            ?assertEqual(<<" One ">>, cells_text(Screen, 3, 1, 5)),
            ?assertEqual(<<"Body">>, cells_text(Screen, 3, 3, 4)),
            assert_blank_rows(Screen, 30, lists:seq(Height + 1, 11))
        end, [fun render_two_level/2, fun render_dimmed/2])
    end, [3, 5]).

regular_single_level_tabs_preserve_content_test() ->
    Bounds = #bounds{width = 20, height = 5},
    Output = nit_render:render(tabs(3, [#text{content = <<"Body">>}]), Bounds),
    Screen = nit_screen:from_ansi(Output, 20, 5),
    ?assertEqual(<<" One ">>, cells_text(Screen, 0, 0, 5)),
    ?assertEqual(<<"Body">>, cells_text(Screen, 0, 1, 4)),
    ?assertEqual(<<"─"/utf8>>, cells_text(Screen, 19, 1, 1)),
    assert_blank_rows(Screen, 20, [2, 3, 4]).

tabs(Height, Content) ->
    #tabs{id = tabs, height = Height, tabs = [
        #tab{id = one, label = <<"One">>, content = Content},
        #tab{id = two, label = <<"Two">>}]}.

render_two_level(Tabs, Bounds) ->
    nit_render:render_two_level(Tabs, Bounds, tabs, one, #{}).

render_dimmed(Tabs, Bounds) ->
    nit_render:render_dimmed(Tabs, Bounds, undefined).

renderers() ->
    [fun render_two_level/2, fun render_dimmed/2, fun nit_render:render/2].

%% Inspect raw moves as well as an oversized screen: clipping to the nominal
%% viewport would hide exactly the offscreen-row regression being tested.
cursor_positions(Output) ->
    case re:run(iolist_to_binary(Output), <<"\e\\[([0-9]+);([0-9]+)H">>,
                [global, {capture, [1, 2], binary}]) of
        nomatch -> [];
        {match, Matches} -> [{binary_to_integer(Row) - 1, binary_to_integer(Col) - 1}
                            || [Row, Col] <- Matches]
    end.

assert_blank_rows(Screen, Width, Rows) ->
    lists:foreach(fun(Row) ->
        ?assertEqual(binary:copy(<<" ">>, Width), cells_text(Screen, 0, Row, Width))
    end, Rows).

cells_text(Screen, X, Y, Width) ->
    iolist_to_binary([cell_text(nit_screen:get_cell(Screen, Col, Y))
                      || Col <- lists:seq(X, X + Width - 1)]).

cell_text({Char, _Style}) when is_integer(Char) -> unicode:characters_to_binary([Char]);
cell_text({Char, _Style}) when is_binary(Char) -> Char.