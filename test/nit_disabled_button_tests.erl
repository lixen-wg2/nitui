-module(nit_disabled_button_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("nitui/include/nit_elements.hrl").

-export([view/1, handle_event/2]).

view(#{tree := Tree}) ->
    Tree.

handle_event(Event, State = #{events := Events, event_ref := Ref}) ->
    %% Observe delivery even if a callback result is discarded by the server.
    self() ! {Ref, Event},
    Logged = State#{events := [Event | Events]},
    case {Event, maps:get(replacement, State, undefined)} of
        {{click, first, _}, {tree, Tree}} ->
            {noreply, maps:remove(replacement, Logged#{tree := Tree})};
        {{click, first, _}, {modal, Modal}} ->
            {modal, Modal, maps:remove(replacement, Logged)};
        _ ->
            {noreply, Logged}
    end.

defaults_test() ->
    ?assertEqual(true, (#button{})#button.enabled),
    ?assertEqual(#{fg => bright_black, dim => true}, (#button{})#button.disabled_style).

disabled_style_overrides_focus_hover_and_base_test_() ->
    [?_test(begin
        Button = (button(first, 0))#button{enabled = false,
            style = #{fg => green, bg => blue},
            focused_style = #{fg => red, bg => red, bold => true, underline => true}},
        Opts = #{focused => Focused, hovered => Hovered,
                 base_style => #{fg => white, dim => false}},
        Output = nit_el_button:render(Button, #bounds{}, Opts),
        ?assertEqual({$f, #{fg => bright_black, bg => blue, dim => true}},
                     nit_screen:get_cell(screen(Output), 2, 0)),
        ?assertEqual(nit_el_button:width(Button#button{enabled = true}, #bounds{}),
                     nit_el_button:width(Button, #bounds{})),
        ?assertEqual(1, nit_el_button:height(Button, #bounds{})),
        ?assertEqual(10, nit_el_button:fixed_width(Button))
    end) || Focused <- [false, true], Hovered <- [false, true]].

custom_disabled_style_test() ->
    Button = (button(first, 0))#button{enabled = false,
        style = #{fg => green, bg => blue},
        disabled_style = #{fg => yellow, dim => true},
        focused_style = #{bg => red, bold => true}},
    Output = nit_el_button:render(Button, #bounds{}, #{focused => true, hovered => true}),
    ?assertEqual({$f, #{fg => yellow, bg => blue, dim => true}},
                 nit_screen:get_cell(screen(Output), 2, 0)),
    ?assertEqual([], nit_el_button:render(Button#button{visible = false}, #bounds{}, #{})).

disabled_style_in_render_entry_points_test() ->
    Button = (button(first, 0))#button{enabled = false},
    Expected = {$f, #{fg => bright_black, dim => true}},
    Outputs = [nit_render:render_two_level(Button, #bounds{}, actions, first,
                                           #{hovered_id => first}),
               nit_render:render_dimmed(Button, #bounds{}, first)],
    lists:foreach(fun(Output) ->
        ?assertEqual(Expected, nit_screen:get_cell(screen(Output), 2, 0))
    end, Outputs).

focus_children_exclude_disabled_hidden_and_mouse_only_test() ->
    Tree = box([#vbox{children = [
        (button(disabled, 0))#button{enabled = false},
        #hbox{children = [button(first, 0),
            (button(mouse_only, 0))#button{focusable = false},
            (button(hidden, 0))#button{visible = false},
            (button(anonymous, 0))#button{id = undefined}]},
        #scroll{children = [button(second, 0)]}]}]),
    ?assertEqual([actions], nit_focus:collect_containers(Tree)),
    ?assertEqual([first, second], nit_focus:collect_children(Tree, actions)),
    ?assertEqual(second, nit_focus:next_focus(nit_focus:collect_children(Tree, actions), first)),
    ?assertEqual(first, nit_focus:prev_focus(nit_focus:collect_children(Tree, actions), second)),
    ?assertMatch(#button{enabled = false}, nit_focus:find_element(Tree, disabled)).

stale_activation_target_checks_button_state_test_() ->
    [?_test(begin
        Button = (button(first, 0))#button{enabled = Enabled, visible = Visible,
                                          focusable = Focusable},
        Tree = case InModal of false -> box([Button]); true -> modal([box([Button])]) end,
        Expected = case Enabled andalso Visible andalso Focusable of
            true -> Button;
            false -> undefined
        end,
        %% Deliberately pass the ID even when it cannot be collected for focus.
        ?assertEqual(Expected, nit_engine:activation_target(Tree, actions, first)),
        ?assertEqual(undefined, nit_engine:activation_target(Tree, first, undefined))
    end) || Enabled <- [false, true], Visible <- [false, true],
            Focusable <- [false, true], InModal <- [false, true]].

button_hits_require_enabled_and_visible_not_focusable_test_() ->
    [?_test(begin
        Button = (button(first, 0))#button{enabled = Enabled, visible = Visible,
                                          focusable = Focusable},
        Expected = case Enabled andalso Visible of
            true -> {button, first};
            false -> not_found
        end,
        ?assertEqual(Expected, nit_hit:find_at(Button, 2, 1, #bounds{})),
        ?assertEqual(Expected, nit_hit:find_at(#vbox{children = [Button]}, 2, 1, #bounds{})),
        ?assertEqual(not_found, nit_hit:find_at(Button, 11, 1, #bounds{}))
    end) || Enabled <- [false, true], Visible <- [false, true], Focusable <- [false, true]].

server_navigation_skips_disabled_and_hidden_buttons_test() ->
    Tree = box([(button(disabled, 0))#button{enabled = false}, button(first, 1),
                (button(hidden, 2))#button{visible = false}, button(second, 3)]),
    {Events, _, _} = run(Tree, undefined,
        [click(2, 1), click(2, 3), enter, {key, down}, {char, 32}, {key, up}, enter]),
    ?assertEqual([activation(first), activation(second), activation(first)], Events).

server_mouse_only_button_does_not_steal_focus_test() ->
    Tree = with_shortcut(box([(button(mode, 0))#button{focusable = false},
                              button(first, 1), button(second, 2)]), <<"Enter">>),
    {Events, _, _} = run(Tree, undefined,
        [{key, down}, click(2, 1), enter, {char, 32}, click(2, 8)]),
    ?assertEqual([activation(mode), activation(second), activation(second), activation(second)],
                 Events).

server_disabled_and_hidden_mouse_only_buttons_never_activate_test_() ->
    [?_test(begin
        Tree = (button(mode, 0))#button{focusable = false, enabled = Enabled, visible = Visible},
        {Events, _, _} = run(Tree, undefined, [click(2, 1), enter, {char, 32}]),
        ?assertEqual([], [Event || Event = {click, _, _} <- Events])
    end) || {Enabled, Visible} <- [{false, true}, {true, false}, {false, false}]].

server_shortcut_activation_obeys_button_state_test_() ->
    [?_test(begin
        Tree = with_shortcut(box([(button(first, 0))#button{enabled = Enabled}]), Key),
        {Events, _, _} = run(Tree, undefined, [click(2, 8)]),
        ?assertEqual(case Enabled of true -> [activation(first)]; false -> [] end,
                     [Event || Event = {click, _, _} <- Events])
    end) || Enabled <- [false, true], Key <- [<<"Enter">>, <<" ">>]].

server_rebuild_reassigns_disabled_focus_test() ->
    First = button(first, 0),
    Tree = with_shortcut(box([First, button(second, 1)]), <<"Enter">>),
    Replacement = nit_tree:update(Tree, first, First#button{enabled = false}),
    {Events, Rebuilt, _} = run(Tree, undefined, [enter, enter, {char, 32}, click(2, 8)],
                              #{replacement => {tree, Replacement}}),
    ?assertEqual([activation(first), activation(second), activation(second), activation(second)],
                 Events),
    ?assertMatch(#button{enabled = false}, nit_focus:find_element(Rebuilt, first)),
    ?assertEqual([second], nit_focus:collect_children(Rebuilt, actions)),
    ?assertEqual(undefined, nit_engine:activation_target(Rebuilt, actions, first)).

server_rebuild_clears_focus_when_all_buttons_disabled_test() ->
    First = button(first, 0),
    Tree = with_shortcut(box([First]), <<"Enter">>),
    Replacement = nit_tree:update(Tree, first, First#button{enabled = false}),
    {Events, Rebuilt, _} = run(Tree, undefined, [enter, enter, {char, 32}, click(2, 8)],
                              #{replacement => {tree, Replacement}}),
    ?assertEqual([activation(first)], [Event || Event = {click, _, _} <- Events]),
    ?assertEqual([], nit_focus:collect_children(Rebuilt, actions)).

modal_buttons_obey_disabled_hidden_and_mouse_only_state_test_() ->
    [?_test(begin
        Buttons = [(button(disabled, 0))#button{enabled = false}, button(first, 1),
            (button(hidden, 2))#button{visible = false}, button(second, 3),
            (button(mode, 4))#button{focusable = false}],
        Modal = modal(case Boxed of true -> [box(Buttons)]; false -> Buttons end),
        Tree = box([button(main, 0)]),
        {Events, Tree, Modal} = run(Tree, Modal,
            [click(32, 10), click(32, 12), enter, {key, down}, {char, 32},
             click(32, 14), enter, {char, $x}]),
        ?assertEqual([activation(first), activation(second), activation(mode), activation(second)],
                     Events)
    end) || Boxed <- [false, true]].

modal_disabled_buttons_isolate_input_test() ->
    Tree = box([button(main, 0)]),
    Modal = modal([(button(first, 0))#button{enabled = false}]),
    ?assertEqual({[], Tree, Modal}, run(Tree, Modal,
        [enter, {char, 32}, {char, $x}, click(32, 10), click(2, 1)])).

modal_replacement_reassigns_disabled_focus_test() ->
    First = button(first, 0),
    Tree = box([button(main, 0)]),
    Modal = modal([First, button(second, 1)]),
    Replacement = modal([First#button{enabled = false}, button(second, 1)]),
    {Events, Tree, Replacement} = run(Tree, Modal, [enter, enter, {char, 32}],
                                    #{replacement => {modal, Replacement}}),
    ?assertEqual([activation(first), activation(second), activation(second)], Events).

space_still_edits_inputs_test() ->
    Tree = box([#input{id = input, focusable = true, value = <<"ab">>, cursor_pos = 1}]),
    {Events, Edited, _} = run(Tree, undefined, [{char, 32}]),
    ?assertEqual([{input, input, <<"a b">>}], Events),
    ?assertMatch(#input{value = <<"a b">>, cursor_pos = 2}, nit_focus:find_element(Edited, input)).

anonymous_button_does_not_receive_space_without_focus_test() ->
    Tree = (button(first, 0))#button{id = undefined},
    {Events, _, _} = run(Tree, undefined, [{char, 32}]),
    ?assertEqual([{event, {char, 32}}], Events).

button(Id, Y) ->
    #button{id = Id, y = Y, width = 10, focusable = true,
            label = atom_to_binary(Id, utf8), on_click = {?MODULE, Id}}.

box(Children) ->
    #box{id = actions, focusable = true, border = none, width = 20, height = 6,
         children = Children}.

modal(Children) ->
    #modal{id = dialog, width = 20, height = 8, children = Children}.

with_shortcut(Tree, Key) ->
    #panel{children = [Tree, #status_bar{y = 7, items = [{Key, <<"Activate">>}]}]}.

activation(Id) -> {click, Id, {?MODULE, Id}}.

click(Col, Row) -> {mouse, click, left, Col, Row}.

screen(Output) -> nit_screen:from_ansi(Output, 80, 24).

run(Tree, Modal, Events) -> run(Tree, Modal, Events, #{}).

run(Tree, Modal, Events, Extra) ->
    Ref = make_ref(),
    State = maps:merge(#{tree => Tree, events => [], event_ref => Ref}, Extra),
    try
        {NewState, NewTree, NewModal} =
            nit_server:input_sequence_for_test(?MODULE, State, Tree, Modal, Events),
        Delivered = take_events(Ref),
        ?assertEqual(lists:reverse(maps:get(events, NewState)), Delivered),
        {Delivered, NewTree, NewModal}
    after
        take_events(Ref)
    end.

take_events(Ref) ->
    receive
        {Ref, Event} -> [Event | take_events(Ref)]
    after 0 -> []
    end.