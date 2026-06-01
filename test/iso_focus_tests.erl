%%%-------------------------------------------------------------------
%%% @doc Unit tests for iso_focus module.
%%%
%%% Tests focus management including:
%%% - Container collection (box, tabs, table)
%%% - Children collection within containers
%%% - Focus navigation (next/prev with wrap-around)
%%% - Element finding by ID
%%% @end
%%%-------------------------------------------------------------------
-module(iso_focus_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("nitui/include/iso_elements.hrl").

%%====================================================================
%% next_focus tests
%%====================================================================

next_focus_empty_list_test() ->
    ?assertEqual(undefined, iso_focus:next_focus([], foo)).

next_focus_undefined_current_test() ->
    ?assertEqual(a, iso_focus:next_focus([a, b, c], undefined)).

next_focus_first_to_second_test() ->
    ?assertEqual(b, iso_focus:next_focus([a, b, c], a)).

next_focus_middle_to_next_test() ->
    ?assertEqual(c, iso_focus:next_focus([a, b, c], b)).

next_focus_wrap_around_test() ->
    ?assertEqual(a, iso_focus:next_focus([a, b, c], c)).

next_focus_not_found_returns_first_test() ->
    ?assertEqual(a, iso_focus:next_focus([a, b, c], unknown)).

%%====================================================================
%% prev_focus tests
%%====================================================================

prev_focus_empty_list_test() ->
    ?assertEqual(undefined, iso_focus:prev_focus([], foo)).

prev_focus_undefined_current_test() ->
    ?assertEqual(c, iso_focus:prev_focus([a, b, c], undefined)).

prev_focus_last_to_middle_test() ->
    ?assertEqual(b, iso_focus:prev_focus([a, b, c], c)).

prev_focus_middle_to_first_test() ->
    ?assertEqual(a, iso_focus:prev_focus([a, b, c], b)).

prev_focus_wrap_around_test() ->
    ?assertEqual(c, iso_focus:prev_focus([a, b, c], a)).

prev_focus_not_found_returns_last_test() ->
    ?assertEqual(c, iso_focus:prev_focus([a, b, c], unknown)).

%%====================================================================
%% collect_containers tests
%%====================================================================

collect_containers_empty_vbox_test() ->
    Tree = #vbox{children = []},
    ?assertEqual([], iso_focus:collect_containers(Tree)).

collect_containers_focusable_box_test() ->
    Tree = #box{id = my_box, focusable = true, children = []},
    ?assertEqual([my_box], iso_focus:collect_containers(Tree)).

collect_containers_non_focusable_box_test() ->
    Tree = #box{id = my_box, focusable = false, children = []},
    ?assertEqual([], iso_focus:collect_containers(Tree)).

collect_containers_box_without_id_test() ->
    Tree = #box{focusable = true, children = []},
    ?assertEqual([], iso_focus:collect_containers(Tree)).

collect_containers_focusable_tabs_test() ->
    Tree = #tabs{id = my_tabs, focusable = true, tabs = []},
    ?assertEqual([my_tabs], iso_focus:collect_containers(Tree)).

collect_containers_focusable_table_test() ->
    Tree = #table{id = my_table, focusable = true},
    ?assertEqual([my_table], iso_focus:collect_containers(Tree)).

collect_containers_focusable_tree_test() ->
    Tree = #tree{id = my_tree, focusable = true, nodes = []},
    ?assertEqual([my_tree], iso_focus:collect_containers(Tree)).

collect_containers_focusable_scroll_test() ->
    Tree = #scroll{id = my_scroll, focusable = true, children = []},
    ?assertEqual([my_scroll], iso_focus:collect_containers(Tree)).

collect_containers_non_focusable_tree_test() ->
    Tree = #tree{id = my_tree, focusable = false, nodes = []},
    ?assertEqual([], iso_focus:collect_containers(Tree)).

collect_containers_tree_in_vbox_test() ->
    Tree = #vbox{children = [
        #tree{id = tree1, focusable = true, nodes = []},
        #text{content = <<"ignored">>}
    ]},
    ?assertEqual([tree1], iso_focus:collect_containers(Tree)).

collect_containers_nested_in_vbox_test() ->
    Tree = #vbox{children = [
        #box{id = box1, focusable = true, children = []},
        #table{id = table1, focusable = true},
        #text{content = <<"ignored">>}
    ]},
    ?assertEqual([box1, table1], iso_focus:collect_containers(Tree)).

collect_containers_nested_in_hbox_test() ->
    Tree = #hbox{children = [
        #tabs{id = tabs1, focusable = true, tabs = []},
        #box{id = box1, focusable = true, children = []}
    ]},
    ?assertEqual([tabs1, box1], iso_focus:collect_containers(Tree)).

collect_containers_deeply_nested_test() ->
    Tree = #vbox{children = [
        #hbox{children = [
            #panel{children = [
                #box{id = deep_box, focusable = true, children = []}
            ]}
        ]}
    ]},
    ?assertEqual([deep_box], iso_focus:collect_containers(Tree)).

%%====================================================================
%% collect_children tests
%%====================================================================

collect_children_box_with_buttons_test() ->
    Tree = #box{id = my_box, focusable = true, children = [
        #button{id = btn1, focusable = true},
        #button{id = btn2, focusable = true},
        #text{content = <<"not focusable">>}
    ]},
    ?assertEqual([btn1, btn2], iso_focus:collect_children(Tree, my_box)).

collect_children_box_with_inputs_test() ->
    Tree = #box{id = my_box, focusable = true, children = [
        #input{id = input1, focusable = true},
        #input{id = input2, focusable = true}
    ]},
    ?assertEqual([input1, input2], iso_focus:collect_children(Tree, my_box)).

collect_children_box_with_table_test() ->
    Tree = #box{id = my_box, focusable = true, children = [
        #table{id = table1, focusable = true}
    ]},
    ?assertEqual([table1], iso_focus:collect_children(Tree, my_box)).

collect_children_box_with_scroll_test() ->
    Tree = #box{id = my_box, focusable = true, children = [
        #scroll{id = scroll1, focusable = true}
    ]},
    ?assertEqual([scroll1], iso_focus:collect_children(Tree, my_box)).

collect_children_tabs_returns_tab_ids_test() ->
    Tree = #tabs{id = my_tabs, focusable = true, tabs = [
        #tab{id = tab1, label = <<"Tab 1">>},
        #tab{id = tab2, label = <<"Tab 2">>},
        #tab{id = tab3, label = <<"Tab 3">>}
    ]},
    ?assertEqual([tab1, tab2, tab3], iso_focus:collect_children(Tree, my_tabs)).

collect_children_unknown_container_test() ->
    Tree = #vbox{children = []},
    ?assertEqual([], iso_focus:collect_children(Tree, unknown_id)).

collect_children_nested_in_vbox_test() ->
    Tree = #box{id = my_box, focusable = true, children = [
        #vbox{children = [
            #button{id = btn1, focusable = true},
            #button{id = btn2, focusable = true}
        ]}
    ]},
    ?assertEqual([btn1, btn2], iso_focus:collect_children(Tree, my_box)).

%%====================================================================
%% find_element tests
%%====================================================================

find_element_button_test() ->
    Tree = #vbox{children = [
        #button{id = my_button, label = <<"Click">>}
    ]},
    Result = iso_focus:find_element(Tree, my_button),
    ?assertEqual(my_button, Result#button.id).

find_element_input_test() ->
    Tree = #vbox{children = [
        #input{id = my_input, value = <<"test">>}
    ]},
    Result = iso_focus:find_element(Tree, my_input),
    ?assertEqual(my_input, Result#input.id).

find_element_table_test() ->
    Tree = #vbox{children = [
        #table{id = my_table, columns = []}
    ]},
    Result = iso_focus:find_element(Tree, my_table),
    ?assertEqual(my_table, Result#table.id).

find_element_tabs_test() ->
    Tree = #tabs{id = my_tabs, tabs = []},
    Result = iso_focus:find_element(Tree, my_tabs),
    ?assertEqual(my_tabs, Result#tabs.id).

find_element_box_test() ->
    Tree = #box{id = my_box, children = []},
    Result = iso_focus:find_element(Tree, my_box),
    ?assertEqual(my_box, Result#box.id).

find_element_not_found_test() ->
    Tree = #vbox{children = []},
    ?assertEqual(undefined, iso_focus:find_element(Tree, unknown)).

find_element_nested_in_box_test() ->
    Tree = #box{id = outer, children = [
        #button{id = nested_btn, label = <<"Nested">>}
    ]},
    Result = iso_focus:find_element(Tree, nested_btn),
    ?assertEqual(nested_btn, Result#button.id).

find_element_deeply_nested_test() ->
    Tree = #vbox{children = [
        #hbox{children = [
            #panel{children = [
                #box{id = outer, children = [
                    #input{id = deep_input, value = <<"deep">>}
                ]}
            ]}
        ]}
    ]},
    Result = iso_focus:find_element(Tree, deep_input),
    ?assertEqual(deep_input, Result#input.id).

find_element_in_tabs_content_test() ->
    Tree = #tabs{id = my_tabs, active_tab = tab1, tabs = [
        #tab{id = tab1, label = <<"Tab 1">>, content = [
            #button{id = tab_button, label = <<"In Tab">>}
        ]}
    ]},
    Result = iso_focus:find_element(Tree, tab_button),
    ?assertEqual(tab_button, Result#button.id).

find_element_tree_test() ->
    Tree = #tree{id = my_tree, nodes = []},
    Result = iso_focus:find_element(Tree, my_tree),
    ?assertEqual(my_tree, Result#tree.id).

find_element_tree_in_vbox_test() ->
    Tree = #vbox{children = [
        #tree{id = nested_tree, nodes = []}
    ]},
    Result = iso_focus:find_element(Tree, nested_tree),
    ?assertEqual(nested_tree, Result#tree.id).

%%====================================================================
%% find_container tests
%%====================================================================

find_container_button_in_tabs_content_test() ->
    Tree = #tabs{
        id = top_tabs,
        focusable = true,
        active_tab = tab1,
        tabs = [
            #tab{
                id = tab1,
                label = <<"Tab 1">>,
                content = [#button{id = tab_btn, label = <<"Click">>}]
            }
        ]
    },
    ?assertEqual(top_tabs, iso_focus:find_container(Tree, tab_btn)).

find_container_skips_unrelated_tabs_branch_test() ->
    Tree = #vbox{children = [
        #tabs{
            id = tabs1,
            focusable = true,
            active_tab = first,
            tabs = [#tab{id = first, label = <<"First">>, content = []}]
        },
        #box{
            id = actions_box,
            focusable = true,
            children = [#button{id = save_btn, label = <<"Save">>}]
        }
    ]},
    ?assertEqual(actions_box, iso_focus:find_container(Tree, save_btn)).
