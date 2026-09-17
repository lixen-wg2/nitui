%%%-------------------------------------------------------------------
%%% @doc Isolated tests for the native read-only text viewer.
%%% @end
%%%-------------------------------------------------------------------
-module(nit_text_view_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("nitui/include/nit_elements.hrl").

source_copy_preserves_tabs_and_line_endings_test() ->
    Text = <<"ab\tcd\r\nef\ngh">>,
    View = (view(Text))#text_view{selection_anchor = 1, cursor_pos = 10},
    ?assertEqual({ok, Text}, nit_el_text_view:copy_text(View, all)),
    ?assertEqual({ok, <<"b\tcd\r\nef\ng">>}, nit_el_text_view:copy_text(View, selection)),
    Reverse = View#text_view{selection_anchor = 10, cursor_pos = 1},
    ?assertEqual(nit_el_text_view:copy_text(View, selection),
                 nit_el_text_view:copy_text(Reverse, selection)),
    lists:foreach(fun(W) ->
        All = nit_el_text_view:key(View, {ctrl, $a}, b(W, 2)),
        ?assertEqual(11, All#text_view.cursor_pos),
        ?assertEqual({ok, Text}, nit_el_text_view:copy_text(All, selection))
    end, [0, 1, 2, 3, 8, 80]).

grapheme_selection_test_() ->
    Graphemes = [<<"e", 16#301/utf8>>, <<16#4E2D/utf8>>,
                 <<16#1F469/utf8, 16#200D/utf8, 16#1F4BB/utf8>>,
                 <<16#1F1F8/utf8, 16#1F1EA/utf8>>,
                 <<16#1F44D/utf8, 16#1F3FD/utf8>>,
                 <<$1, 16#FE0F/utf8, 16#20E3/utf8>>],
    [?_test(begin
        View = (view(<<"a", G/binary, "z">>))#text_view{cursor_pos = 1},
        Selected = nit_el_text_view:key(View, {key, {shift, right}}, b(4, 3)),
        ?assertEqual(2, Selected#text_view.cursor_pos),
        ?assertEqual(1, Selected#text_view.selection_anchor),
        ?assertEqual({ok, G}, nit_el_text_view:copy_text(Selected, selection)),
        ?assert(binary:match(output(View, b(4, 3)), G) =/= nomatch),
        All = nit_el_text_view:key(View, {ctrl, $a}, b(4, 3)),
        ?assertEqual(3, All#text_view.cursor_pos)
    end) || G <- Graphemes].

charlist_copy_is_utf8_test() ->
    Text = [$a, 16#4E2D, $e, 16#301, $\r, $\n],
    View = (view(Text))#text_view{selection_anchor = 1, cursor_pos = 4},
    ?assertEqual({ok, unicode:characters_to_binary(Text)}, nit_el_text_view:copy_text(View, all)),
    ?assertEqual({ok, unicode:characters_to_binary(tl(Text))},
                 nit_el_text_view:copy_text(View, selection)).

invalid_text_rejected_test_() ->
    [?_test(begin
        View = view(Text),
        ?assertEqual({error, invalid_text}, nit_el_text_view:copy_text(View, all)),
        ?assertEqual({error, invalid_text}, nit_el_text_view:copy_text(View, selection)),
        ?assertEqual(View, nit_el_text_view:key(View, {ctrl, $a}, b(10, 2))),
        ?assert(is_binary(output(View, b(10, 2))))
    end) || Text <- [<<255>>, <<16#E2, 16#82>>, [16#D800], [16#110000], invalid]].

no_selection_and_stale_positions_test() ->
    View = view(<<"abc">>),
    ?assertEqual({error, no_selection}, nit_el_text_view:copy_text(View, selection)),
    Empty = View#text_view{selection_anchor = 99, cursor_pos = 88},
    ?assertEqual({error, no_selection}, nit_el_text_view:copy_text(Empty, selection)),
    All = View#text_view{selection_anchor = -1, cursor_pos = 99},
    ?assertEqual({ok, <<"abc">>}, nit_el_text_view:copy_text(All, selection)),
    ?assertEqual({ok, <<>>}, nit_el_text_view:copy_text(view(<<>>), all)).

soft_wrap_source_boundary_test() ->
    View = view(<<"abcdef">>),
    Bounds = b(3, 3),
    ?assertEqual([<<"abc">>, <<"def">>, <<"   ">>], rows(View, Bounds)),
    AtWrap = nit_el_text_view:mouse(View, press, 1, 2, Bounds),
    ?assertEqual(3, AtWrap#text_view.cursor_pos),
    Home = nit_el_text_view:key(AtWrap, {key, home}, Bounds),
    ?assertEqual(3, Home#text_view.cursor_pos),
    Before = View#text_view{cursor_pos = 2},
    Across = keys(Before, [{key, {shift, right}}, {key, {shift, right}}], Bounds),
    ?assertEqual({ok, <<"cd">>}, nit_el_text_view:copy_text(Across, selection)),
    End = nit_el_text_view:key(View#text_view{cursor_pos = 1}, {key, 'end'}, Bounds),
    ?assertEqual(3, End#text_view.cursor_pos),
    ?assertEqual(6, (nit_el_text_view:key(End, {key, 'end'}, Bounds))#text_view.cursor_pos).

full_width_newline_does_not_add_soft_empty_row_test() ->
    View = view(<<"abc\r\ndef\n">>),
    ?assertEqual([<<"abc">>, <<"def">>, <<"   ">>, <<"   ">>], rows(View, b(3, 4))),
    Click = nit_el_text_view:mouse(View, press, 1, 2, b(3, 4)),
    ?assertEqual(4, Click#text_view.cursor_pos),
    All = nit_el_text_view:key(View, {ctrl, $a}, b(3, 4)),
    ?assertEqual(8, All#text_view.cursor_pos),
    Auto = View#text_view{height = auto},
    ?assertEqual(3, nit_el_text_view:height(Auto, b(3, 8))).

wide_cells_map_to_one_source_grapheme_test() ->
    View = view(<<"a", 16#4E2D/utf8, "b">>),
    Bounds = b(3, 2),
    lists:foreach(fun(Col) ->
        Click = nit_el_text_view:mouse(View, press, Col, 1, Bounds),
        ?assertEqual(1, Click#text_view.cursor_pos)
    end, [2, 3]),
    NextRow = nit_el_text_view:mouse(View, press, 1, 2, Bounds),
    ?assertEqual(2, NextRow#text_view.cursor_pos),
    Combining = view(<<"e", 16#301/utf8, "x">>),
    ?assertEqual(1, (nit_el_text_view:mouse(Combining, press, 2, 1, Bounds))#text_view.cursor_pos).

narrow_non_emoji_sequences_keep_second_column_hit_test_() ->
    [?_test(assert_grapheme_cells(G, 1)) || G <-
        [<<$A, 16#200D/utf8>>, <<$A, 16#FE0F/utf8>>, <<$A, 16#20E3/utf8>>,
         <<$A, 16#FE0F/utf8, 16#20E3/utf8>>,
         <<$1, 16#FE0F/utf8>>, <<$#, 16#FE0F/utf8>>, <<$*, 16#FE0F/utf8>>,
         <<16#A9/utf8, 16#200D/utf8>>, <<16#261D/utf8, 16#200D/utf8>>,
         <<16#2388/utf8, 16#FE0F/utf8>>, <<16#2764/utf8, 16#FE0E/utf8>>]].

emoji_sequences_keep_two_cells_and_exact_copy_test_() ->
    Emoji = [<<16#2764/utf8, 16#FE0F/utf8>>, <<16#A9/utf8, 16#FE0F/utf8>>,
             <<16#263A/utf8, 16#FE0F/utf8>>,
             <<16#1F1F8/utf8, 16#1F1EA/utf8>>,
             <<16#1F468/utf8, 16#200D/utf8, 16#1F469/utf8, 16#200D/utf8,
               16#1F467/utf8, 16#200D/utf8, 16#1F466/utf8>>,
             <<16#1F469/utf8, 16#200D/utf8, 16#1F4BB/utf8>>,
             <<16#1F469/utf8, 16#1F3FD/utf8, 16#200D/utf8, 16#1F4BB/utf8>>,
             <<16#1F44D/utf8, 16#1F3FD/utf8>>,
             <<16#261D/utf8, 16#1F3FD/utf8>>,
             <<16#261D/utf8, 16#FE0F/utf8, 16#1F3FD/utf8>>,
             <<16#261D/utf8, 16#FE0F/utf8>>],
    Keycaps = [unicode:characters_to_binary([Base] ++ Selector ++ [16#20E3])
               || Base <- "0123456789#*", Selector <- [[], [16#FE0F]]],
    [?_test(assert_grapheme_cells(G, 2)) || G <- Emoji ++ Keycaps].

indic_source_copy_preserves_joiners_test() ->
    %% Indic shaping/width belongs to nit_unicode; viewer copy must not
    %% normalize vowel signs, viramas or joiners while laying out the source.
    Text = <<16#915/utf8, 16#93E/utf8, "\t", 16#915/utf8, 16#94D/utf8,
             16#200D/utf8, 16#937/utf8, "\r\n", 16#915/utf8, 16#93F/utf8>>,
    lists:foreach(fun(W) ->
        View = view(Text),
        ?assert(is_binary(output(View, b(W, 3)))),
        ?assertEqual({ok, Text}, nit_el_text_view:copy_text(View, all)),
        All = nit_el_text_view:key(View, {ctrl, $a}, b(W, 3)),
        ?assertEqual({ok, Text}, nit_el_text_view:copy_text(All, selection))
    end, [1, 2, 8]).

oversized_grapheme_replaced_not_split_test() ->
    Text = <<16#4E2D/utf8, "x">>,
    View = (view(Text))#text_view{show_scrollbar = true},
    Output = output(View, b(1, 2)),
    ?assertEqual(nomatch, binary:match(Output, <<16#4E2D/utf8>>)),
    ?assert(binary:match(Output, <<16#FFFD/utf8>>) =/= nomatch),
    ?assertEqual(nomatch, binary:match(Output, <<"█"/utf8>>)),
    ?assertEqual({ok, Text}, nit_el_text_view:copy_text(View, all)),
    ?assertEqual(1, (nit_el_text_view:mouse(View, press, 1, 2, b(1, 2)))#text_view.cursor_pos).

standalone_combining_mark_gets_safe_base_test() ->
    G = <<16#301/utf8>>,
    View = view(G),
    ?assert(binary:match(output(View, b(1, 1)), <<16#25CC/utf8, G/binary>>) =/= nomatch),
    ?assertEqual({ok, G}, nit_el_text_view:copy_text(View, all)).

tabs_use_eight_cell_stops_and_single_source_index_test() ->
    View = view(<<"a\tb">>),
    ?assertEqual([<<"a       b ">>], rows(View, b(10, 1))),
    lists:foreach(fun(Col) ->
        Click = nit_el_text_view:mouse(View, press, Col, 1, b(10, 1)),
        ?assertEqual(1, Click#text_view.cursor_pos)
    end, lists:seq(2, 8)),
    ClickB = nit_el_text_view:mouse(View, press, 9, 1, b(10, 1)),
    ?assertEqual(2, ClickB#text_view.cursor_pos),
    ?assertEqual([<<"a   ">>, <<"    ">>, <<"b   ">>], rows(View, b(4, 3))).

keyboard_vertical_page_and_home_end_test() ->
    Bounds = b(3, 2),
    View = (view(<<"abc\ndef\nghi\njkl\nmno">>))#text_view{cursor_pos = 1},
    Down = nit_el_text_view:key(View, {key, down}, Bounds),
    ?assertEqual(5, Down#text_view.cursor_pos),
    Page = nit_el_text_view:key(Down, {key, page_down}, Bounds),
    ?assertEqual({13, 2}, {Page#text_view.cursor_pos, Page#text_view.offset}),
    Back = nit_el_text_view:key(Page, {key, page_up}, Bounds),
    ?assertEqual({5, 1}, {Back#text_view.cursor_pos, Back#text_view.offset}),
    Up = nit_el_text_view:key(Back, {key, up}, Bounds),
    ?assertEqual({1, 0}, {Up#text_view.cursor_pos, Up#text_view.offset}),
    End = nit_el_text_view:key(Up, {key, 'end'}, Bounds),
    ?assertEqual(3, End#text_view.cursor_pos),
    ?assertEqual(0, (nit_el_text_view:key(End, {key, home}, Bounds))#text_view.cursor_pos).

vertical_movement_does_not_stick_at_soft_wrap_eof_test() ->
    View = (view(<<"abcdef">>))#text_view{cursor_pos = 6},
    Bounds = b(3, 2),
    Up = nit_el_text_view:key(View, {key, up}, Bounds),
    ?assertEqual(2, Up#text_view.cursor_pos),
    Down = nit_el_text_view:key(Up, {key, down}, Bounds),
    ?assertEqual(5, Down#text_view.cursor_pos),
    ?assertEqual(View, nit_el_text_view:key(View, {key, down}, Bounds)),
    First = View#text_view{cursor_pos = 0},
    ?assertEqual(First, nit_el_text_view:key(First, {key, up}, Bounds)).

shift_navigation_and_selection_collapse_test() ->
    Bounds = b(4, 2),
    View = (view(<<"abc\ndef\nghi">>))#text_view{cursor_pos = 1},
    Selected = keys(View, [{key, {shift, down}}, {key, {shift, 'end'}}], Bounds),
    ?assertEqual({1, 7}, {Selected#text_view.selection_anchor, Selected#text_view.cursor_pos}),
    ?assertEqual({ok, <<"bc\ndef">>}, nit_el_text_view:copy_text(Selected, selection)),
    Left = nit_el_text_view:key(Selected, {key, left}, Bounds),
    Right = nit_el_text_view:key(Selected, {key, right}, Bounds),
    ?assertEqual({1, undefined}, {Left#text_view.cursor_pos, Left#text_view.selection_anchor}),
    ?assertEqual({7, undefined}, {Right#text_view.cursor_pos, Right#text_view.selection_anchor}),
    All = nit_el_text_view:key(View, {ctrl, $a}, Bounds),
    ?assertEqual({0, 11, 1}, {All#text_view.selection_anchor, All#text_view.cursor_pos,
                            All#text_view.offset}).

shift_direction_variants_test_() ->
    [?_test(begin
        View = (view(<<"abc\ndef\nghi\njkl">>))#text_view{cursor_pos = 5},
        Selected = nit_el_text_view:key(View, {key, {shift, Dir}}, b(4, 2)),
        ?assertEqual(5, Selected#text_view.selection_anchor),
        ?assertEqual(Expected, Selected#text_view.cursor_pos),
        ?assertEqual(View#text_view.content, Selected#text_view.content)
    end) || {Dir, Expected} <- [{left, 4}, {right, 6}, {up, 1}, {down, 9},
                                {home, 4}, {'end', 7}, {page_up, 1}, {page_down, 13}]].

readonly_unknown_events_do_not_even_normalize_state_test_() ->
    View = (view(<<"abc">>))#text_view{cursor_pos = 99, selection_anchor = 1,
                                    offset = 42, copy_status = {ok, sent}},
    [?_assertEqual(View, nit_el_text_view:key(View, Event, b(2, 2)))
     || Event <- [$x, {key, $x}, {key, backspace}, {key, delete}, {key, enter},
                  {paste, <<"replacement">>}, {ctrl, $x}, {ctrl, $v}, {ctrl, $c},
                  {key, {shift, tab}}, {key, {ctrl, right}}, {key, escape},
                  {key, $y}, {key, $Y}]].

mouse_one_based_and_drag_autoscroll_test() ->
    Bounds = #bounds{x = 5, y = 7, width = 4, height = 2},
    View = view(<<"00\n11\n22\n33\n44\n55">>),
    ?assertEqual(View, nit_el_text_view:mouse(View, drag, 7, 10, Bounds)),
    Press = nit_el_text_view:mouse(View, press, 6, 8, Bounds),
    ?assertEqual({0, 0}, {Press#text_view.cursor_pos, Press#text_view.selection_anchor}),
    Drag = nit_el_text_view:mouse(Press, drag, 7, 10, Bounds),
    ?assertEqual({7, 1}, {Drag#text_view.cursor_pos, Drag#text_view.offset}),
    ?assertEqual({ok, <<"00\n11\n2">>}, nit_el_text_view:copy_text(Drag, selection)),
    Above = nit_el_text_view:mouse(Drag, drag, 7, 7, Bounds),
    ?assertEqual({1, 0}, {Above#text_view.cursor_pos, Above#text_view.offset}),
    Release = nit_el_text_view:mouse(Above, release, 8, 9, Bounds),
    ?assertEqual({ok, <<"00\n11">>}, nit_el_text_view:copy_text(Release, selection)),
    Far = nit_el_text_view:mouse(Release, drag, 100, 100, Bounds),
    ?assertEqual({17, 4}, {Far#text_view.cursor_pos, Far#text_view.offset}),
    ?assertEqual(View#text_view.content, Far#text_view.content).

mouse_outside_press_is_ignored_test() ->
    Bounds = #bounds{x = 2, y = 3, width = 4, height = 2},
    View = view(<<"abc">>),
    lists:foreach(fun({Col, Row}) ->
        ?assertEqual(View, nit_el_text_view:mouse(View, press, Col, Row, Bounds))
    end, [{2, 4}, {7, 4}, {3, 3}, {3, 6}]).

wheel_preserves_selection_and_clamps_test() ->
    View = (view(<<"a\nb\nc\nd\ne">>))#text_view{cursor_pos = 3, selection_anchor = 1,
                                              copy_status = {ok, sent}},
    Down = nit_el_text_view:scroll(View, down, 999, b(2, 2)),
    ?assertEqual(View#text_view{offset = 3}, Down),
    ?assertEqual(View, nit_el_text_view:scroll(Down, up, 999, b(2, 2))),
    ?assertEqual(Down, nit_el_text_view:scroll(Down, down, -4, b(2, 2))),
    Resized = nit_el_text_view:scroll(Down, down, 0, b(10, 10)),
    ?assertEqual(View, Resized).

resolved_bounds_apply_offsets_once_and_clamp_test() ->
    View = (view(<<"abcdefghijk">>))#text_view{x = 2, y = 1, width = 30, height = 20},
    Parent = #bounds{x = 4, y = 6, width = 8, height = 4},
    Bounds = nit_el_text_view:bounds(View, Parent),
    ?assertEqual(#bounds{x = 6, y = 7, width = 6, height = 3}, Bounds),
    ?assertEqual(6, nit_el_text_view:width(View, Parent)),
    ?assertEqual(3, nit_el_text_view:height(View, Parent)),
    Press = nit_el_text_view:mouse(View, press, 7, 8, Bounds),
    ?assertEqual(0, Press#text_view.cursor_pos),
    NextLine = nit_el_text_view:mouse(View, press, 7, 9, Bounds),
    ?assertEqual(6, NextLine#text_view.cursor_pos),
    Ansi = output(View, Parent),
    assert_cursor_moves_inside(Ansi, Bounds),
    Screen = nit_screen:from_ansi(Ansi, 14, 12),
    ?assertMatch({$a, _}, nit_screen:get_cell(Screen, 6, 7)),
    ?assertMatch({$g, _}, nit_screen:get_cell(Screen, 6, 8)),
    ?assertMatch({$\s, _}, nit_screen:get_cell(Screen, 5, 7)).

size_callbacks_and_resize_reflow_test() ->
    View = view(<<"abcdefghi">>),
    ?assertEqual({flex, 1}, nit_el_text_view:height(View, b(3, 10))),
    ?assertEqual(auto, nit_el_text_view:fixed_width(View)),
    ?assertEqual(7, nit_el_text_view:fixed_width(View#text_view{width = 7})),
    Auto = View#text_view{height = auto},
    ?assertEqual(3, nit_el_text_view:height(Auto, b(3, 10))),
    ?assertEqual(1, nit_el_text_view:height(Auto, b(9, 10))),
    ?assertEqual(4, nit_el_text_view:height(Auto#text_view{show_toolbar = true}, b(3, 10))),
    Stale = View#text_view{offset = 999, cursor_pos = 99, selection_anchor = 1},
    ?assertEqual([<<"abcdefghi">>], rows(Stale, b(9, 1))),
    Clamped = nit_el_text_view:key(Stale, {key, right}, b(9, 1)),
    ?assertEqual({9, 0}, {Clamped#text_view.cursor_pos, Clamped#text_view.offset}).

zero_and_tiny_allocations_test_() ->
    [?_test(begin
        View = #text_view{content = <<"abc\ndef">>, height = fill, offset = 99},
        Bounds = b(W, H),
        Ansi = output(View, Bounds),
        case W =:= 0 orelse H =:= 0 of
            true -> ?assertEqual(<<>>, Ansi);
            false -> assert_cursor_moves_inside(Ansi, Bounds)
        end,
        _ = nit_el_text_view:key(View, {key, down}, Bounds),
        _ = nit_el_text_view:scroll(View, down, 2, Bounds),
        ?assertEqual(View, nit_el_text_view:mouse(View, press, 1, H + 1, Bounds)),
        ?assertEqual(text, nit_el_text_view:hit_action(View, 1, H, Bounds))
    end) || {W, H} <- [{0, 0}, {0, 3}, {3, 0}, {1, 1}, {1, 2}, {2, 1}]].

hidden_and_offsets_outside_allocation_test() ->
    View = view(<<"abc">>),
    ?assertEqual(<<>>, output(View#text_view{visible = false}, b(8, 3))),
    Outside = View#text_view{x = 99, y = 99},
    ?assertEqual(#bounds{x = 8, y = 3, width = 0, height = 0},
                 nit_el_text_view:bounds(Outside, b(8, 3))),
    ?assertEqual(<<>>, output(Outside, b(8, 3))).

scrollbar_rewraps_and_matches_framework_glyphs_test() ->
    View = (view(<<"abcdefghi">>))#text_view{show_scrollbar = true},
    Bounds = b(4, 2),
    Screen = screen(View, Bounds, #{}),
    ?assertMatch({$c, _}, nit_screen:get_cell(Screen, 2, 0)),
    ?assertMatch({$█, _}, nit_screen:get_cell(Screen, 3, 0)),
    ?assertMatch({$░, _}, nit_screen:get_cell(Screen, 3, 1)),
    BarClick = nit_el_text_view:mouse(View, press, 4, 1, Bounds),
    ?assertEqual(View, BarClick),
    Next = nit_el_text_view:scroll(View, down, 1, Bounds),
    Scrolled = screen(Next, Bounds, #{}),
    ?assertMatch({$d, _}, nit_screen:get_cell(Scrolled, 0, 0)),
    ?assertMatch({$█, _}, nit_screen:get_cell(Scrolled, 3, 1)),
    Fit = View#text_view{content = <<"abcd">>},
    ?assertEqual(nomatch, binary:match(output(Fit, Bounds), <<"█"/utf8>>)).

toolbar_complete_label_hit_regions_test() ->
    View = #text_view{height = fill},
    lists:foreach(fun(W) ->
        Bounds = #bounds{x = 3, y = 4, width = W, height = 2},
        lists:foreach(fun(Local) ->
            Expected = if Local < 0; Local >= W -> text;
                          W >= 8, Local < 8 -> selection;
                          W >= 21, Local >= 9, Local < 21 -> all;
                          true -> text
                       end,
            ?assertEqual(Expected, nit_el_text_view:hit_action(View, Local + 4, 6, Bounds))
        end, lists:seq(-1, W)),
        ?assertEqual(text, nit_el_text_view:hit_action(View, 4, 5, Bounds)),
        Ansi = output(View, Bounds),
        assert_cursor_moves_inside(Ansi, Bounds),
        case W < 21 of
            true -> ?assertEqual(nomatch, binary:match(Ansi, <<"[Y Copy all]">>));
            false -> ?assert(binary:match(Ansi, <<"[y Copy] [Y Copy all]">>) =/= nomatch)
        end
    end, [1, 7, 8, 9, 19, 20, 21, 22, 60]),
    ?assertEqual(text, nit_el_text_view:hit_action(View#text_view{show_toolbar = false},
                                                1, 2, b(30, 2))),
    ?assertEqual(text, nit_el_text_view:hit_action(View#text_view{visible = false},
                                                1, 2, b(30, 2))).

toolbar_exact_painted_labels_and_spacing_test() ->
    View = #text_view{height = fill},
    Copy = <<"[y Copy]">>,
    All = <<"[Y Copy all]">>,
    ?assertEqual(8, byte_size(Copy)),
    ?assertEqual(12, byte_size(All)),
    lists:foreach(fun({W, Expected}) ->
        ?assertEqual([Expected], rows(View, b(W, 1)))
    end, [{7, <<"Ctrl-A ">>}, {8, Copy}, {9, <<Copy/binary, " ">>},
          {19, <<Copy/binary, " Ctrl-A all">>},
          {20, <<Copy/binary, " Ctrl-A all,">>},
          {21, <<Copy/binary, " ", All/binary>>},
          {22, <<Copy/binary, " ", All/binary, " ">>}]),
    %% One-based columns 9 and 22 are spacing, never copy targets.
    ?assertEqual(text, nit_el_text_view:hit_action(View, 9, 1, b(22, 1))),
    ?assertEqual(all, nit_el_text_view:hit_action(View, 21, 1, b(21, 1))),
    ?assertEqual(text, nit_el_text_view:hit_action(View, 22, 1, b(22, 1))).

unselected_ascii_is_rendered_in_bounded_runs_test() ->
    Text = binary:copy(<<"a">>, 80),
    Output = output(view(Text), b(80, 1)),
    ?assert(binary:match(Output, Text) =/= nomatch),
    ?assert(byte_size(Output) < 256).

small_render_does_not_write_outside_allocation_test_() ->
    [?_test(begin
        View = #text_view{content = <<"a\tb\n0123456789">>, height = fill,
                          cursor_pos = 99, selection_anchor = 0},
        Bounds = #bounds{x = 2, y = 2, width = W, height = H},
        Ansi = nit_el_text_view:render(View, Bounds, #{focused => true}),
        Screen = nit_screen:from_ansi(Ansi, W + 5, H + 5),
        lists:foreach(fun(Row) ->
            lists:foreach(fun(Col) ->
                case Col >= 2 andalso Col < W + 2 andalso Row >= 2 andalso Row < H + 2 of
                    true -> ok;
                    false -> ?assertEqual({$\s, #{}}, nit_screen:get_cell(Screen, Col, Row))
                end
            end, lists:seq(0, W + 4))
        end, lists:seq(0, H + 4))
    end) || {W, H} <- [{1, 1}, {1, 3}, {2, 2}, {7, 3}, {8, 3}, {20, 2}, {21, 2}]].

toolbar_press_does_not_move_text_selection_test() ->
    View = #text_view{content = <<"abc">>, height = fill, cursor_pos = 2, selection_anchor = 0},
    ?assertEqual(View, nit_el_text_view:mouse(View, press, 2, 2, b(30, 2))),
    ?assertEqual(selection, nit_el_text_view:hit_action(View, 2, 2, b(30, 2))).

toolbar_status_test_() ->
    [?_test(begin
        View = #text_view{height = fill, copy_status = Status},
        Ansi = output(View, b(110, 1)),
        ?assert(binary:match(Ansi, Expected) =/= nomatch),
        ?assert(binary:match(Ansi, <<"Ctrl-A all, Shift-arrows select">>) =/= nomatch),
        ?assertEqual(nomatch, binary:match(Ansi, <<"Copied">>))
    end) || {Status, Expected} <-
        [{idle, <<"[y Copy] [Y Copy all]">>},
         {{ok, sent}, <<"Sent to terminal (clipboard unverified)">>},
         {{error, disabled}, <<"Clipboard disabled">>},
         {{error, too_large}, <<"Too large; select less">>},
         {{error, invalid_text}, <<"Invalid UTF-8 text">>},
         {{error, unavailable}, <<"Clipboard unavailable">>},
         {{error, write_failed}, <<"Terminal write failed">>},
         {{error, no_selection}, <<"No selection">>}]].

selection_and_visible_cursor_styles_test() ->
    View = (view(<<"abcd">>))#text_view{selection_anchor = 1, cursor_pos = 3,
                                      selection_style = #{bg => red, fg => white}},
    Screen = screen(View, b(5, 1), #{focused => true}),
    {$b, SelectionStyle} = nit_screen:get_cell(Screen, 1, 0),
    ?assertEqual(red, maps:get(bg, SelectionStyle)),
    {$d, CursorStyle} = nit_screen:get_cell(Screen, 3, 0),
    ?assertEqual(true, maps:get(reverse, CursorStyle)),
    ?assertEqual(true, maps:get(underline, CursorStyle)),
    Unfocused = screen(View, b(5, 1), #{}),
    {$d, PlainStyle} = nit_screen:get_cell(Unfocused, 3, 0),
    ?assertNot(maps:get(reverse, PlainStyle, false)).

eof_cursor_on_full_and_empty_rows_test() ->
    View = (view(<<"abc">>))#text_view{cursor_pos = 3},
    Screen = screen(View, b(3, 1), #{focused => true}),
    {$c, Style} = nit_screen:get_cell(Screen, 2, 0),
    ?assertEqual(true, maps:get(reverse, Style)),
    Empty = screen(view(<<>>), b(1, 1), #{focused => true}),
    {$\s, EmptyStyle} = nit_screen:get_cell(Empty, 0, 0),
    ?assertEqual(true, maps:get(reverse, EmptyStyle)),
    assert_cursor_moves_inside(iolist_to_binary(nit_el_text_view:render(View, b(3, 1),
                                                                      #{focused => true})), b(3, 1)).

selected_newline_has_visible_cell_test() ->
    View = (view(<<"a\r\nb">>))#text_view{selection_anchor = 1, cursor_pos = 2},
    Screen = screen(View, b(3, 2), #{}),
    {$\s, Style} = nit_screen:get_cell(Screen, 1, 0),
    ?assertEqual(blue, maps:get(bg, Style)),
    ?assertEqual({ok, <<"\r\n">>}, nit_el_text_view:copy_text(View, selection)).

controls_are_sanitized_but_copy_is_exact_test() ->
    Text = unicode:characters_to_binary([0, 7, 8, 11, 12, 27, $[, $2, $J,
                                         127, 16#85, 16#9B, 16#202E, $x,
                                         27, $], $5, $2, $;, $c, $;, $Q, $Q, $=, $=, 7]),
    View = view(Text),
    Ansi = output(View, b(80, 2)),
    Plain = re:replace(Ansi, <<"\e(?:\\[[0-9;]*[A-Za-z]|\\([A-Za-z])">>, <<>>,
                       [global, {return, binary}]),
    lists:foreach(fun(C) ->
        ?assertEqual(nomatch, binary:match(Plain, unicode:characters_to_binary([C])))
    end, [0, 7, 8, 11, 12, 27, 127, 16#85, 16#9B, 16#202E]),
    ?assert(binary:match(Plain, <<16#FFFD/utf8>>) =/= nomatch),
    ?assertEqual({ok, Text}, nit_el_text_view:copy_text(View, all)),
    All = nit_el_text_view:key(View, {ctrl, $a}, b(80, 2)),
    ?assertEqual({ok, Text}, nit_el_text_view:copy_text(All, selection)).

merge_preserves_only_native_state_for_identical_content_test() ->
    Old = (view(<<"abc">>))#text_view{cursor_pos = 2, selection_anchor = 1, offset = 3,
                                    copy_status = {ok, sent}, style = #{fg => red}},
    New = (view(<<"abc">>))#text_view{id = replacement, width = 20, style = #{fg => green},
                                    selection_style = #{bg => yellow}, show_toolbar = true},
    Expected = New#text_view{cursor_pos = 2, selection_anchor = 1, offset = 3,
                             copy_status = {ok, sent}},
    ?assertEqual(Expected, nit_el_text_view:merge(Old, New)),
    Changed = New#text_view{content = <<"different">>, cursor_pos = 77,
                            selection_anchor = 55, offset = 88, copy_status = {error, too_large}},
    ?assertEqual(Changed#text_view{cursor_pos = 0, selection_anchor = undefined,
                                  offset = 0, copy_status = idle},
                 nit_el_text_view:merge(Old, Changed)).

large_source_layout_and_copy_test_() ->
    {timeout, 15, fun() ->
        Text = binary:copy(<<"abcdefg\r\n">>, 12000),
        View = view(Text),
        All = nit_el_text_view:key(View, {ctrl, $a}, b(40, 5)),
        ?assertEqual(96000, All#text_view.cursor_pos),
        ?assertEqual(11996, All#text_view.offset),
        ?assertEqual({ok, Text}, nit_el_text_view:copy_text(All, selection)),
        %% Clipboard size enforcement is not part of this source-copy API.
        ?assertEqual({ok, Text}, nit_el_text_view:copy_text(View, all)),
        ?assert(byte_size(output(All, b(40, 5))) < 10000)
    end}.

assert_grapheme_cells(G, Width) ->
    Text = <<G/binary, "b">>,
    View = view(Text),
    Bounds = b(Width + 1, 2),
    lists:foreach(fun(Col) ->
        Click = nit_el_text_view:mouse(View, press, Col, 1, Bounds),
        ?assertEqual(0, Click#text_view.cursor_pos)
    end, lists:seq(1, Width)),
    ClickB = nit_el_text_view:mouse(View, press, Width + 1, 1, Bounds),
    ?assertEqual(1, ClickB#text_view.cursor_pos),
    SelectB = nit_el_text_view:key(ClickB, {key, {shift, right}}, Bounds),
    ?assertEqual({ok, <<"b">>}, nit_el_text_view:copy_text(SelectB, selection)),
    SelectG = nit_el_text_view:key(View, {key, {shift, right}}, Bounds),
    ?assertEqual({ok, G}, nit_el_text_view:copy_text(SelectG, selection)),
    ?assertEqual({ok, Text}, nit_el_text_view:copy_text(SelectG, all)),
    All = nit_el_text_view:key(View, {ctrl, $a}, Bounds),
    ?assertEqual(2, All#text_view.cursor_pos),
    ?assertEqual({ok, Text}, nit_el_text_view:copy_text(All, selection)),
    ?assert(binary:match(output(View, b(Width, 2)), G) =/= nomatch),
    ?assertEqual(1, nit_el_text_view:height(View#text_view{height = auto}, Bounds)),
    ?assertEqual(2, nit_el_text_view:height(View#text_view{height = auto}, b(Width, 2))),
    WrappedB = nit_el_text_view:mouse(View, press, 1, 2, b(Width, 2)),
    ?assertEqual(1, WrappedB#text_view.cursor_pos).

view(Content) ->
    #text_view{content = Content, height = fill, show_toolbar = false, show_scrollbar = false}.

b(W, H) -> #bounds{width = W, height = H}.

keys(View, Events, Bounds) ->
    lists:foldl(fun(Event, Acc) -> nit_el_text_view:key(Acc, Event, Bounds) end, View, Events).

output(View, Bounds) -> iolist_to_binary(nit_el_text_view:render(View, Bounds, #{})).

screen(View, Bounds, Opts) ->
    nit_screen:from_ansi(nit_el_text_view:render(View, Bounds, Opts),
                         Bounds#bounds.width, Bounds#bounds.height).

rows(View, Bounds) ->
    Screen = screen(View, Bounds, #{}),
    [unicode:characters_to_binary([element(1, nit_screen:get_cell(Screen, Col, Row))
                                  || Col <- lists:seq(0, Bounds#bounds.width - 1)])
     || Row <- lists:seq(0, Bounds#bounds.height - 1)].

assert_cursor_moves_inside(Ansi, #bounds{x = X, y = Y, width = W, height = H}) ->
    case re:run(Ansi, <<"\e\\[([0-9]+);([0-9]+)H">>, [global, {capture, all_but_first, binary}]) of
        nomatch -> ?assertEqual(<<>>, Ansi);
        {match, Matches} ->
            lists:foreach(fun([RowBin, ColBin]) ->
                Row = binary_to_integer(RowBin) - 1,
                Col = binary_to_integer(ColBin) - 1,
                ?assert(Row >= Y andalso Row < Y + H),
                ?assert(Col >= X andalso Col < X + W)
            end, Matches)
    end.