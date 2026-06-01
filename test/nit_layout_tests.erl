%%%-------------------------------------------------------------------
%%% @doc Unit tests for nit_layout module.
%%%
%%% Tests layout calculation functions including:
%%% - element_height/2 for various element types
%%% - element_width/2 for various element types
%%% - element_fixed_width/1 for hbox layout
%%% @end
%%%-------------------------------------------------------------------
-module(nit_layout_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("nitui/include/nit_elements.hrl").

%%====================================================================
%% Test helpers
%%====================================================================

default_bounds() ->
    #bounds{x = 0, y = 0, width = 80, height = 24}.

%%====================================================================
%% element_height tests
%%====================================================================

height_text_test() ->
    Element = #text{content = <<"Hello">>},
    ?assertEqual(1, nit_layout:element_height(Element, default_bounds())).

height_wrapped_text_uses_available_width_test() ->
    Bounds = #bounds{x = 0, y = 0, width = 4, height = 24},
    Element = #text{content = <<"abcdefghi">>, wrap = true},
    ?assertEqual(3, nit_layout:element_height(Element, Bounds)).

height_wrapped_empty_text_is_one_line_test() ->
    Bounds = #bounds{x = 0, y = 0, width = 4, height = 24},
    Element = #text{content = <<>>, wrap = true},
    ?assertEqual(1, nit_layout:element_height(Element, Bounds)).

height_button_test() ->
    Element = #button{label = <<"Click">>},
    ?assertEqual(1, nit_layout:element_height(Element, default_bounds())).

height_input_test() ->
    Element = #input{value = <<"test">>},
    ?assertEqual(1, nit_layout:element_height(Element, default_bounds())).

height_box_auto_test() ->
    Element = #box{height = auto, children = []},
    Bounds = default_bounds(),
    ?assertEqual(Bounds#bounds.height, nit_layout:element_height(Element, Bounds)).

height_box_fixed_test() ->
    Element = #box{height = 10, children = []},
    ?assertEqual(10, nit_layout:element_height(Element, default_bounds())).

height_vbox_empty_test() ->
    Element = #vbox{children = []},
    %% Empty vbox has minimum height of 1
    ?assertEqual(1, nit_layout:element_height(Element, default_bounds())).

height_vbox_with_children_test() ->
    Element = #vbox{children = [
        #text{content = <<"Line 1">>},
        #text{content = <<"Line 2">>},
        #text{content = <<"Line 3">>}
    ], spacing = 0},
    ?assertEqual(3, nit_layout:element_height(Element, default_bounds())).

height_vbox_with_spacing_test() ->
    Element = #vbox{children = [
        #text{content = <<"Line 1">>},
        #text{content = <<"Line 2">>}
    ], spacing = 1},
    %% 2 children + 1 spacing between them = 3
    ?assertEqual(3, nit_layout:element_height(Element, default_bounds())).

height_table_auto_test() ->
    Element = #table{height = auto, rows = [
        [<<"Row 1">>],
        [<<"Row 2">>],
        [<<"Row 3">>]
    ]},
    Bounds = default_bounds(),
    %% Default table is borderless with a header separator, so auto height is rows + 2
    Expected = min(3 + 2, Bounds#bounds.height),
    ?assertEqual(Expected, nit_layout:element_height(Element, Bounds)).

height_bordered_table_auto_test() ->
    Element = #table{
        height = auto,
        border = single,
        rows = [[<<"Row 1">>], [<<"Row 2">>]]
    },
    Bounds = default_bounds(),
    %% Top + bottom border + header + separator + rows
    Expected = min(2 + 4, Bounds#bounds.height),
    ?assertEqual(Expected, nit_layout:element_height(Element, Bounds)).

height_table_fixed_test() ->
    Element = #table{height = 15, rows = []},
    ?assertEqual(15, nit_layout:element_height(Element, default_bounds())).

height_table_fill_test() ->
    Element = #table{height = fill, border = single, rows = [[<<"Row 1">>]]},
    ?assertEqual({flex, 5}, nit_layout:element_height(Element, default_bounds())).

height_non_tuple_test() ->
    ?assertEqual(1, nit_layout:element_height(not_a_tuple, default_bounds())).

%%====================================================================
%% element_width tests
%%====================================================================

width_text_test() ->
    Element = #text{content = <<"Hello">>},
    ?assertEqual(5, nit_layout:element_width(Element, default_bounds())).

width_button_auto_test() ->
    Element = #button{label = <<"OK">>, width = auto},
    %% auto width adds horizontal padding around the label
    ?assertEqual(6, nit_layout:element_width(Element, default_bounds())).

width_button_fixed_test() ->
    Element = #button{label = <<"OK">>, width = 20},
    ?assertEqual(20, nit_layout:element_width(Element, default_bounds())).

width_input_auto_test() ->
    Element = #input{width = auto},
    %% auto width defaults to 20
    ?assertEqual(20, nit_layout:element_width(Element, default_bounds())).

width_input_fixed_test() ->
    Element = #input{width = 30},
    ?assertEqual(30, nit_layout:element_width(Element, default_bounds())).

width_box_auto_test() ->
    Element = #box{width = auto, children = []},
    Bounds = default_bounds(),
    ?assertEqual(Bounds#bounds.width, nit_layout:element_width(Element, Bounds)).

width_box_fixed_test() ->
    Element = #box{width = 40, children = []},
    ?assertEqual(40, nit_layout:element_width(Element, default_bounds())).

width_non_tuple_test() ->
    ?assertEqual(1, nit_layout:element_width(not_a_tuple, default_bounds())).

%%====================================================================
%% element_fixed_width tests
%%====================================================================

fixed_width_text_test() ->
    Element = #text{content = <<"Hello">>},
    %% Text returns its content length as fixed width
    ?assertEqual(5, nit_layout:element_fixed_width(Element)).

fixed_width_wrapped_text_is_auto_test() ->
    Element = #text{content = <<"Hello">>, wrap = true},
    ?assertEqual(auto, nit_layout:element_fixed_width(Element)).

fixed_width_button_auto_test() ->
    Element = #button{label = <<"Click">>, width = auto},
    %% auto width adds horizontal padding around the label
    ?assertEqual(9, nit_layout:element_fixed_width(Element)).

fixed_width_button_fixed_test() ->
    Element = #button{label = <<"Click">>, width = 20},
    ?assertEqual(20, nit_layout:element_fixed_width(Element)).

fixed_width_input_auto_test() ->
    Element = #input{width = auto},
    ?assertEqual(20, nit_layout:element_fixed_width(Element)).

fixed_width_input_fixed_test() ->
    Element = #input{width = 30},
    ?assertEqual(30, nit_layout:element_fixed_width(Element)).

fixed_width_box_auto_test() ->
    Element = #box{width = auto, children = []},
    ?assertEqual(auto, nit_layout:element_fixed_width(Element)).

fixed_width_box_fixed_test() ->
    Element = #box{width = 50, children = []},
    ?assertEqual(50, nit_layout:element_fixed_width(Element)).

fixed_width_vbox_test() ->
    Element = #vbox{children = []},
    ?assertEqual(auto, nit_layout:element_fixed_width(Element)).

fixed_width_non_tuple_test() ->
    ?assertEqual(auto, nit_layout:element_fixed_width(not_a_tuple)).

%%====================================================================
%% Layout helper tests
%%====================================================================

calculate_vbox_heights_ignores_absolute_parent_y_test() ->
    Bounds = #bounds{x = 1, y = 11, width = 20, height = 6},
    Children = [
        #text{content = <<"Top">>},
        #spacer{},
        #text{content = <<"Bottom">>}
    ],
    ?assertEqual([1, 4, 1], nit_layout:calculate_vbox_heights(Children, Bounds, 0, 0)).

calculate_hbox_widths_split_auto_children_evenly_test() ->
    Bounds = #bounds{x = 0, y = 0, width = 20, height = 4},
    Children = [
        #box{children = []},
        #box{children = []}
    ],
    ?assertEqual([10, 10], nit_layout:calculate_hbox_widths(Children, Bounds, 0)).

calculate_hbox_widths_respect_local_x_offset_test() ->
    Bounds = #bounds{x = 0, y = 0, width = 20, height = 4},
    Children = [
        #box{children = []},
        #box{children = []}
    ],
    ?assertEqual([9, 9], nit_layout:calculate_hbox_widths(Children, Bounds, 0, 2)).
