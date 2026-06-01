%%%-------------------------------------------------------------------
%%% @doc Unit tests for input rendering.
%%% @end
%%%-------------------------------------------------------------------
-module(iso_el_input_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("nitui/include/iso_elements.hrl").

selection_range_is_highlighted_test() ->
    Input = #input{
        id = search,
        value = <<"abc">>,
        width = 5,
        cursor_pos = 2,
        selection_anchor = 1
    },
    Bounds = #bounds{x = 0, y = 0, width = 5, height = 1},
    Screen = iso_screen:from_ansi(iso_el_input:render(Input, Bounds, #{focused => true}), 5, 1),
    {Char, Style} = iso_screen:get_cell(Screen, 2, 0),
    ?assertEqual($b, Char),
    ?assertEqual(blue, maps:get(bg, Style)),
    ?assertEqual(white, maps:get(fg, Style)).
