-module(nit_tree_selection_request_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("nitui/include/nit_elements.hrl").

-export([init/1, view/1, handle_event/2]).

init(Tree) -> {ok, {initial, Tree}}.

view({initial, Tree}) ->
    %% Both initial view evaluations must see an unconsumed intent.
    Context = erlang:get(nitui_view_tree),
    ?assert(Context =:= undefined orelse Context =:= Tree),
    Tree;
view({ExpectedContext, Tree}) ->
    ?assertEqual(ExpectedContext, erlang:get(nitui_view_tree)),
    Tree.

handle_event(Event, _State) -> error({unexpected_callback, Event}).

merge_preserves_native_state_and_new_intent_test() ->
    Old = (branch_tree({old, target}))#tree{selected = root, offset = 2,
                                          selection_request_applied = {old, target}},
    New = (branch_tree({new, target}))#tree{selected = target, offset = 0,
                                          selection_request_applied = {new, target}},
    Merged = nit_tree:merge_state(Old, New),
    ?assertEqual(Old#tree.selected, Merged#tree.selected),
    ?assertEqual(Old#tree.offset, Merged#tree.offset),
    ?assertEqual(Old#tree.nodes, Merged#tree.nodes),
    ?assertEqual({new, target}, Merged#tree.selection_request),
    ?assertEqual({old, target}, Merged#tree.selection_request_applied),
    ?assertEqual(New#tree{id = different}, nit_tree:merge_state(Old, New#tree{id = different})).

request_expands_only_ancestors_after_merge_test() ->
    Raw = branch_tree({once, target}),
    Old = Raw#tree{selected = before, offset = 0},
    Prepared = nit_engine:prepare_tree(nit_tree:merge_state(Old, Raw), bounds(3)),
    ?assertMatch(#tree{selected = target, offset = 1,
                      selection_request_applied = {once, target}}, Prepared),
    [Before, Root, Closed, Open] = Prepared#tree.nodes,
    [Branch, Side] = Root#tree_node.children,
    [Target] = Branch#tree_node.children,
    [OldBefore, OldRoot, OldClosed, OldOpen] = Old#tree.nodes,
    [_OldBranch, OldSide] = OldRoot#tree_node.children,
    ?assert(Root#tree_node.expanded),
    ?assert(Branch#tree_node.expanded),
    ?assertNot(Target#tree_node.expanded),
    ?assertEqual({OldBefore, OldClosed, OldOpen, OldSide}, {Before, Closed, Open, Side}),
    ?assertEqual([before, root, branch, target, side, side_child, closed, open, open_child],
                 visible_ids(Prepared)).

unchanged_request_preserves_interactive_collapse_and_selection_test() ->
    Raw = branch_tree({once, target}),
    Prepared = nit_engine:prepare_tree(Raw, bounds(3)),
    Parent = nit_tree_nav:select(root, Prepared, bounds(3)),
    Collapsed = nit_tree_nav:toggle(left, Parent, bounds(3)),
    Native = nit_tree_nav:scroll(down, 3, 3, Collapsed),
    ?assertEqual(root, Native#tree.selected),
    ?assertNot((lists:nth(2, Native#tree.nodes))#tree_node.expanded),
    ?assertEqual(Native, nit_engine:prepare_tree(nit_tree:merge_state(Native, Raw), bounds(3))).

refresh_and_async_rebuild_preserve_native_wheel_scroll_test() ->
    Raw = flat_tree({once, 20}),
    Prepared = nit_engine:prepare_tree(Raw, bounds(5)),
    Native = nit_tree_nav:scroll(up, 12, 5, Prepared),
    ?assertMatch(#tree{selected = 20, offset = 3}, Native),
    %% Tick uses an explicit merge source; async updates use the active tree.
    lists:foreach(fun(Source) ->
        Refreshed = nit_server:rebuild_for_test(?MODULE, {Native, Raw}, Native, Source),
        ?assertEqual(Native, Refreshed),
        ?assertEqual(Native, nit_engine:prepare_tree(Refreshed, bounds(5), normal))
    end, [undefined, Native]).

new_token_repeats_target_and_reopens_ancestors_test() ->
    Raw = branch_tree({once, target}),
    Prepared = nit_engine:prepare_tree(Raw, bounds(3)),
    Collapsed = nit_tree_nav:toggle(left, Prepared#tree{selected = root}, bounds(3)),
    New = Raw#tree{selection_request = {again, target}},
    Repeated = nit_engine:prepare_tree(nit_tree:merge_state(Collapsed, New), bounds(3)),
    ?assertEqual(Prepared#tree{selection_request = {again, target},
                               selection_request_applied = {again, target}}, Repeated).

full_request_not_just_token_is_compared_test() ->
    Raw = flat_tree({token, 20}),
    Prepared = nit_engine:prepare_tree(Raw, bounds(5)),
    Changed = Raw#tree{selection_request = {token, 2}},
    Result = nit_engine:prepare_tree(nit_tree:merge_state(Prepared, Changed), bounds(5)),
    ?assertMatch(#tree{selected = 2, offset = 1,
                      selection_request_applied = {token, 2}}, Result).

undefined_cancels_and_allows_same_request_again_test() ->
    Raw = flat_tree({once, 20}),
    Prepared = nit_engine:prepare_tree(Raw, bounds(5)),
    Native = nit_tree_nav:navigate(up, 10, 5, Prepared),
    Cancelled = nit_tree:merge_state(Native, Raw#tree{selection_request = undefined}),
    ?assertEqual(undefined, Cancelled#tree.selection_request_applied),
    ?assertEqual(Cancelled, nit_engine:prepare_tree(Cancelled, bounds(5))),
    Repeated = nit_engine:prepare_tree(nit_tree:merge_state(Cancelled, Raw), bounds(5)),
    ?assertEqual(Prepared, Repeated).

missing_target_is_consumed_noop_even_when_it_appears_later_test() ->
    Raw = (flat_tree({once, absent}))#tree{selected = 4, offset = 8},
    Prepared = nit_engine:prepare_tree(Raw, bounds(5)),
    ?assertEqual(Raw#tree{selection_request_applied = {once, absent}}, Prepared),
    WithTarget = Raw#tree{nodes = Raw#tree.nodes ++ [#tree_node{id = absent}]},
    Refreshed = nit_engine:prepare_tree(nit_tree:merge_state(Prepared, WithTarget), bounds(5)),
    ?assertMatch(#tree{selected = 4, offset = 8}, Refreshed),
    Repeated = nit_engine:prepare_tree(nit_tree:merge_state(Refreshed,
        WithTarget#tree{selection_request = {again, absent}}), bounds(5)),
    ?assertMatch(#tree{selected = absent, offset = 26}, Repeated).

missing_target_in_empty_tree_is_noop_test() ->
    Raw = #tree{id = tree, nodes = [], selected = old, offset = 7,
                selection_request = {once, absent}},
    ?assertEqual(Raw#tree{selection_request_applied = {once, absent}},
                 nit_engine:prepare_tree(Raw, bounds(5))).

minimal_scroll_test_() ->
    [?_test(begin
        Raw = (flat_tree({once, Target}))#tree{offset = 8},
        Result = nit_engine:prepare_tree(Raw, bounds(5)),
        ?assertEqual(Offset, Result#tree.offset)
    end) || {Target, Offset} <- [{10, 8}, {4, 3}, {20, 15}]].

final_auto_height_is_resolved_after_expansion_test() ->
    Raw = #tree{id = tree, height = auto, selection_request = {once, 15}, nodes = [
        #tree_node{id = root, expanded = false, children = numbered_nodes(15)}
    ]},
    Result = nit_engine:prepare_tree(Raw, bounds(6)),
    ?assertMatch(#tree{selected = 15, offset = 10}, Result),
    ?assertEqual({ok, #bounds{width = 80, height = 6}},
                 nit_bounds:find_element_bounds(Result, tree, bounds(6))).

all_expansions_precede_sibling_layout_test_() ->
    Auto = #tree{id = auto_tree, height = auto, selection_request = {once, 5}, nodes = [
        #tree_node{id = auto_root, expanded = false, children = numbered_nodes(5)}
    ]},
    Flat = flat_tree({once, 20}),
    [?_test(begin
        Result = nit_engine:prepare_tree(#vbox{children = Children}, bounds(12)),
        ?assertMatch({ok, #bounds{height = 6}},
                     nit_bounds:find_element_bounds(Result, tree, bounds(12))),
        ?assertMatch(#tree{selected = 20, offset = 14}, nit_focus:find_element(Result, tree))
    end) || Children <- [[Flat, Auto], [Auto, Flat]]].

nested_layout_uses_final_real_bounds_test() ->
    Raw = nested((flat_tree({once, 30}))#tree{y = 2}),
    Result = nit_engine:prepare_tree(Raw, bounds(24)),
    {ok, #bounds{height = Height, y = Y}} = nit_bounds:find_element_bounds(Result, tree, bounds(24)),
    ?assertEqual(8, Height),
    ?assert(Y > 2),
    ?assertMatch(#tree{selected = 30, offset = 22, y = 2}, nit_focus:find_element(Result, tree)).

local_y_is_not_subtracted_twice_test() ->
    Raw = (flat_tree({once, 20}))#tree{y = 3},
    Result = nit_engine:prepare_tree(Raw, bounds(10)),
    ?assertMatch(#tree{selected = 20, offset = 13, y = 3, height = fill}, Result).

initial_double_view_does_not_consume_test() ->
    Raw = flat_tree({initial, 20}),
    {_US, Viewed, _Ids, _Container, _Child} = nit_engine:init_focus_state(?MODULE, Raw),
    ?assertEqual(Raw, Viewed),
    ?assertEqual(undefined, erlang:get(nitui_view_tree)),
    Prepared = nit_engine:prepare_tree(Viewed, bounds(5)),
    ?assertMatch(#tree{selected = 20, offset = 15,
                      selection_request_applied = {initial, 20}}, Prepared),
    ?assertEqual(Prepared, nit_engine:prepare_tree(Prepared, bounds(5))).

server_rebuild_applies_after_native_merge_test() ->
    Old = (flat_tree(undefined))#tree{height = 5, selected = 2, offset = 0},
    Raw = Old#tree{selection_request = {once, 20}},
    Result = nit_server:rebuild_for_test(?MODULE, {Old, Raw}, Old, undefined),
    ?assertMatch(#tree{selected = 20, offset = 15,
                      selection_request_applied = {once, 20}}, Result).

resize_reconciles_current_selection_not_consumed_target_test() ->
    Prepared = nit_engine:prepare_tree(flat_tree({once, 20}), bounds(10)),
    Native = nit_tree_nav:navigate(up, 5, 10, Prepared),
    ?assertMatch(#tree{selected = 15, offset = 10}, Native),
    %% Ordinary preparation, even with different bounds, is not resize.
    ?assertEqual(Native, nit_engine:prepare_tree(Native, bounds(3))),
    Smaller = nit_engine:prepare_tree(Native, bounds(3), resize),
    ?assertMatch(#tree{selected = 15, offset = 12,
                      selection_request_applied = {once, 20}}, Smaller),
    Larger = nit_engine:prepare_tree(Smaller, bounds(25), resize),
    ?assertMatch(#tree{selected = 15, offset = 5}, Larger).

resize_does_not_reexpand_collapsed_request_target_test() ->
    Prepared = nit_engine:prepare_tree(branch_tree({once, target}), bounds(3)),
    Collapsed = nit_tree_nav:toggle(left, Prepared#tree{selected = root}, bounds(3)),
    Result = nit_engine:prepare_tree(Collapsed, bounds(2), resize),
    ?assertEqual(Collapsed#tree.nodes, Result#tree.nodes),
    ?assertEqual(root, Result#tree.selected),
    ?assertEqual({once, target}, Result#tree.selection_request_applied),
    %% A selection hidden by a collapsed ancestor must not reopen it either.
    HiddenSelection = Collapsed#tree{selected = target},
    HiddenResult = nit_engine:prepare_tree(HiddenSelection, bounds(2), resize),
    ?assertEqual(HiddenSelection#tree.nodes, HiddenResult#tree.nodes),
    ?assertEqual(target, HiddenResult#tree.selected).

resize_without_request_uses_nested_bounds_test() ->
    Raw = nested((flat_tree(undefined))#tree{selected = 20, y = 2}),
    Result = nit_engine:prepare_tree(Raw, bounds(24), resize),
    ?assertMatch(#tree{selected = 20, offset = 12}, nit_focus:find_element(Result, tree)).

hidden_tree_and_hidden_ancestors_defer_test() ->
    Raw = branch_tree({once, target}),
    Hidden = Raw#tree{visible = false},
    ?assertEqual(Hidden, nit_engine:prepare_tree(Hidden, bounds(3))),
    ?assertEqual(Hidden, nit_engine:prepare_tree(Hidden, bounds(3), resize)),
    Parent = #box{id = hidden, visible = false, children = [Raw]},
    ?assertEqual(Parent, nit_engine:prepare_tree(Parent, bounds(3))),
    Shown = nit_engine:prepare_tree(Parent#box{visible = true}, bounds(3)),
    ?assertMatch(#box{children = [#tree{selected = target,
                                      selection_request_applied = {once, target}}]}, Shown).

inactive_tabs_defer_until_activated_test() ->
    Raw = branch_tree({once, target}),
    Tabs = #tabs{id = tabs, height = fill, tabs = [
        #tab{id = first, content = [#text{content = <<"active">>}]},
        #tab{id = second, content = [Raw]}
    ]},
    ?assertEqual(Tabs, nit_engine:prepare_tree(Tabs, bounds(8))),
    ?assertEqual(Tabs, nit_engine:prepare_tree(Tabs, bounds(6), resize)),
    Shown = nit_engine:prepare_tree(Tabs#tabs{active_tab = second}, bounds(6)),
    ?assertMatch(#tree{selected = target, offset = 1,
                      selection_request_applied = {once, target}},
                 nit_focus:find_element(Shown, tree)).

header_only_tabs_defer_requests_test_() ->
    [?_test(begin
        Tabs = #tabs{id = tabs, width = Width, height = Height, tabs = [
            #tab{id = content, content = [branch_tree({once, target})]}
        ]},
        ?assertEqual(Tabs, nit_engine:prepare_tree(Tabs, Bounds)),
        ?assertEqual(Tabs, nit_engine:prepare_tree(Tabs, Bounds, resize))
    end) || {Width, Height, Bounds} <- [
        {fill, 1, bounds(10)}, {fill, 2, bounds(10)},
        {2, fill, bounds(10)}, {fill, fill, bounds(2)}
    ]].

undefined_resets_marker_while_hidden_test() ->
    Hidden = (branch_tree(undefined))#tree{visible = false,
                                          selection_request_applied = {once, target}},
    Result = nit_engine:prepare_tree(Hidden, bounds(3)),
    ?assertEqual(Hidden#tree{selection_request_applied = undefined}, Result).

modal_and_fullscreen_roots_use_their_own_bounds_test() ->
    Raw = flat_tree({once, 20}),
    Modal = #modal{id = modal, width = 40, height = 8, children = [Raw]},
    PreparedModal = nit_engine:prepare_tree(Modal, bounds(24)),
    ?assertMatch(#tree{selected = 20, offset = 14}, nit_focus:find_element(PreparedModal, tree)),
    %% Fullscreen preparation is passed the stretched active root, not the base layout.
    PreparedFull = nit_engine:prepare_tree(Raw#tree{x = 0, y = 0, height = fill}, bounds(24)),
    ?assertMatch(#tree{selected = 20, offset = 0}, PreparedFull).

preparation_never_changes_focus_or_emits_callbacks_test() ->
    Raw = #box{id = container, focusable = true, children = [
        #input{id = input, focusable = true},
        (flat_tree({once, 20}))#tree{focusable = true,
            on_select = fun() -> error(unexpected_on_select) end}
    ]},
    Containers = nit_focus:collect_containers(Raw),
    Children = nit_focus:collect_children(Raw, container),
    Prepared = nit_engine:prepare_tree(Raw, bounds(5)),
    ?assertEqual(Containers, nit_focus:collect_containers(Prepared)),
    ?assertEqual(Children, nit_focus:collect_children(Prepared, container)),
    ?assertEqual(nit_focus:find_element(Raw, input), nit_focus:find_element(Prepared, input)).

bounds(Height) -> #bounds{width = 80, height = Height}.

numbered_nodes(Count) ->
    [#tree_node{id = N, label = integer_to_binary(N)} || N <- lists:seq(1, Count)].

flat_tree(Request) ->
    #tree{id = tree, height = fill, nodes = numbered_nodes(30), selection_request = Request}.

visible_ids(Tree) -> [Id || {_, _, #tree_node{id = Id}} <- nit_tree_nav:flatten_visible(Tree)].

branch_tree(Request) ->
    #tree{id = tree, height = fill, selection_request = Request, nodes = [
        #tree_node{id = before},
        #tree_node{id = root, expanded = false, children = [
            #tree_node{id = branch, expanded = false, children = [
                #tree_node{id = target, expanded = false, children = [#tree_node{id = leaf}]}
            ]},
            #tree_node{id = side, expanded = true, children = [#tree_node{id = side_child}]}
        ]},
        #tree_node{id = closed, expanded = false, children = [#tree_node{id = closed_child}]},
        #tree_node{id = open, expanded = true, children = [#tree_node{id = open_child}]}
    ]}.

nested(Tree) ->
    #vbox{y = 1, spacing = 1, children = [
        #text{height = 2},
        #hbox{height = fill, children = [
            #box{width = 12, height = fill, border = single},
            #box{width = fill, height = fill, border = single, children = [
                #tabs{id = tabs, height = fill, tabs = [#tab{id = content, content = [
                    #vbox{y = 1, spacing = 1, children = [#text{height = 1}, Tree]}
                ]}]}
            ]}
        ]},
        #text{height = 1}
    ]}.