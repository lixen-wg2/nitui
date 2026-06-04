%%%-------------------------------------------------------------------
%%% @doc Tests that verify demo views render correctly
%%% @end
%%%-------------------------------------------------------------------
-module(nit_demo_render_tests).

-include_lib("eunit/include/eunit.hrl").
-include("nit_elements.hrl").

%% Test bounds
-define(BOUNDS, #bounds{x = 0, y = 0, width = 80, height = 24}).

%% Test that scroll element renders correctly
scroll_render_test() ->
    Tree = #scroll{
        id = test_scroll,
        height = 5,
        children = [
            #vbox{children = [
                #text{content = <<"Line 1">>},
                #text{content = <<"Line 2">>},
                #text{content = <<"Line 3">>},
                #text{content = <<"Line 4">>},
                #text{content = <<"Line 5">>},
                #text{content = <<"Line 6">>},
                #text{content = <<"Line 7">>}
            ]}
        ]
    },
    Output = nit_render:render(Tree, ?BOUNDS),
    ?assert(is_list(Output) orelse is_binary(Output)),
    FlatOutput = iolist_to_binary(Output),
    ?assert(byte_size(FlatOutput) > 0),
    %% Should contain Line 1 through Line 5 (visible in viewport)
    ?assert(binary:match(FlatOutput, <<"Line 1">>) =/= nomatch).

%% Test that list element renders correctly
list_render_test() ->
    Tree = #list{
        id = test_list,
        items = [<<"Item 1">>, <<"Item 2">>, <<"Item 3">>],
        selected = 1,
        height = 5
    },
    Output = nit_render:render(Tree, ?BOUNDS),
    ?assert(is_list(Output) orelse is_binary(Output)),
    FlatOutput = iolist_to_binary(Output),
    ?assert(byte_size(FlatOutput) > 0),
    %% Should contain all items
    ?assert(binary:match(FlatOutput, <<"Item 1">>) =/= nomatch),
    ?assert(binary:match(FlatOutput, <<"Item 2">>) =/= nomatch),
    ?assert(binary:match(FlatOutput, <<"Item 3">>) =/= nomatch).

%% Test list with tuple items
list_tuple_items_test() ->
    Tree = #list{
        id = test_list,
        items = [{id1, <<"First">>}, {id2, <<"Second">>}],
        selected = 0,
        height = 3
    },
    Output = nit_render:render(Tree, ?BOUNDS),
    FlatOutput = iolist_to_binary(Output),
    ?assert(binary:match(FlatOutput, <<"First">>) =/= nomatch),
    ?assert(binary:match(FlatOutput, <<"Second">>) =/= nomatch).

list_selection_does_not_shift_item_text_test() ->
    Bounds = #bounds{x = 0, y = 0, width = 12, height = 3},
    Tree = #list{
        id = test_list,
        items = [<<"Dashboard">>, <<"Processes">>, <<"Network">>],
        selected = 1,
        height = 3,
        selected_style = #{bg => blue, fg => white}
    },
    Screen = nit_screen:from_ansi(nit_render:render(Tree, Bounds), 12, 3),
    ?assertEqual(<<"Dashboard   ">>, row_text(Screen, 12, 0)),
    ?assertEqual(<<"Processes   ">>, row_text(Screen, 12, 1)),
    ?assertEqual(<<"Network     ">>, row_text(Screen, 12, 2)).

two_level_borderless_box_does_not_shift_list_children_test() ->
    Bounds = #bounds{x = 0, y = 0, width = 12, height = 3},
    Tree = #box{
        id = menu_box,
        border = none,
        focusable = true,
        children = [
            #list{
                id = menu_list,
                items = [<<"First">>, <<"Second">>],
                selected = 0,
                height = 2
            }
        ]
    },
    Screen = nit_screen:from_ansi(
        nit_render:render_two_level(Tree, Bounds, menu_box, menu_list),
        12,
        3),
    ?assertEqual(<<"First       ">>, row_text(Screen, 12, 0)),
    ?assertEqual(<<"Second      ">>, row_text(Screen, 12, 1)).

text_wrap_uses_render_bounds_width_test() ->
    Bounds = #bounds{x = 0, y = 0, width = 6, height = 3},
    Tree = #text{content = <<"abcdefghij">>, wrap = true},
    Screen = nit_screen:from_ansi(nit_render:render(Tree, Bounds), 6, 3),
    ?assertEqual(<<"abcdef">>, row_text(Screen, 6, 0)),
    ?assertEqual(<<"ghij  ">>, row_text(Screen, 6, 1)).

%% Test scroll with offset
scroll_with_offset_test() ->
    Tree = #scroll{
        id = test_scroll,
        height = 3,
        offset = 2,
        children = [
            #vbox{children = [
                #text{content = <<"Line 1">>},
                #text{content = <<"Line 2">>},
                #text{content = <<"Line 3">>},
                #text{content = <<"Line 4">>},
                #text{content = <<"Line 5">>}
            ]}
        ]
    },
    Output = nit_render:render(Tree, ?BOUNDS),
    FlatOutput = iolist_to_binary(Output),
    ?assert(byte_size(FlatOutput) > 0).

scroll_clips_nested_children_to_viewport_test() ->
    Bounds = #bounds{x = 0, y = 0, width = 12, height = 3},
    Tree = #scroll{
        id = clipped_scroll,
        height = 3,
        children = [
            #vbox{children = [
                #text{content = <<"Line 1">>},
                #text{content = <<"Line 2">>},
                #text{content = <<"Line 3">>},
                #text{content = <<"Line 4">>},
                #text{content = <<"Line 5">>}
            ]}
        ]
    },
    Screen = nit_screen:from_ansi(nit_render:render(Tree, Bounds), 12, 5),
    ?assertEqual(<<"Line 1      ">>, row_text(Screen, 12, 0)),
    ?assertEqual(<<"Line 2      ">>, row_text(Screen, 12, 1)),
    ?assertEqual(<<"Line 3      ">>, row_text(Screen, 12, 2)),
    ?assertEqual(<<"            ">>, row_text(Screen, 12, 3)).

scroll_offset_applies_with_nested_vbox_children_test() ->
    Bounds = #bounds{x = 0, y = 0, width = 12, height = 3},
    Tree = #scroll{
        id = offset_scroll,
        height = 3,
        offset = 2,
        children = [
            #vbox{children = [
                #text{content = <<"Line 1">>},
                #text{content = <<"Line 2">>},
                #text{content = <<"Line 3">>},
                #text{content = <<"Line 4">>},
                #text{content = <<"Line 5">>}
            ]}
        ]
    },
    Screen = nit_screen:from_ansi(nit_render:render(Tree, Bounds), 12, 4),
    ?assertEqual(<<"Line 3      ">>, row_text(Screen, 12, 0)),
    ?assertEqual(<<"Line 4      ">>, row_text(Screen, 12, 1)),
    ?assertEqual(<<"Line 5      ">>, row_text(Screen, 12, 2)).

scroll_hides_invisible_vbox_when_clipped_test() ->
    %% Regression: render_clipped_child used to bypass the visible=false
    %% short-circuit when a #vbox{} sat directly inside a #scroll{} and
    %% was partially outside the viewport. The hidden vbox would then
    %% render anyway. Drive the offset so the vbox straddles the
    %% viewport edge and assert no content leaks through.
    Bounds = #bounds{x = 0, y = 0, width = 12, height = 3},
    Tree = #scroll{
        id = hidden_scroll,
        height = 3,
        offset = 1,
        children = [
            #vbox{visible = false, children = [
                #text{content = <<"Hidden 1">>},
                #text{content = <<"Hidden 2">>},
                #text{content = <<"Hidden 3">>},
                #text{content = <<"Hidden 4">>},
                #text{content = <<"Hidden 5">>}
            ]}
        ]
    },
    Screen = nit_screen:from_ansi(nit_render:render(Tree, Bounds), 12, 3),
    ?assertEqual(<<"            ">>, row_text(Screen, 12, 0)),
    ?assertEqual(<<"            ">>, row_text(Screen, 12, 1)),
    ?assertEqual(<<"            ">>, row_text(Screen, 12, 2)).

scroll_offset_counts_wrapped_text_lines_test() ->
    Bounds = #bounds{x = 0, y = 0, width = 4, height = 2},
    Tree = #scroll{
        id = wrapped_scroll,
        height = 2,
        offset = 1,
        show_scrollbar = false,
        children = [
            #vbox{children = [
                #text{content = <<"abcdefghi">>, wrap = true}
            ]}
        ]
    },
    Screen = nit_screen:from_ansi(nit_render:render(Tree, Bounds), 4, 2),
    ?assertEqual(<<"efgh">>, row_text(Screen, 4, 0)),
    ?assertEqual(<<"i   ">>, row_text(Screen, 4, 1)).

%% Test list in a box container
list_in_box_test() ->
    Tree = #box{
        id = container,
        title = <<"Menu">>,
        width = 30,
        height = 8,
        children = [
            #list{
                id = menu,
                items = [<<"Option 1">>, <<"Option 2">>, <<"Option 3">>],
                selected = 0,
                height = 5
            }
        ]
    },
    Output = nit_render:render(Tree, ?BOUNDS),
    FlatOutput = iolist_to_binary(Output),
    %% Check that list items are rendered
    ?assert(binary:match(FlatOutput, <<"Option 1">>) =/= nomatch).

%% Test empty list
empty_list_test() ->
    Tree = #list{
        id = empty_list,
        items = [],
        selected = 0,
        height = 3
    },
    Output = nit_render:render(Tree, ?BOUNDS),
    ?assert(is_list(Output) orelse is_binary(Output)).

%% Test scroll with no children
empty_scroll_test() ->
    Tree = #scroll{
        id = empty_scroll,
        height = 5,
        children = []
    },
    Output = nit_render:render(Tree, ?BOUNDS),
    ?assert(is_list(Output) orelse is_binary(Output)).

unicode_status_bar_render_test() ->
    Tree = #status_bar{
        items = [
            {<<"H">>, <<"Home">>},
            {"↑/↓", <<"Navigate">>}
        ]
    },
    Output = nit_render:render(Tree, ?BOUNDS),
    FlatOutput = iolist_to_binary(Output),
    ?assert(binary:match(FlatOutput, <<"↑/↓"/utf8>>) =/= nomatch),
    ?assert(binary:match(FlatOutput, <<"Navigate">>) =/= nomatch).

table_diff_redraw_matches_full_render_test() ->
    Bounds = #bounds{x = 0, y = 0, width = 32, height = 8},
    Rows = [
        [<<"<0.1.0>">>, <<"very-long-process-name-driving-width">>, <<"99999">>],
        [<<"<0.2.0>">>, <<"a">>, <<"2">>],
        [<<"<0.3.0>">>, <<"b">>, <<"3">>],
        [<<"<0.4.0>">>, <<"c">>, <<"4">>],
        [<<"<0.5.0>">>, <<"selected-before-scroll">>, <<"5">>],
        [<<"<0.6.0>">>, <<"x">>, <<"6">>]
    ],
    Columns = [
        #table_col{id = pid, header = <<"PID">>},
        #table_col{id = name, header = <<"Name">>},
        #table_col{id = mem, header = <<"Mem">>, align = right}
    ],
    OldTable = #table{
        id = proc_table,
        width = 32,
        height = 7,
        border = none,
        show_header = true,
        columns = Columns,
        rows = Rows,
        selected_row = 5,
        scroll_offset = 0
    },
    NewTable = OldTable#table{selected_row = 6, scroll_offset = 1},
    OldAnsi = nit_el_table:render(OldTable, Bounds, #{focused => false}),
    NewAnsi = nit_el_table:render(NewTable, Bounds, #{focused => false}),
    OldScreen = nit_screen:from_ansi(OldAnsi, 32, 8),
    NewScreen = nit_screen:from_ansi(NewAnsi, 32, 8),
    AppliedDiffScreen = nit_screen:from_ansi(
        [OldAnsi, nit_screen:diff(OldScreen, NewScreen)], 32, 8),
    assert_screens_equal(AppliedDiffScreen, NewScreen, 32, 8).

list_diff_redraw_clears_previous_selection_styles_test() ->
    Bounds = #bounds{x = 0, y = 0, width = 18, height = 4},
    BaseList = #list{
        id = menu_list,
        items = [<<"Dashboard">>, <<"Processes">>, <<"Network">>, <<"ETS">>],
        height = 4,
        selected_style = #{bg => blue, fg => white, bold => true}
    },
    OldList = BaseList#list{selected = 0},
    MidList = BaseList#list{selected = 1},
    NewList = BaseList#list{selected = 2},
    OldAnsi = nit_el_list:render(OldList, Bounds, #{}),
    MidAnsi = nit_el_list:render(MidList, Bounds, #{}),
    NewAnsi = nit_el_list:render(NewList, Bounds, #{}),
    OldScreen = nit_screen:from_ansi(OldAnsi, 18, 4),
    MidScreen = nit_screen:from_ansi(MidAnsi, 18, 4),
    NewScreen = nit_screen:from_ansi(NewAnsi, 18, 4),
    AppliedDiffScreen = nit_screen:from_ansi(
        [OldAnsi, nit_screen:diff(OldScreen, MidScreen), nit_screen:diff(MidScreen, NewScreen)],
        18, 4),
    assert_screens_equal(AppliedDiffScreen, NewScreen, 18, 4).

screen_diff_identical_screens_is_empty_test() ->
    Screen = nit_screen:new(8, 2),
    ?assertEqual([], nit_screen:diff(Screen, Screen)).

screen_diff_coalesces_adjacent_cell_updates_test() ->
    OldScreen = nit_screen:new(8, 1),
    NewScreen = nit_screen:put_string(OldScreen, 0, 0, <<"abc">>, #{}),
    Diff = iolist_to_binary(nit_screen:diff(OldScreen, NewScreen)),
    ?assert(binary:match(Diff, <<"\e[1;1H">>) =/= nomatch),
    ?assertEqual(nomatch, binary:match(Diff, <<"\e[1;2H">>)),
    ?assertEqual(nomatch, binary:match(Diff, <<"\e[1;3H">>)).

%% Visual test - prints rendered output for inspection
visual_widgets_test_() ->
    {timeout, 10, fun() ->
        %% Create a simple list + scroll layout similar to demo_widgets
        Tree = #vbox{children = [
            #text{content = <<"=== Widget Demo Test ===">>},
            #hbox{spacing = 2, children = [
                #vbox{children = [
                    #text{content = <<"Menu:">>},
                    #list{
                        id = menu,
                        items = [<<"Dashboard">>, <<"Processes">>, <<"Network">>],
                        selected = 1,
                        height = 3
                    }
                ]},
                #vbox{children = [
                    #text{content = <<"Logs:">>},
                    #scroll{
                        id = logs,
                        height = 3,
                        children = [
                            #vbox{children = [
                                #text{content = <<"[INFO] Started">>},
                                #text{content = <<"[DEBUG] Loading">>},
                                #text{content = <<"[INFO] Ready">>}
                            ]}
                        ]
                    }
                ]}
            ]}
        ]},
        Output = nit_render:render(Tree, ?BOUNDS),
        FlatOutput = iolist_to_binary(Output),
        %% Verify key content is present
        ?assert(binary:match(FlatOutput, <<"Widget Demo">>) =/= nomatch),
        ?assert(binary:match(FlatOutput, <<"Dashboard">>) =/= nomatch),
        ?assert(binary:match(FlatOutput, <<"Processes">>) =/= nomatch),
        ?assert(binary:match(FlatOutput, <<"INFO">>) =/= nomatch),
        %% Print for visual inspection (visible in verbose test output)
        io:format("~n~nRendered output:~n~s~n", [FlatOutput])
    end}.

assert_screens_equal(Left, Right, Width, Height) ->
    lists:foreach(
        fun(Row) ->
            lists:foreach(
                fun(Col) ->
                    ?assertEqual(
                        nit_screen:get_cell(Right, Col, Row),
                        nit_screen:get_cell(Left, Col, Row))
                end,
                lists:seq(0, Width - 1))
        end,
        lists:seq(0, Height - 1)).

row_text(Screen, Width, Row) ->
    iolist_to_binary([
        cell_char(nit_screen:get_cell(Screen, Col, Row))
        || Col <- lists:seq(0, Width - 1)
    ]).

cell_char({Char, _Style}) when is_integer(Char) ->
    unicode:characters_to_binary([Char]);
cell_char({Char, _Style}) when is_binary(Char) ->
    Char.
