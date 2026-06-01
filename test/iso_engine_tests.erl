%%%-------------------------------------------------------------------
%%% @doc Unit tests for shared engine behavior.
%%% @end
%%%-------------------------------------------------------------------
-module(iso_engine_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("nitui/include/iso_elements.hrl").

tree_nodes() ->
    [#tree_node{id = N, label = integer_to_binary(N)} || N <- lists:seq(1, 5)].

root_bounds() ->
    #bounds{x = 0, y = 0, width = 40, height = 4}.

scroll_target_element_returns_tree_test() ->
    Tree = #tree{id = nav_tree, focusable = true, nodes = tree_nodes()},
    ?assertEqual({tree, nav_tree}, iso_engine:scroll_target_element(Tree, nav_tree)).

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
    Navigated = iso_engine:navigate_tree(down, 3, TreeEl, Root, root_bounds()),
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
    Scrolled = iso_engine:scroll_tree(down, 3, TreeEl, Root, root_bounds()),
    ?assertEqual(1, Scrolled#tree.selected),
    ?assertEqual(2, Scrolled#tree.offset).

move_input_cursor_with_shift_marks_range_test() ->
    Tree = #input{id = search, value = <<"abc">>, cursor_pos = 1},
    {ok, NewTree} = iso_engine:move_input_cursor(Tree, search, right, true),
    ?assertEqual(2, NewTree#input.cursor_pos),
    ?assertEqual(1, NewTree#input.selection_anchor).

typing_replaces_marked_input_range_test() ->
    Tree = #input{id = search, value = <<"abc">>, cursor_pos = 2,
                  selection_anchor = 0},
    {ok, NewTree, search, <<"Xc">>} = iso_engine:apply_char_input(Tree, search, $X),
    ?assertEqual(1, NewTree#input.cursor_pos),
    ?assertEqual(undefined, NewTree#input.selection_anchor).

backspace_deletes_marked_input_range_test() ->
    Tree = #input{id = search, value = <<"abc">>, cursor_pos = 2,
                  selection_anchor = 0},
    {ok, NewTree, search, <<"c">>} = iso_engine:apply_backspace(Tree, search),
    ?assertEqual(0, NewTree#input.cursor_pos),
    ?assertEqual(undefined, NewTree#input.selection_anchor).

delete_deletes_marked_input_range_test() ->
    Tree = #input{id = search, value = <<"abc">>, cursor_pos = 2,
                  selection_anchor = 0},
    {ok, NewTree, search, <<"c">>} = iso_engine:apply_delete_input(Tree, search),
    ?assertEqual(0, NewTree#input.cursor_pos),
    ?assertEqual(undefined, NewTree#input.selection_anchor).

select_all_input_marks_whole_value_test() ->
    Tree = #input{id = search, value = <<"abc">>, cursor_pos = 1},
    {ok, NewTree} = iso_engine:select_all_input(Tree, search),
    ?assertEqual(3, NewTree#input.cursor_pos),
    ?assertEqual(0, NewTree#input.selection_anchor).
