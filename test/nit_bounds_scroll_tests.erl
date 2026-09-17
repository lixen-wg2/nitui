-module(nit_bounds_scroll_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("nitui/include/nit_elements.hrl").

scroll_stacks_children_with_flex_heights_test() ->
    Bounds = #bounds{width = 40, height = 5},
    Scroll = #scroll{id = scroll, children = [#text{height = 2}, tree(fill)]},
    ?assertEqual({ok, #bounds{y = 2, width = 40, height = 3}},
                 nit_bounds:find_element_bounds(Scroll, tree, Bounds)).

scroll_offsets_preserve_child_render_height_test_() ->
    [?_test(begin
        Bounds = #bounds{x = 3, y = 4, width = 40, height = 5},
        Scroll = #scroll{offset = Offset, children = [#text{height = 4}, tree(3)]},
        Expected = #bounds{x = 3, y = 8 - SafeOffset, width = 39, height = 3},
        ?assertEqual({ok, Expected}, nit_bounds:find_element_bounds(Scroll, tree, Bounds)),
        %% The scroll renderer lays the child out at full height even when clipped.
        Parent = self(),
        RenderChild = fun(Child, ChildBounds, Opts) ->
            case Child of
                #tree{} -> Parent ! {tree_bounds, ChildBounds};
                _ -> ok
            end,
            nit_element:render(Child, ChildBounds, Opts)
        end,
        nit_el_scroll:render(Scroll, Bounds, #{render_child => RenderChild}),
        receive
            {tree_bounds, RenderBounds} ->
                ?assertEqual(Expected#bounds.height, RenderBounds#bounds.height),
                ?assertEqual(Expected#bounds.width, RenderBounds#bounds.width)
        after 0 -> error(tree_not_rendered)
        end
    end) || {Offset, SafeOffset} <- [{-3, 0}, {0, 0}, {1, 1}, {2, 2}, {99, 2}]].

scroll_remeasures_wrapped_content_after_reserving_bar_test() ->
    Bounds = #bounds{width = 10, height = 5},
    Scroll = #scroll{offset = 99, children = [
        #text{wrap = true, content = <<"12345678901234567890">>}, tree(4)]},
    ?assertEqual({9, 7}, nit_el_scroll:content_size(Scroll, Bounds)),
    ?assertEqual({ok, #bounds{y = 1, width = 9, height = 4}},
                 nit_bounds:find_element_bounds(Scroll, tree, Bounds)).

nested_vbox_local_offsets_and_spacing_test() ->
    Bounds = #bounds{x = 2, y = 3, width = 40, height = 6},
    Scroll = #scroll{offset = 1, children = [#text{height = 2},
        #vbox{x = 1, y = 1, spacing = 1, children = [#text{height = 1}, tree(fill)]}]},
    %% Content measures 8 rows; the flex-containing vbox is then measured again
    %% against that content height, just as in the scroll renderer.
    ?assertEqual({ok, #bounds{x = 3, y = 7, width = 39, height = 5}},
                 nit_bounds:find_element_bounds(Scroll, tree, Bounds)).

tree(Height) ->
    #tree{id = tree, height = Height,
          nodes = [#tree_node{id = N} || N <- lists:seq(1, 30)]}.