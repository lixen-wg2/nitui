%%%-------------------------------------------------------------------
%%% @doc Regression tests for bounded, styled stat row rendering.
%%% @end
%%%-------------------------------------------------------------------
-module(nit_el_stat_row_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("nitui/include/nit_elements.hrl").

styled_clipping_test_() ->
    [{"styled width " ++ integer_to_list(Width), fun() ->
        Row = (styled_row())#stat_row{x = 2, y = 1},
        Bounds = #bounds{x = 3, y = 1, width = Width + 2, height = 2},
        Full = <<"CPU: 123 | Mem: 456">>,
        Expected = binary:part(Full, 0, min(Width, byte_size(Full))),
        Output = assert_render(Row, Bounds, style_opts(), Expected),
        Screen = nit_screen:from_ansi([
            nit_ansi:style_to_ansi(#{dim => true, reverse => true}),
            Output, nit_ansi:move_to(3, 1), <<"!">>
        ], 30, 5),
        lists:foreach(fun(Index) ->
            ?assertEqual({binary:at(Expected, Index), expected_style(Index)},
                         nit_screen:get_cell(Screen, 5 + Index, 2))
        end, lists:seq(0, byte_size(Expected) - 1)),
        ?assertEqual({$\s, #{}}, nit_screen:get_cell(Screen, 4, 2)),
        ?assertEqual({$\s, #{}}, nit_screen:get_cell(Screen, 5 + Width, 2)),
        ?assertEqual({$\s, #{}}, nit_screen:get_cell(Screen, 5, 3)),
        case Width of
            0 -> ?assertEqual({$!, #{dim => true, reverse => true}},
                              nit_screen:get_cell(Screen, 1, 3));
            _ -> ?assertEqual({$!, #{}}, nit_screen:get_cell(Screen, 1, 3))
        end
    end} || Width <- lists:seq(0, 21)].

offsets_and_declared_width_test_() ->
    [{"declared width " ++ lists:flatten(io_lib:format("~p", [Width])), fun() ->
        Row = (styled_row())#stat_row{x = 3, y = 2, width = Width},
        Bounds = #bounds{x = 4, y = 5, width = 8, height = 3},
        assert_render(Row, Bounds, style_opts(), Expected)
    end} || {Width, Expected} <- [
        {auto, <<"CPU: ">>}, {fill, <<"CPU: ">>}, {0, <<>>},
        {2, <<"CP">>}, {5, <<"CPU: ">>}, {50, <<"CPU: ">>}
    ]].

outside_bounds_test_() ->
    [{"outside bounds " ++ integer_to_list(Index), fun() ->
        ?assertEqual([], nit_el_stat_row:render(Row, Bounds, style_opts()))
    end} || {Index, {Row, Bounds}} <- lists:zip(lists:seq(1, 9), [
        {styled_row(), #bounds{width = 0, height = 1}},
        {styled_row(), #bounds{width = 20, height = 0}},
        {(styled_row())#stat_row{x = 20}, #bounds{width = 20, height = 1}},
        {(styled_row())#stat_row{x = 21}, #bounds{width = 20, height = 1}},
        {(styled_row())#stat_row{y = 1}, #bounds{width = 20, height = 1}},
        {(styled_row())#stat_row{y = 2}, #bounds{width = 20, height = 1}},
        {(styled_row())#stat_row{x = -1}, #bounds{width = 20, height = 1}},
        {(styled_row())#stat_row{y = -1}, #bounds{width = 20, height = 1}},
        {(styled_row())#stat_row{width = -1}, #bounds{width = 20, height = 1}}
    ])].

unicode_width_test() ->
    Row = unicode_row(),
    ?assertEqual(14, nit_el_stat_row:width(Row, #bounds{width = 1})),
    ?assertEqual(8, nit_el_stat_row:width(
        Row#stat_row{items = [hd(Row#stat_row.items)]}, #bounds{})).

unicode_clipping_test_() ->
    Label = <<"界e"/utf8, 16#0301/utf8>>,
    Item = <<Label/binary, ": 📦x"/utf8>>,
    WithSeparator = <<Item/binary, "│"/utf8, 16#0301/utf8>>,
    [{"unicode width " ++ integer_to_list(Width), fun() ->
        assert_render(unicode_row(), #bounds{width = Width, height = 1}, #{}, Expected)
    end} || {Width, Expected} <- [
        {0, <<>>}, {1, <<>>}, {2, <<"界"/utf8>>},
        {3, Label}, {4, <<Label/binary, ":">>},
        {5, <<Label/binary, ": ">>}, {6, <<Label/binary, ": ">>},
        {7, <<Label/binary, ": 📦"/utf8>>}, {8, Item}, {9, WithSeparator},
        {10, <<WithSeparator/binary, "λ"/utf8>>},
        {11, <<WithSeparator/binary, "λ:"/utf8>>},
        {12, <<WithSeparator/binary, "λ: "/utf8>>},
        {13, <<WithSeparator/binary, "λ: "/utf8>>},
        {14, <<WithSeparator/binary, "λ: 好"/utf8>>}
    ]].

wide_separator_boundary_test_() ->
    [{"wide separator width " ++ integer_to_list(Width), fun() ->
        Row = #stat_row{items = [{<<"a">>, <<"b">>}, {<<"c">>, <<"d">>}],
                        separator = <<"界x"/utf8>>},
        assert_render(Row, #bounds{width = Width, height = 1}, #{}, Expected)
    end} || {Width, Expected} <- [
        {4, <<"a: b">>}, {5, <<"a: b">>}, {6, <<"a: b界"/utf8>>},
        {7, <<"a: b界x"/utf8>>}, {8, <<"a: b界xc"/utf8>>},
        {11, <<"a: b界xc: d"/utf8>>}, {20, <<"a: b界xc: d"/utf8>>}
    ]].

combining_value_at_boundary_test() ->
    Row = #stat_row{items = [{<<"x">>, <<"e", 16#0301/utf8, "z">>}]},
    assert_render(Row, #bounds{width = 4, height = 1}, #{}, <<"x: e", 16#0301/utf8>>).

empty_and_hidden_test() ->
    Bounds = #bounds{x = 3, y = 2, width = 20, height = 1},
    ?assertEqual([], nit_el_stat_row:render(#stat_row{}, Bounds, #{})),
    ?assertEqual(0, nit_el_stat_row:width(#stat_row{}, Bounds)),
    ?assertEqual([], nit_el_stat_row:render(
        (styled_row())#stat_row{visible = false}, Bounds, style_opts())),
    Row = #stat_row{items = [{<<>>, <<>>}, {<<>>, <<>>}], separator = <<>>},
    ?assertEqual(4, nit_el_stat_row:width(Row, Bounds)),
    assert_render(Row, Bounds, #{}, <<": : ">>),
    assert_render(Row#stat_row{width = 1}, Bounds, #{}, <<":">>).

width_callbacks_test() ->
    Row = (styled_row())#stat_row{x = 3},
    Bounds = #bounds{width = 8},
    ?assertEqual(19, nit_el_stat_row:width(Row, Bounds)),
    ?assertEqual(4, nit_el_stat_row:width(Row#stat_row{width = 4}, Bounds)),
    ?assertEqual(50, nit_el_stat_row:width(Row#stat_row{width = 50}, Bounds)),
    ?assertEqual(0, nit_el_stat_row:width(Row#stat_row{width = 0}, Bounds)),
    ?assertEqual(5, nit_el_stat_row:width(Row#stat_row{width = fill}, Bounds)),
    ?assertEqual(0, nit_el_stat_row:width(Row#stat_row{width = fill, x = 9}, Bounds)),
    ?assertEqual(auto, nit_el_stat_row:fixed_width(Row)),
    ?assertEqual(auto, nit_el_stat_row:fixed_width(Row#stat_row{width = fill})),
    ?assertEqual(4, nit_el_stat_row:fixed_width(Row#stat_row{width = 4})),
    ?assertEqual(1, nit_el_stat_row:height(Row, Bounds)).

control_characters_cannot_move_cursor_test() ->
    Row = #stat_row{items = [{<<"a\nb\rc\td">>, <<"1\b2", 16#85/utf8>>},
                              {<<"e">>, <<"3">>}], separator = <<"\n|\r">>},
    Bounds = #bounds{width = 20, height = 1},
    ?assertEqual(13, nit_el_stat_row:width(Row, Bounds)),
    assert_render(Row, Bounds, #{}, <<"abcd: 12|e: 3">>).

embedded_escape_cannot_move_cursor_test() ->
    Row = #stat_row{items = [{<<"a\e[9;9H">>, <<"b">>}]},
    Bounds = #bounds{width = 20, height = 1},
    ?assertEqual(9, nit_el_stat_row:width(Row, Bounds)),
    assert_render(Row, Bounds, #{}, <<"a[9;9H: b">>).

styled_row() ->
    #stat_row{items = [{<<"CPU">>, <<"123">>}, {<<"Mem">>, <<"456">>}],
              style = #{fg => yellow, underline => true, bold => false},
              label_style = #{fg => cyan, bold => true},
              value_style = #{fg => green, italic => false}}.

style_opts() ->
    #{base_style => #{fg => white, bg => blue, italic => true, bold => true}}.

expected_style(Index) when Index < 5; Index >= 11, Index < 16 ->
    #{fg => cyan, bg => blue, italic => true, underline => true, bold => true};
expected_style(Index) when Index < 8; Index >= 16 ->
    #{fg => green, bg => blue, underline => true};
expected_style(_Index) ->
    #{dim => true}.

unicode_row() ->
    #stat_row{items = [{<<"界e"/utf8, 16#0301/utf8>>, <<"📦x"/utf8>>},
                       {<<"λ"/utf8>>, <<"好"/utf8>>}],
              separator = <<"│"/utf8, 16#0301/utf8>>}.

assert_render(Row, Bounds, Opts, Expected) ->
    Output = iolist_to_binary(nit_el_stat_row:render(Row, Bounds, Opts)),
    %% Only remove complete cursor/style sequences; any broken ANSI remains
    %% visible and fails the exact text assertion. Do not use nit_screen for
    %% Unicode widths: its parser currently advances one column per codepoint.
    WithoutCharset = binary:replace(Output, <<"\e(B">>, <<>>, [global]),
    Text = re:replace(WithoutCharset, <<"\e\\[[0-9;]*[Hm]">>, <<>>,
                      [global, {return, binary}]),
    ?assertEqual(Expected, Text),
    ?assert(is_list(unicode:characters_to_list(Text))),
    Available = max(0, Bounds#bounds.width - Row#stat_row.x),
    MaxWidth = max(0, min(Available, nit_ansi:resolve_size(Row#stat_row.width, Available))),
    ?assert(nit_unicode:display_width(Text) =< MaxWidth),
    case Expected of
        <<>> -> ?assertEqual(<<>>, Output);
        _ ->
            Move = nit_ansi:move_to(Bounds#bounds.y + Row#stat_row.y,
                                    Bounds#bounds.x + Row#stat_row.x),
            ?assertEqual({match, [[Move]]}, re:run(Output, <<"\e\\[[0-9;]*H">>,
                                                  [global, {capture, first, binary}])),
            Reset = nit_ansi:reset_style(),
            ?assertEqual(Reset, binary:part(Output, byte_size(Output) - byte_size(Reset),
                                           byte_size(Reset)))
    end,
    Output.