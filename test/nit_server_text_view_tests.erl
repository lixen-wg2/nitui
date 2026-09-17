-module(nit_server_text_view_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("nitui/include/nit_elements.hrl").

-export([init/1, view/1, handle_event/2]).

init(State) -> {ok, State}.
view(#{tree := Tree, ref := Ref}) ->
    self() ! {Ref, view},
    Tree.
handle_event(Event, State = #{ref := Ref}) ->
    self() ! {Ref, {event, Event}},
    case Event of
        {event, {key, f2}} -> {fullscreen, viewer, State};
        _ -> {noreply, State}
    end.

keyboard_is_native_standalone_and_nested_test_() ->
    [?_test(begin
        V = viewer(),
        Tree = wrap(Kind, V),
        Keys = [{key, right}, {key, {shift, down}}, {key, {shift, 'end'}},
                {key, {shift, page_down}}, {key, {shift, page_up}},
                {key, {shift, up}}, {key, {shift, home}}],
        {ok, B} = nit_bounds:find_element_bounds(Tree, viewer, #bounds{}),
        Expected = lists:foldl(fun(Key, Acc) -> nit_el_text_view:key(Acc, Key, B) end, V, Keys),
        Result = run(Tree, undefined, Keys),
        ?assertEqual(Expected, element_view(Result)),
        ?assertEqual([], maps:get(log, Result))
    end) || Kind <- [standalone, box, nested, tabs, scroll]].

editing_is_readonly_but_application_shortcuts_remain_test() ->
    V = viewer(),
    Result = run(V, undefined, [{char, $r}, backspace, delete, enter, {ctrl, $v},
                                {paste, <<"qYy">>}, {char, $q}, escape, {ctrl, $c}]),
    ?assertEqual(V, element_view(Result)),
    ?assertEqual([{event, {event, {char, $r}}}, view,
                  {event, {event, {char, $q}}}, view,
                  {event, {event, escape}}, view, {event, quit}], maps:get(log, Result)).

refresh_shortcut_preserves_readonly_selection_test_() ->
    [?_test(begin
        V = viewer(),
        Selected = V#text_view{cursor_pos = 3, selection_anchor = 1},
        R = run(wrap(Kind, Selected), undefined,
                [{char, $r}, backspace, delete, enter, {ctrl, $x}, {ctrl, $v},
                 {paste, <<"replace selection">>}, {paste, start},
                 {char, $r}, {char, $q}, {char, $Y}, delete, {paste, 'end'}],
                #{callback_tree => wrap(Kind, V)}),
        ?assertEqual(Selected, element_view(R)),
        ?assertEqual([{event, {event, {char, $r}}}, view], maps:get(log, R))
    end) || Kind <- [standalone, box, nested, tabs, scroll]].

incomplete_bracketed_paste_cannot_trap_ctrl_c_test_() ->
    [?_test(begin
        V = viewer(),
        M = case Where of main -> undefined; modal -> modal(V#text_view{id = modal_view}) end,
        %% Deliberately omit paste end. The callback declines to stop so the
        %% following native key also proves Ctrl-C cleared the paste latch.
        R = run(V, M, [{paste, start}, {char, $r}, {char, $q}, {char, $Y},
                       {key, {shift, right}}, delete, {ctrl, $c}, {key, right}]),
        Target = case Where of
            main -> element_view(R);
            modal ->
                ?assertEqual(V, element_view(R)),
                nit_focus:find_element(maps:get(modal, R), modal_view)
        end,
        ?assertEqual(V#text_view.content, Target#text_view.content),
        ?assertMatch(#text_view{cursor_pos = 1, selection_anchor = undefined,
                               copy_status = idle}, Target),
        ?assertEqual([{event, quit}], maps:get(log, R))
    end) || Where <- [main, modal]].

selection_copy_all_copy_and_failure_status_test_() ->
    [?_test(begin
        V = viewer(),
        Result = run(V, undefined, [{key, {shift, right}}, {char, $y}],
                     #{copy_result => Status}),
        ?assertEqual([{copy, <<"a">>}], maps:get(log, Result)),
        ?assertEqual(Status, (element_view(Result))#text_view.copy_status),
        All = run(V, undefined, [{ctrl, $a}, {char, $y}, {char, $Y}],
                  #{copy_result => Status}),
        ?assertEqual([{copy, V#text_view.content}, {copy, V#text_view.content}], maps:get(log, All)),
        ?assertEqual(Status, (element_view(All))#text_view.copy_status)
    end) || Status <- [{ok, sent}, {error, disabled}, {error, too_large},
                      {error, invalid_text}, {error, unavailable}, {error, write_failed}]].

copy_without_selection_or_valid_text_never_writes_test() ->
    None = run(viewer(), undefined, [{char, $y}]),
    ?assertEqual([], maps:get(log, None)),
    ?assertEqual({error, no_selection}, (element_view(None))#text_view.copy_status),
    Invalid = run((viewer())#text_view{content = <<255>>}, undefined, [{char, $Y}]),
    ?assertEqual([], maps:get(log, Invalid)),
    ?assertEqual({error, invalid_text}, (element_view(Invalid))#text_view.copy_status).

copy_does_not_repeat_on_redraw_or_rebuild_test() ->
    V = viewer(),
    R = run(V, undefined, [{char, $Y}, {test_info, {resize, 60, 20}},
                           {test_info, refresh_tick}, {test_info, cursor_blink}]),
    ?assertEqual([{copy, V#text_view.content}, {event, tick}, view], maps:get(log, R)),
    ?assertEqual({ok, sent}, (element_view(R))#text_view.copy_status).

no_application_or_virtual_table_fetch_on_navigation_copy_test() ->
    Ref = make_ref(),
    Provider = fun(_, _) -> self() ! {Ref, fetch}, [[<<"row">>]] end,
    Table = #table{id = background, y = 10, width = 10, height = 2,
                   row_provider = Provider, total_rows = 1,
                   columns = [#table_col{id = value}]},
    Tree = #panel{children = [viewer(), Table]},
    Result = run(Tree, undefined, [{key, right}, {key, page_down}, {char, $Y}]),
    ?assertEqual([{copy, (viewer())#text_view.content}], maps:get(log, Result)),
    receive {Ref, fetch} -> ?assert(false) after 0 -> ok end.

drag_requires_press_and_release_stops_capture_test() ->
    V = viewer(),
    Motion = {mouse, motion, left, 8, 2},
    ?assertEqual(V, element_view(run(V, undefined, [Motion]))),
    Press = {mouse, click, left, 2, 1},
    Release = {mouse, release, left, 4, 2},
    Result = run(V, undefined, [Press, Motion, Release, {mouse, motion, left, 10, 3}]),
    B = nit_el_text_view:bounds(V, #bounds{}),
    Expected = lists:foldl(fun({Phase, C, R}, Acc) ->
        nit_el_text_view:mouse(Acc, Phase, C, R, B)
    end, V, [{press, 2, 1}, {drag, 8, 2}, {release, 4, 2}]),
    ?assertEqual(Expected, element_view(Result)),
    ?assertEqual([], maps:get(log, Result)).

drag_autoscroll_and_focus_invalidation_test() ->
    V = viewer(),
    Tree = #panel{children = [V, V#text_view{id = other, x = 30}]},
    Prefix = [{mouse, click, left, 2, 1}, {mouse, motion, left, 3, 8}],
    Dragged = element_view(run(Tree, undefined, Prefix)),
    ?assert(Dragged#text_view.offset > 0),
    Result = run(Tree, undefined, Prefix ++ [tab, {key, btab}, {mouse, motion, left, 8, 1}]),
    ?assertEqual(Dragged, element_view(Result)),
    ?assertEqual([], maps:get(log, Result)).

wheel_scrolls_hovered_viewer_without_stealing_focus_test() ->
    V = viewer(),
    Tree = #panel{children = [V, V#text_view{id = other, x = 30}]},
    R = run(Tree, undefined, [{mouse, scroll, down, 32, 2}, {key, right}]),
    ?assertMatch(#text_view{cursor_pos = 1, offset = 0}, element_view(R)),
    ?assertMatch(#text_view{cursor_pos = 0, offset = 1},
                 nit_focus:find_element(maps:get(tree, R), other)),
    ?assertEqual([], maps:get(log, R)).

modal_keys_wheel_and_mouse_are_isolated_test() ->
    V = viewer(),
    M = modal(V#text_view{id = modal_view}),
    {ok, B} = nit_bounds:find_element_bounds(M, modal_view, #bounds{}),
    X = B#bounds.x + 1, Y = B#bounds.y + 1,
    R = run(V, M, [{key, right}, {key, page_down}, {mouse, scroll, down, 1, 1},
                   {mouse, click, left, X, Y}, {mouse, motion, left, X + 3, Y},
                   {mouse, release, left, X + 3, Y}, {char, $y}]),
    ?assertEqual(V, element_view(R)),
    ?assertEqual([{copy, <<"klm">>}], maps:get(log, R)),
    ModalView = nit_focus:find_element(maps:get(modal, R), modal_view),
    ?assertEqual({ok, sent}, ModalView#text_view.copy_status).

background_viewer_is_not_scrolled_under_button_modal_test() ->
    V = viewer(),
    M = modal(#button{id = close, focusable = true, label = <<"Close">>}),
    R = run(V, M, [{mouse, scroll, down, 2, 1}, {char, $Y}, {ctrl, $a},
                   {mouse, scroll, down, 79, 23},
                   {mouse, click, left, 2, 1}, {mouse, motion, left, 8, 2}]),
    ?assertEqual(V, element_view(R)),
    ?assertEqual([], maps:get(log, R)).

modal_characters_do_not_leak_application_shortcuts_test_() ->
    [?_test(begin
        V = (viewer())#text_view{cursor_pos = 3, selection_anchor = 1},
        M = modal(Child),
        R = run(V, M, [{char, $r}, {char, $h}, {char, $?}, {char, $x},
                       backspace, delete]),
        ?assertEqual(V, element_view(R)),
        ?assertEqual(M, maps:get(modal, R)),
        ?assertEqual([], maps:get(log, R)),
        ?assertEqual([], maps:get(writes, R))
    end) || Child <- [(viewer())#text_view{id = modal_view},
                      #button{id = close, focusable = true, label = <<"Close">>}]].

modal_and_rebuild_invalidate_drag_test_() ->
    [?_test(begin
        V = viewer(),
        Press = {mouse, click, left, 2, 1},
        R = run(V, undefined, [Press | Transition] ++ [{mouse, motion, left, 8, 2}]),
        ?assertMatch(#text_view{cursor_pos = 1, selection_anchor = 1}, element_view(R))
    end) || Transition <- [
        [{test_cast, {set_modal, modal(#text{content = <<"Modal">>})}},
         {test_cast, close_modal}],
        [{test_cast, {update, fun(S) -> S end}}],
        [{test_info, refresh_tick}],
        [{test_info, {resize, 60, 20}}]
    ]].

same_content_rebuild_preserves_state_changed_content_resets_test() ->
    V = viewer(),
    Old = V#text_view{cursor_pos = 12, selection_anchor = 2, offset = 2,
                      copy_status = {ok, sent}},
    Ref = make_ref(),
    try
        lists:foreach(fun(MergeFrom) ->
            Same = nit_server:rebuild_for_test(?MODULE, #{tree => V, ref => Ref}, Old, MergeFrom),
            ?assertEqual(Old, Same),
            Changed = V#text_view{content = <<"new">>},
            Reset = nit_server:rebuild_for_test(?MODULE, #{tree => Changed, ref => Ref}, Old, MergeFrom),
            ?assertEqual(Changed, Reset)
        end, [undefined, Old])
    after drain(Ref) end.

fullscreen_uses_screen_bounds_and_restores_native_state_test() ->
    V = (viewer())#text_view{x = 3, y = 2},
    B = #bounds{width = 40, height = 12},
    Full = run(V, undefined, [{key, f2}, {key, page_down}], #{bounds => B}),
    Stretched = V#text_view{x = 0, y = 0, width = fill, height = fill},
    Expected = nit_el_text_view:key(Stretched, {key, page_down}, B),
    ?assertEqual(Expected, element_view(Full)),
    Back = run(V, undefined, [{key, f2}, {key, page_down}, escape], #{bounds => B}),
    ?assertEqual(nit_el_text_view:merge(Expected, V), element_view(Back)),
    ?assertEqual([{event, {event, {key, f2}}}, view, view], maps:get(log, Back)).

focus_and_visible_bounds_integration_test() ->
    V = (viewer())#text_view{x = 2, y = 1, width = 99, height = 99},
    Tree = #box{id = box, focusable = true, border = single,
                x = 3, y = 2, width = 20, height = 8,
                children = [#panel{children = [V]}]},
    B = #bounds{x = 6, y = 4, width = 16, height = 5},
    ?assertEqual([box], nit_focus:collect_containers(Tree)),
    ?assertEqual([viewer], nit_focus:collect_children(Tree, box)),
    ?assertEqual({ok, B}, nit_bounds:find_element_bounds(Tree, viewer, #bounds{})),
    ?assertEqual({text_view, viewer}, nit_hit:find_at(Tree, 7, 5, #bounds{})),
    ?assertEqual({box, box}, nit_hit:find_at(Tree, 23, 5, #bounds{})),
    Hidden = Tree#box{visible = false},
    ?assertEqual([], nit_focus:collect_children(Hidden, box)),
    ?assertEqual(not_found, nit_hit:find_at(Hidden, 7, 5, #bounds{})),
    ?assertEqual([], nit_render:render_two_level(Hidden, #bounds{}, box, viewer)).

toolbar_click_copies_once_and_does_not_start_drag_test() ->
    V = (viewer())#text_view{show_toolbar = true, width = 25, height = 4,
                            cursor_pos = 3, selection_anchor = 0},
    R = run(V, undefined, [{mouse, click, left, 2, 4}, {mouse, release, left, 2, 4},
                           {mouse, motion, left, 8, 1}, {mouse, click, left, 12, 4}]),
    ?assertEqual([{copy, <<"abc">>}, {copy, V#text_view.content}], maps:get(log, R)),
    ?assertMatch(#text_view{cursor_pos = 3, selection_anchor = 0}, element_view(R)).

offset_render_bounds_and_keyboard_agree_test() ->
    V = (viewer())#text_view{x = 2, y = 1, width = fill, height = fill},
    Tree = #box{id = box, x = 3, y = 2, width = 10, height = 6,
                focusable = true, children = [V]},
    B = #bounds{x = 5, y = 3, width = 8, height = 5},
    ?assertEqual({ok, B}, nit_bounds:find_element_bounds(Tree, viewer, #bounds{})),
    R = run(Tree, undefined, [{key, down}]),
    Expected = nit_el_text_view:key(V, {key, down}, B),
    ?assertEqual(Expected, element_view(R)),
    Output = nit_render:render_two_level(Tree, #bounds{}, box, viewer),
    Screen = nit_screen:from_ansi(Output, 80, 24),
    ?assertMatch({$a, _}, nit_screen:get_cell(Screen, 5, 3)),
    ?assertMatch({$i, _}, nit_screen:get_cell(Screen, 5, 4)),
    ?assertMatch({$\s, _}, nit_screen:get_cell(Screen, 13, 3)).

partial_redraw_preserves_scroll_siblings_test() ->
    V = (viewer())#text_view{height = 4, width = fill},
    Tree = #scroll{id = scroll, offset = 1, show_scrollbar = false,
                   children = [V, #text{content = <<"SIBLING">>}]},
    B = #bounds{width = 20, height = 4},
    Before = nit_render:render_two_level(Tree, B, scroll, viewer),
    Output = nit_render:render_text_view(Tree, B, scroll, viewer, viewer),
    Screen = nit_screen:from_ansi([Before, Output], 20, 4),
    Row = unicode:characters_to_binary([C || X <- lists:seq(0, 6),
                                             {C, _} <- [nit_screen:get_cell(Screen, X, 3)]]),
    ?assertEqual(<<"SIBLING">>, Row),
    ?assertEqual(not_found, nit_hit:find_at(Tree, 1, 5, B)).

hidden_and_inactive_viewers_cannot_receive_keys_test() ->
    Hidden = (viewer())#text_view{id = hidden, visible = false},
    Inactive = (viewer())#text_view{id = inactive},
    Active = viewer(),
    Tree = #panel{children = [Hidden, #tabs{id = tabs, focusable = true,
        active_tab = active, tabs = [#tab{id = other, content = [Inactive]},
                                     #tab{id = active, content = [Active]}]}]},
    R = run(Tree, undefined, [{key, right}, {char, $Y}]),
    ?assertMatch(#text_view{cursor_pos = 1}, element_view(R)),
    ?assertEqual([tabs], nit_focus:collect_containers(Tree)),
    ?assertEqual(not_found, nit_bounds:find_element_bounds(Tree, hidden, #bounds{})),
    ?assertEqual(undefined, nit_focus:find_element(Tree, inactive)),
    ?assertEqual([{copy, Active#text_view.content}], maps:get(log, R)).

ordinary_frames_preserve_narrow_combining_graphemes_test_() ->
    [?_test(begin
        V = (viewer())#text_view{content = <<$e, 16#0301/utf8, "cho">>},
        Selected = V#text_view{cursor_pos = 1, selection_anchor = 0},
        {Tree, M} = frame_fixture(Where, Selected),
        {CallbackTree, _} = frame_fixture(Where, V),
        %% No native viewer key or partial render precedes the first ordinary
        %% frame. A second ordinary render must not use a lossy cached screen.
        R = run(Tree, M, [{test_info, refresh_tick}, Redraw],
                #{bounds => #bounds{width = 40, height = 12}, callback_tree => CallbackTree}),
        Writes = maps:get(writes, R),
        Frames = case Redraw of
            {test_info, {resize, _, _}} ->
                [Initial, Clear, Next] = Writes,
                ?assertEqual(unicode:characters_to_binary(nit_terminal:clear()), Clear),
                [Initial, Next];
            _ ->
                ?assertEqual(2, length(Writes)),
                Writes
        end,
        %% Inspect each combined raw tty frame, not nit_screen's codepoint
        %% cells or all writes concatenated (which could hide a missing redraw).
        lists:foreach(fun assert_combining_frame/1, Frames),
        FinalView = case Where of
            modal -> nit_focus:find_element(maps:get(modal, R), viewer);
            _ -> element_view(R)
        end,
        ?assertEqual(Selected, FinalView),
        ?assertEqual({ok, <<$e, 16#0301/utf8>>}, nit_el_text_view:copy_text(FinalView, selection)),
        ExpectedLog = case Redraw of
            {test_info, refresh_tick} -> [{event, tick}, view, {event, tick}, view];
            _ -> [{event, tick}, view]
        end,
        ?assertEqual(ExpectedLog, maps:get(log, R))
    end) || Where <- [main, modal, background],
            Redraw <- [{test_info, refresh_tick}, tab, {test_info, {resize, 32, 10}}]].

frame_fixture(Where, V) ->
    Marker = #text{id = marker, y = 8, width = 16, height = 1, content = <<"FRAME SIBLING">>},
    Controls = #box{id = controls, focusable = true, x = 22, width = 8, height = 3,
                    children = [#button{id = close, focusable = true, label = <<"Close">>}]},
    Tree = #panel{children = [#box{id = box, focusable = true, width = 20, height = 4,
                                   children = [V]}, Controls, Marker]},
    case Where of
        main -> {Tree, undefined};
        modal -> {Marker, modal(V)};
        background -> {Tree, modal(#button{id = modal_close, focusable = true,
                                           label = <<"Close">>})}
    end.

assert_combining_frame(Frame) ->
    ?assert(is_binary(Frame)),
    ?assertMatch(<<"\e[2J\e[H", _/binary>>, Frame),
    %% No CJK/emoji/wide glyph may accidentally enable the old wide-only path.
    ?assertNot(nit_unicode:contains_wide(Frame)),
    ?assertMatch([_], binary:matches(Frame, <<$e, 16#0301/utf8>>)),
    ?assertNotEqual(nomatch, binary:match(Frame, <<"FRAME SIBLING">>)),
    ?assertEqual(nomatch, binary:match(Frame, <<16#FFFD/utf8>>)).

viewer() ->
    #text_view{id = viewer, focusable = true, width = 20, height = 3,
                show_toolbar = false, show_scrollbar = false,
                content = <<"abcdefghij\nklmnopqrst\nuvwxyz0123\n456789abcd\nefghijklmn">>}.

wrap(standalone, V) -> V;
wrap(box, V) -> #box{id = box, focusable = true, children = [V]};
wrap(nested, V) -> #box{id = box, focusable = true, border = single,
                       children = [#vbox{children = [#hbox{children = [#panel{children = [V]}]}]}]};
wrap(tabs, V) -> #tabs{id = tabs, focusable = true, tabs = [#tab{id = tab, content = [V]}]};
wrap(scroll, V) -> #scroll{id = scroll, focusable = true, children = [V]}.

modal(Child) -> #modal{id = overlay, width = 30, height = 6, children = [Child]}.
element_view(#{tree := Tree}) -> nit_focus:find_element(Tree, viewer).

run(Tree, Modal, Events) -> run(Tree, Modal, Events, #{}).
run(Tree, Modal, Events, Opts) ->
    %% Never start a real terminal or touch the user's clipboard. All copy
    %% requests use the core helper's injected transport, all writes a fake tty.
    ?assertEqual(undefined, whereis(nit_tty)),
    true = register(nit_tty, self()),
    Ref = make_ref(),
    Copy = fun(Text) -> self() ! {Ref, {copy, Text}}, maps:get(copy_result, Opts, {ok, sent}) end,
    State = #{tree => maps:get(callback_tree, Opts, Tree), ref => Ref},
    try
        {_, NewTree, NewModal} = nit_server:input_sequence_for_test(
            ?MODULE, State, Tree, Modal, Events, Opts#{clipboard_copy => Copy}),
        #{tree => NewTree, modal => NewModal, log => drain(Ref), writes => drain_tty()}
    after
        unregister(nit_tty),
        drain(Ref),
        drain_tty()
    end.

drain(Ref) ->
    receive {Ref, Event} -> [Event | drain(Ref)] after 0 -> [] end.
drain_tty() ->
    receive
        {'$gen_cast', {write, Data}} -> [unicode:characters_to_binary(Data) | drain_tty()]
    after 0 -> [] end.