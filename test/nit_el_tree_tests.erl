%%%-------------------------------------------------------------------
%%% @doc Unit tests for nit_el_tree module.
%%%
%%% Tests tree element rendering including:
%%% - Basic rendering with nodes
%%% - Nested/hierarchical trees
%%% - Expand/collapse behavior
%%% - Tree line prefixes (Unicode box-drawing characters)
%%% - Selection highlighting
%%% - Height calculation
%%% @end
%%%-------------------------------------------------------------------
-module(nit_el_tree_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("nitui/include/nit_elements.hrl").

%%====================================================================
%% Test fixtures
%%====================================================================

simple_tree() ->
    #tree{
        id = test_tree,
        nodes = [
            #tree_node{id = node1, label = <<"Node 1">>},
            #tree_node{id = node2, label = <<"Node 2">>},
            #tree_node{id = node3, label = <<"Node 3">>}
        ]
    }.

nested_tree() ->
    #tree{
        id = test_tree,
        nodes = [
            #tree_node{
                id = parent,
                label = <<"Parent">>,
                expanded = true,
                children = [
                    #tree_node{id = child1, label = <<"Child 1">>},
                    #tree_node{id = child2, label = <<"Child 2">>}
                ]
            }
        ]
    }.

collapsed_tree() ->
    #tree{
        id = test_tree,
        nodes = [
            #tree_node{
                id = parent,
                label = <<"Parent">>,
                expanded = false,
                children = [
                    #tree_node{id = child1, label = <<"Child 1">>},
                    #tree_node{id = child2, label = <<"Child 2">>}
                ]
            }
        ]
    }.

deep_tree() ->
    #tree{
        id = test_tree,
        indent = 2,
        show_lines = true,
        nodes = [
            #tree_node{
                id = level0,
                label = <<"Level 0">>,
                expanded = true,
                children = [
                    #tree_node{
                        id = level1,
                        label = <<"Level 1">>,
                        expanded = true,
                        children = [
                            #tree_node{id = level2, label = <<"Level 2">>}
                        ]
                    }
                ]
            }
        ]
    }.

bounds() ->
    #bounds{x = 1, y = 1, width = 80, height = 24}.

%%====================================================================
%% Render tests
%%====================================================================

render_empty_tree_test() ->
    Tree = #tree{id = empty_tree, nodes = []},
    Output = nit_el_tree:render(Tree, bounds(), #{}),
    ?assertEqual([], Output).

render_invisible_tree_test() ->
    Tree = simple_tree(),
    InvisibleTree = Tree#tree{visible = false},
    Output = nit_el_tree:render(InvisibleTree, bounds(), #{}),
    ?assertEqual([], Output).

render_simple_tree_produces_output_test() ->
    Tree = simple_tree(),
    Output = nit_el_tree:render(Tree, bounds(), #{}),
    %% Should produce non-empty iolist
    ?assert(iolist_size(Output) > 0).

render_nested_tree_produces_output_test() ->
    Tree = nested_tree(),
    Output = nit_el_tree:render(Tree, bounds(), #{}),
    %% Should produce non-empty iolist
    ?assert(iolist_size(Output) > 0).

render_deep_tree_with_unicode_lines_test() ->
    %% This test specifically checks that Unicode box-drawing characters
    %% are handled correctly (the bug that was fixed)
    Tree = deep_tree(),
    Output = nit_el_tree:render(Tree, bounds(), #{}),
    %% Should produce non-empty iolist without crashing
    ?assert(iolist_size(Output) > 0),
    %% Convert to binary to verify it's valid
    Binary = iolist_to_binary(Output),
    ?assert(byte_size(Binary) > 0).

render_tree_with_icons_test() ->
    Tree = #tree{
        id = icon_tree,
        nodes = [
            #tree_node{id = n1, label = <<"Server">>, icon = <<"[S]">>},
            #tree_node{id = n2, label = <<"Worker">>, icon = <<"[W]">>}
        ]
    },
    Output = nit_el_tree:render(Tree, bounds(), #{}),
    Binary = iolist_to_binary(Output),
    %% Should contain the icons
    ?assert(binary:match(Binary, <<"[S]">>) =/= nomatch),
    ?assert(binary:match(Binary, <<"[W]">>) =/= nomatch).

render_tree_with_string_icons_test() ->
    Tree = #tree{
        id = string_icon_tree,
        nodes = [
            #tree_node{id = n1, label = "Supervisor", icon = "[S]"},
            #tree_node{id = n2, label = "Worker", icon = "[W]"}
        ]
    },
    Output = nit_el_tree:render(Tree, bounds(), #{}),
    Binary = iolist_to_binary(Output),
    ?assert(binary:match(Binary, <<"[S]">>) =/= nomatch),
    ?assert(binary:match(Binary, <<"[W]">>) =/= nomatch).

render_tree_with_emoji_icons_test() ->
    Tree = #tree{
        id = emoji_tree,
        nodes = [
            #tree_node{id = n1, label = <<"Supervisor">>, icon = <<"🌳"/utf8>>},
            #tree_node{id = n2, label = <<"Worker">>, icon = <<"🔧"/utf8>>}
        ]
    },
    Output = nit_el_tree:render(Tree, bounds(), #{}),
    Binary = iolist_to_binary(Output),
    ?assert(binary:match(Binary, <<"🌳"/utf8>>) =/= nomatch),
    ?assert(binary:match(Binary, <<"🔧"/utf8>>) =/= nomatch).

render_tree_with_selection_test() ->
    Tree = simple_tree(),
    SelectedTree = Tree#tree{selected = node2},
    Output = nit_el_tree:render(SelectedTree, bounds(), #{}),
    ?assert(iolist_size(Output) > 0).

render_tree_respects_fixed_height_test() ->
    Tree = simple_tree(),
    Output = nit_el_tree:render(Tree#tree{height = 2}, bounds(), #{}),
    Binary = iolist_to_binary(Output),
    ?assert(binary:match(Binary, <<"Node 1">>) =/= nomatch),
    ?assert(binary:match(Binary, <<"Node 2">>) =/= nomatch),
    ?assertEqual(nomatch, binary:match(Binary, <<"Node 3">>)).

render_collapsed_tree_uses_explicit_indicator_test() ->
    Output = nit_el_tree:render(collapsed_tree(), bounds(), #{}),
    Binary = iolist_to_binary(Output),
    ?assert(binary:match(Binary, <<"[+] ">>) =/= nomatch).

%%====================================================================
%% Height calculation tests
%%====================================================================

height_empty_tree_test() ->
    Tree = #tree{id = empty, nodes = []},
    ?assertEqual(0, nit_el_tree:height(Tree, bounds())).

height_simple_tree_test() ->
    Tree = simple_tree(),
    %% 3 nodes = height 3
    ?assertEqual(3, nit_el_tree:height(Tree, bounds())).

height_nested_expanded_tree_test() ->
    Tree = nested_tree(),
    %% 1 parent + 2 children = height 3
    ?assertEqual(3, nit_el_tree:height(Tree, bounds())).

height_collapsed_tree_test() ->
    Tree = collapsed_tree(),
    %% Only parent visible when collapsed = height 1
    ?assertEqual(1, nit_el_tree:height(Tree, bounds())).

height_deep_tree_test() ->
    Tree = deep_tree(),
    %% level0 + level1 + level2 = height 3
    ?assertEqual(3, nit_el_tree:height(Tree, bounds())).

height_fill_tree_test() ->
    Tree = #tree{id = fill_tree, height = fill, nodes = []},
    ?assertEqual({flex, 1}, nit_el_tree:height(Tree, bounds())).

%%====================================================================
%% Width calculation tests
%%====================================================================

width_auto_uses_bounds_test() ->
    Tree = #tree{id = t, width = auto, nodes = []},
    Bounds = #bounds{x = 1, y = 1, width = 100, height = 24},
    ?assertEqual(100, nit_el_tree:width(Tree, Bounds)).

width_fixed_ignores_bounds_test() ->
    Tree = #tree{id = t, width = 50, nodes = []},
    Bounds = #bounds{x = 1, y = 1, width = 100, height = 24},
    ?assertEqual(50, nit_el_tree:width(Tree, Bounds)).

fixed_width_returns_width_test() ->
    Tree = #tree{id = t, width = 42, nodes = []},
    ?assertEqual(42, nit_el_tree:fixed_width(Tree)).

fixed_width_auto_test() ->
    Tree = #tree{id = t, width = auto, nodes = []},
    ?assertEqual(auto, nit_el_tree:fixed_width(Tree)).

%%====================================================================
%% Tree line prefix tests (Unicode box-drawing)
%%====================================================================

render_with_show_lines_true_test() ->
    Tree = #tree{
        id = lines_tree,
        show_lines = true,
        indent = 2,
        nodes = [
            #tree_node{
                id = parent,
                label = <<"Parent">>,
                expanded = true,
                children = [
                    #tree_node{id = child, label = <<"Child">>}
                ]
            }
        ]
    },
    Output = nit_el_tree:render(Tree, bounds(), #{}),
    Binary = iolist_to_binary(Output),
    %% Should contain Unicode box-drawing characters
    ?assert(binary:match(Binary, <<"└">>) =/= nomatch orelse
            binary:match(Binary, <<"├">>) =/= nomatch).

render_with_show_lines_false_test() ->
    Tree = #tree{
        id = no_lines_tree,
        show_lines = false,
        indent = 2,
        nodes = [
            #tree_node{
                id = parent,
                label = <<"Parent">>,
                expanded = true,
                children = [
                    #tree_node{id = child, label = <<"Child">>}
                ]
            }
        ]
    },
    Output = nit_el_tree:render(Tree, bounds(), #{}),
    Binary = iolist_to_binary(Output),
    %% Should NOT contain Unicode box-drawing characters
    ?assertEqual(nomatch, binary:match(Binary, <<"└">>)),
    ?assertEqual(nomatch, binary:match(Binary, <<"├">>)).

%%====================================================================
%% Multiple indent levels test
%%====================================================================

render_various_indent_levels_test() ->
    %% Test different indent values to ensure Unicode handling works
    lists:foreach(
        fun(Indent) ->
            Tree = #tree{
                id = indent_tree,
                indent = Indent,
                show_lines = true,
                nodes = [
                    #tree_node{
                        id = p,
                        label = <<"P">>,
                        expanded = true,
                        children = [
                            #tree_node{id = c, label = <<"C">>}
                        ]
                    }
                ]
            },
            Output = nit_el_tree:render(Tree, bounds(), #{}),
            ?assert(iolist_size(Output) > 0)
        end,
        [1, 2, 3, 4, 5, 8]
    ).
