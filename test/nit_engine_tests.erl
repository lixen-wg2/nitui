%%%-------------------------------------------------------------------
%%% @doc Unit tests for shared engine behavior.
%%% @end
%%%-------------------------------------------------------------------
-module(nit_engine_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("nitui/include/nit_elements.hrl").

tree_nodes() ->
    [#tree_node{id = N, label = integer_to_binary(N)} || N <- lists:seq(1, 5)].

root_bounds() ->
    #bounds{x = 0, y = 0, width = 40, height = 4}.

scroll_content_height_accounts_for_scrollbar_wrap_test() ->
    Bounds = #bounds{width = 5, height = 2},
    Text = #text{content = <<"abcdefghijklmnopTAIL">>, wrap = true},
    Scroll = #scroll{id = log_scroll, children = [Text]},
    ?assertEqual(5, nit_engine:scroll_content_height(Scroll, Bounds)),
    ?assertEqual(4, nit_engine:scroll_content_height(
                      Scroll#scroll{show_scrollbar = false}, Bounds)),
    %% Content that fits at full width must not acquire a scrollbar.
    ?assertEqual(4, nit_engine:scroll_content_height(Scroll, Bounds#bounds{height = 4})),
    ?assertEqual(20, nit_engine:scroll_content_height(Scroll, Bounds#bounds{width = 1})),
    ?assertEqual(6, nit_engine:scroll_content_height(
                      Scroll#scroll{children = [Text, #text{height = fill}]}, Bounds)),
    ?assertEqual(0, nit_engine:scroll_content_height(Scroll#scroll{children = []}, Bounds)).

scroll_page_down_reaches_final_wrapped_line_test() ->
    Bounds = #bounds{width = 5, height = 2},
    Scroll = #scroll{id = log_scroll, height = fill, focusable = true, children = [
        #vbox{children = [#text{content = <<"abcdefghijklmnopTAIL">>, wrap = true}]}
    ]},
    Root = #vbox{children = [Scroll]},
    {ok, Page1, unchanged} =
        nit_engine:page_navigate_element(down, log_scroll, Root, Bounds, ?MODULE, unchanged),
    ?assertMatch(#scroll{offset = 2}, nit_focus:find_element(Page1, log_scroll)),
    {ok, Page2, unchanged} =
        nit_engine:page_navigate_element(down, log_scroll, Page1, Bounds, ?MODULE, unchanged),
    ?assertMatch(#scroll{offset = 3}, nit_focus:find_element(Page2, log_scroll)),
    Screen = nit_screen:from_ansi(nit_render:render(Page2, Bounds), 5, 2),
    Tail = unicode:characters_to_binary([
        Char || Col <- lists:seq(0, 3), {Char, _} <- [nit_screen:get_cell(Screen, Col, 1)]
    ]),
    ?assertEqual(<<"TAIL">>, Tail),
    ?assertEqual({ok, Page2, unchanged},
                 nit_engine:page_navigate_element(down, log_scroll, Page2, Bounds, ?MODULE, unchanged)),
    {ok, PageUp, unchanged} =
        nit_engine:page_navigate_element(up, log_scroll, Page2, Bounds, ?MODULE, unchanged),
    ?assertMatch(#scroll{offset = 1}, nit_focus:find_element(PageUp, log_scroll)).

scroll_target_element_returns_tree_test() ->
    Tree = #tree{id = nav_tree, focusable = true, nodes = tree_nodes()},
    ?assertEqual({tree, nav_tree}, nit_engine:scroll_target_element(Tree, nav_tree)).

navigate_tree_uses_resolved_layout_height_test() ->
    TreeEl = #tree{
        id = nav_tree,
        height = fill,
        selected = 1,
        nodes = tree_nodes()
    },
    Root = #vbox{children = [
        #text{content = <<"Header">>},
        TreeEl
    ]},
    Navigated = nit_engine:navigate_tree(down, 3, TreeEl, Root, root_bounds()),
    ?assertEqual(4, Navigated#tree.selected),
    ?assertEqual(1, Navigated#tree.offset).

scroll_tree_uses_resolved_layout_height_without_selecting_test() ->
    TreeEl = #tree{
        id = nav_tree,
        height = fill,
        selected = 1,
        nodes = tree_nodes()
    },
    Root = #vbox{children = [
        #text{content = <<"Header">>},
        TreeEl
    ]},
    Scrolled = nit_engine:scroll_tree(down, 3, TreeEl, Root, root_bounds()),
    ?assertEqual(1, Scrolled#tree.selected),
    ?assertEqual(2, Scrolled#tree.offset).

move_input_cursor_with_shift_marks_range_test() ->
    Tree = #input{id = search, value = <<"abc">>, cursor_pos = 1},
    {ok, NewTree} = nit_engine:move_input_cursor(Tree, search, right, true),
    ?assertEqual(2, NewTree#input.cursor_pos),
    ?assertEqual(1, NewTree#input.selection_anchor).

typing_replaces_marked_input_range_test() ->
    Tree = #input{id = search, value = <<"abc">>, cursor_pos = 2,
                  selection_anchor = 0},
    {ok, NewTree, search, <<"Xc">>} = nit_engine:apply_char_input(Tree, search, $X),
    ?assertEqual(1, NewTree#input.cursor_pos),
    ?assertEqual(undefined, NewTree#input.selection_anchor).

backspace_deletes_marked_input_range_test() ->
    Tree = #input{id = search, value = <<"abc">>, cursor_pos = 2,
                  selection_anchor = 0},
    {ok, NewTree, search, <<"c">>} = nit_engine:apply_backspace(Tree, search),
    ?assertEqual(0, NewTree#input.cursor_pos),
    ?assertEqual(undefined, NewTree#input.selection_anchor).

delete_deletes_marked_input_range_test() ->
    Tree = #input{id = search, value = <<"abc">>, cursor_pos = 2,
                  selection_anchor = 0},
    {ok, NewTree, search, <<"c">>} = nit_engine:apply_delete_input(Tree, search),
    ?assertEqual(0, NewTree#input.cursor_pos),
    ?assertEqual(undefined, NewTree#input.selection_anchor).

select_all_input_marks_whole_value_test() ->
    Tree = #input{id = search, value = <<"abc">>, cursor_pos = 1},
    {ok, NewTree} = nit_engine:select_all_input(Tree, search),
    ?assertEqual(3, NewTree#input.cursor_pos),
    ?assertEqual(0, NewTree#input.selection_anchor).
