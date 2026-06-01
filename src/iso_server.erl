%%%-------------------------------------------------------------------
%%% @doc NitUI UI Server - Core TUI event loop and rendering.
%%%
%%% This module handles all the TUI machinery:
%%% - Input event handling (keyboard, mouse)
%%% - Focus management
%%% - Rendering
%%% - Modal overlays
%%%
%%% Users implement a callback module with:
%%% - init() -> {ok, State} | {ok, State, Tree}
%%% - view(State) -> Tree
%%% - handle_event(Event, State) -> {noreply, State} | {stop, Reason, State}
%%% @end
%%%-------------------------------------------------------------------
-module(iso_server).

-behaviour(gen_server).

-include("iso_elements.hrl").

%% API
-export([start_link/1, start_link/2, start_link/3, stop/1]).
-export([update/2, get_state/1, set_modal/2, close_modal/1]).
-export([send_event/2]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-record(fullscreen, {
    id :: term(),
    tree :: term(),
    focused_container :: term(),
    focused_child :: term(),
    container_ids :: [term()]
}).

%% Focus tracking for elements inside an active #modal{} overlay.
%% Mirrors the focused_container/focused_child/container_ids triple on
%% #iso_state but scoped to the modal subtree.
-record(modal_focus, {
    container :: term(),
    child :: term(),
    container_ids :: [term()]
}).

-record(iso_state, {
    callback :: module(),          %% User callback module
    user_state :: term(),          %% User's state (typically a map)
    tree :: term(),                %% Current element tree
    bounds :: #bounds{},           %% Screen bounds
    focused_container :: term(),   %% Currently focused container (Tab navigation)
    focused_child :: term(),       %% Currently focused child within container (Arrow navigation)
    container_ids :: [term()],     %% List of container IDs (for Tab)
    modal :: undefined | term(),   %% Current modal overlay
    modal_focus = undefined :: undefined | #modal_focus{},  %% Focus inside modal subtree
    debug_event :: undefined | term(),  %% Last unhandled event for debug display
    nav_stack = [] :: [nav_entry()],    %% Navigation stack for push/pop
    prev_screen :: undefined | iso_screen:screen(),  %% Previous screen for diff rendering
    mounted_ids = #{} :: #{term() => tuple()},  %% Currently mounted elements {Id => Element}
    %% Cursor blink state
    cursor_visible = true :: boolean(),   %% Whether cursor is currently visible
    cursor_timer = undefined :: undefined | reference(),  %% Timer ref for cursor blink
    %% Periodic refresh timer for live updates
    refresh_timer = undefined :: undefined | reference(),  %% Timer ref for periodic refresh
    fullscreen = undefined :: undefined | #fullscreen{}
}).

%% Entry in the navigation stack - stores everything needed to restore a view
-record(nav_entry, {
    callback :: module(),
    user_state :: term(),
    tree :: term(),
    focused_container :: term(),
    focused_child :: term(),
    container_ids :: [term()]
}).
-type nav_entry() :: #nav_entry{}.

%%====================================================================
%% API
%%====================================================================

-spec start_link(module()) -> {ok, pid()} | {error, term()}.
start_link(CallbackModule) ->
    start_link(CallbackModule, #{}).

-spec start_link(module(), term()) -> {ok, pid()} | {error, term()}.
start_link(CallbackModule, InitArg) ->
    gen_server:start_link(?MODULE, {undefined, CallbackModule, InitArg}, []).

-spec start_link({local, atom()} | {global, term()}, module(), term()) -> {ok, pid()} | {error, term()}.
start_link(Name, CallbackModule, InitArg) ->
    gen_server:start_link(Name, ?MODULE, {Name, CallbackModule, InitArg}, []).

-spec stop(pid() | atom()) -> ok.
stop(Server) ->
    gen_server:stop(Server).

%% Update user state and re-render
-spec update(pid() | atom(), fun((term()) -> term())) -> ok.
update(Server, UpdateFun) ->
    gen_server:cast(Server, {update, UpdateFun}).

%% Get current user state
-spec get_state(pid() | atom()) -> term().
get_state(Server) ->
    gen_server:call(Server, get_state).

%% Show a modal overlay
-spec set_modal(pid() | atom(), term()) -> ok.
set_modal(Server, Modal) ->
    gen_server:cast(Server, {set_modal, Modal}).

%% Close current modal
-spec close_modal(pid() | atom()) -> ok.
close_modal(Server) ->
    gen_server:cast(Server, close_modal).

%% Send an event to be handled as if it came from user input
-spec send_event(pid() | atom(), term()) -> ok.
send_event(Server, Event) ->
    gen_server:cast(Server, {send_event, Event}).

%%====================================================================
%% gen_server callbacks
%%====================================================================

init({_Name, CallbackModule, InitArg}) ->
    %% Note: iso_tty and iso_input are started by nitui application,
    %% which must be a dependency. OTP ensures dependencies are fully
    %% started before this application starts.
    %% Register this process as the input target
    iso_input:set_target(self()),
    %% Register for terminal resize events
    iso_tty:set_resize_target(self()),
    %% Get terminal size
    Bounds = case iso_tty:get_size() of
        {ok, {Cols, Rows}} -> #bounds{width = Cols, height = Rows};
        _ -> #bounds{width = 80, height = 24}
    end,
    %% Initialize user state and focus
    {UserState, Tree, ContainerIds, FocusedContainer, FocusedChild} =
        iso_engine:init_focus_state(CallbackModule, InitArg),
    %% Start periodic refresh timer (every 1 second)
    RefreshTimer = erlang:send_after(1000, self(), refresh_tick),
    %% Initial render
    iso_tty:clear(),
    render_tree(Tree, Bounds, FocusedContainer, FocusedChild),
    {ok, #iso_state{
        callback = CallbackModule,
        user_state = UserState,
        tree = Tree,
        bounds = Bounds,
        focused_container = FocusedContainer,
        focused_child = FocusedChild,
        container_ids = ContainerIds,
        modal = undefined,
        refresh_timer = RefreshTimer
    }}.

handle_call(get_state, _From, State = #iso_state{user_state = UserState}) ->
    {reply, UserState, State};
handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast({update, UpdateFun}, State) ->
    {noreply, NewState} = do_update(UpdateFun, State),
    {noreply, NewState};
handle_cast({set_modal, Modal}, State) ->
    NewState = activate_modal(State, Modal),
    FinalState = render_diff(NewState),
    {noreply, FinalState};
handle_cast(close_modal, State) ->
    NewState = deactivate_modal(State),
    FinalState = render_diff(NewState),
    {noreply, FinalState};
handle_cast({send_event, Event}, State) ->
    forward_event(Event, State);
handle_cast(_Msg, State) ->
    {noreply, State}.

%% Handle input events from iso_input
handle_info({input, Event}, State) ->
    handle_input(Event, State);

%% Handle terminal resize
handle_info({resize, Cols, Rows}, State = #iso_state{tree = Tree,
                                                       focused_container = FC,
                                                       focused_child = FCh}) ->
    %% Update bounds and re-render
    NewBounds = #bounds{width = Cols, height = Rows},
    iso_tty:clear(),
    render_tree(Tree, NewBounds, FC, FCh),
    {noreply, State#iso_state{bounds = NewBounds}};

%% Handle cursor blink timer
handle_info(cursor_blink, State = #iso_state{cursor_visible = Visible, cursor_timer = _Timer}) ->
    NewVisible = not Visible,
    NewTimer = erlang:send_after(500, self(), cursor_blink),
    NewState = State#iso_state{cursor_visible = NewVisible, cursor_timer = NewTimer},
    FinalState = render_diff(NewState),
    {noreply, FinalState};

%% Handle periodic refresh timer for live updates
handle_info(refresh_tick, State = #iso_state{callback = Cb, user_state = US, tree = OldTree}) ->
    %% Notify the callback module of periodic tick
    NewUS = case erlang:function_exported(Cb, handle_event, 2) of
        true ->
            case catch Cb:handle_event(tick, US) of
                {noreply, S} -> S;
                _ -> US
            end;
        false -> US
    end,
    %% Re-render with updated state, preserving widget state from the active tree.
    NewState = rebuild_view_state(NewUS, State, OldTree),
    FinalState = render_diff(NewState),
    %% Schedule next refresh
    NewTimer = erlang:send_after(1000, self(), refresh_tick),
    {noreply, FinalState#iso_state{refresh_timer = NewTimer}};

%% Ignore raw signal messages (e.g., sigwinch delivered by the BEAM runtime)
handle_info(sigwinch, State) ->
    {noreply, State};
handle_info({_Ref, {signal, sigwinch}}, State) ->
    {noreply, State};
handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, #iso_state{cursor_timer = CursorTimer, refresh_timer = RefreshTimer}) ->
    maybe_cancel_timer(CursorTimer),
    maybe_cancel_timer(RefreshTimer),
    %% Cleanup terminal state (disable mouse, show cursor, exit alt screen)
    %% We catch errors in case iso_tty is already stopped
    catch iso_tty:cleanup(),
    ok.

%%====================================================================
%% Internal: Modal focus helpers
%%====================================================================
%%
%% When a #modal{} is active, focus navigation and input routing target
%% the modal subtree rather than the main view tree. `modal_focus` on
%% #iso_state tracks the modal's own {container, child, container_ids}
%% triple; `activate_modal/2` initialises it from the modal's contents
%% and `deactivate_modal/1` clears it when the modal closes.

%% Set/update the active modal, picking an initial focus inside it.
activate_modal(State, Modal) ->
    State#iso_state{modal = Modal, modal_focus = init_modal_focus(Modal)}.

%% Clear the active modal and its focus tracking.
deactivate_modal(State) ->
    State#iso_state{modal = undefined, modal_focus = undefined}.

init_modal_focus(undefined) ->
    undefined;
init_modal_focus(Modal) ->
    ContainerIds = iso_focus:collect_containers(Modal),
    Container = case ContainerIds of [First | _] -> First; [] -> undefined end,
    ChildIds = iso_focus:collect_children(Modal, Container),
    Child = case ChildIds of
        [FirstChild | _] -> FirstChild;
        [] ->
            %% No focusable child under a container - try the modal's own
            %% direct children (buttons/inputs sitting in a vbox/hbox).
            case iso_focus:collect_children(#box{children = modal_children(Modal)}, undefined) of
                [F | _] -> F;
                [] -> undefined
            end
    end,
    #modal_focus{container = Container, child = Child, container_ids = ContainerIds}.

modal_children(#modal{children = Children}) -> Children;
modal_children(_) -> [].

%% Return {Tree, Container, Child, ContainerIds, Where} for the active
%% focus target. Where is `modal` when a modal is active, `main` otherwise.
active_focus(#iso_state{modal = undefined, tree = Tree,
                        focused_container = FC, focused_child = Ch,
                        container_ids = Ids}) ->
    {Tree, FC, Ch, Ids, main};
active_focus(#iso_state{modal = Modal, modal_focus = undefined} = State) ->
    active_focus(State#iso_state{modal_focus = init_modal_focus(Modal)});
active_focus(#iso_state{modal = Modal,
                        modal_focus = #modal_focus{container = FC, child = Ch,
                                                   container_ids = Ids}}) ->
    {Modal, FC, Ch, Ids, modal}.

%% Write {Tree, Container, Child, ContainerIds} back into the right slot.
set_active(main, State, Tree, FC, Ch, Ids) ->
    State#iso_state{tree = Tree,
                    focused_container = FC,
                    focused_child = Ch,
                    container_ids = Ids};
set_active(modal, State, Modal, FC, Ch, Ids) ->
    State#iso_state{modal = Modal,
                    modal_focus = #modal_focus{container = FC, child = Ch,
                                               container_ids = Ids}}.

%% Write back just the tree (modal subtree updates after input edits).
set_active_tree(main, State, Tree) ->
    State#iso_state{tree = Tree};
set_active_tree(modal, State, Modal) ->
    State#iso_state{modal = Modal}.

%% Write back just the focused child within the active focus root.
set_active_child(main, State, Ch) ->
    State#iso_state{focused_child = Ch};
set_active_child(modal, State = #iso_state{modal_focus = MF}, Ch) ->
    State#iso_state{modal_focus = MF#modal_focus{child = Ch}}.

%%====================================================================
%% Internal: Input handling
%%====================================================================

handle_input(escape, State = #iso_state{modal = Modal}) when Modal =/= undefined ->
    handle_close_modal(State);
handle_input(escape, State = #iso_state{fullscreen = #fullscreen{}, user_state = US}) ->
    exit_fullscreen(US, State, undefined);
handle_input({ctrl, $c}, State = #iso_state{callback = Cb, user_state = US}) ->
    case call_handler(Cb, quit, US) of
        {stop, _Reason, _NewUS} -> {stop, normal, State};
        _ -> {noreply, State}
    end;
handle_input({ctrl, $a}, State) ->
    case handle_input_select_all(State) of
        unhandled -> forward_event({ctrl, $a}, State);
        Result -> Result
    end;
handle_input(tab, State) ->
    handle_focus_next(State);
handle_input({key, btab}, State) ->
    handle_focus_prev(State);
handle_input(enter, State) ->
    handle_activate(State);
handle_input({key, page_up}, State = #iso_state{modal = Modal}) when Modal =/= undefined ->
    {noreply, State};
handle_input({key, page_down}, State = #iso_state{modal = Modal}) when Modal =/= undefined ->
    {noreply, State};
handle_input({key, page_up}, State) ->
    case handle_page(up, State) of
        unhandled -> forward_event({key, page_up}, State);
        Result -> Result
    end;
handle_input({key, page_down}, State) ->
    case handle_page(down, State) of
        unhandled -> forward_event({key, page_down}, State);
        Result -> Result
    end;
handle_input({key, {shift, Dir}}, State)
        when Dir =:= left; Dir =:= right; Dir =:= home; Dir =:= 'end' ->
    case handle_input_cursor(Dir, true, State) of
        unhandled -> forward_event({key, {shift, Dir}}, State);
        Result -> Result
    end;
handle_input({key, Dir}, State) when Dir =:= home; Dir =:= 'end' ->
    case handle_input_cursor(Dir, false, State) of
        unhandled -> forward_event({key, Dir}, State);
        Result -> Result
    end;
handle_input({key, Dir}, State) when Dir =:= up; Dir =:= down; Dir =:= left; Dir =:= right ->
    handle_arrow(Dir, State);
handle_input({char, Char}, State) when Char >= 32 ->
    handle_char_input(Char, State);
handle_input(backspace, State) ->
    handle_backspace(State);
handle_input(delete, State) ->
    handle_delete(State);
handle_input({mouse, click, left, Col, Row}, State = #iso_state{modal = Modal, bounds = Bounds}) when Modal =/= undefined ->
    handle_modal_click(Col, Row, Modal, Bounds, State);
handle_input({mouse, click, left, Col, Row}, State) ->
    handle_mouse_click(Col, Row, State);
handle_input({mouse, motion, left, Col, Row}, State) ->
    handle_input_drag(Col, Row, State);
handle_input({mouse, scroll, Dir, Col, Row}, State) when Dir =:= up; Dir =:= down ->
    handle_scroll(Dir, 1, Col, Row, State);
handle_input({mouse, scroll, _Dir, _Col, _Row}, State) ->
    {noreply, State};
handle_input({mouse, _, _, _, _}, State) ->
    {noreply, State};
handle_input(_Event, State = #iso_state{modal = Modal}) when Modal =/= undefined ->
    {noreply, State};
handle_input(Event, State) ->
    forward_event(Event, State).

%%====================================================================
%% Internal: Focus management (Tab = containers, Arrows = children)
%%====================================================================

handle_focus_next(State) ->
    {Tree, Current, _Ch, Ids, Where} = active_focus(State),
    {NewContainer, NewChild} = iso_engine:cycle_focus(next, Ids, Current, Tree),
    NewState0 = set_active(Where, State, Tree, NewContainer, NewChild, Ids),
    NewState = update_cursor_timer(NewState0),
    FinalState = render_diff(NewState),
    {noreply, FinalState}.

handle_focus_prev(State) ->
    {Tree, Current, _Ch, Ids, Where} = active_focus(State),
    {NewContainer, NewChild} = iso_engine:cycle_focus(prev, Ids, Current, Tree),
    NewState0 = set_active(Where, State, Tree, NewContainer, NewChild, Ids),
    NewState = update_cursor_timer(NewState0),
    FinalState = render_diff(NewState),
    {noreply, FinalState}.

handle_close_modal(State) ->
    NewState = deactivate_modal(State),
    FinalState = render_diff(NewState),
    {noreply, FinalState}.

%% Handle mouse clicks on modal elements
handle_modal_click(Col, Row, Modal, Bounds, State) ->
    case iso_hit:find_at(Modal, Col, Row, Bounds) of
        {button, ButtonId} ->
            handle_modal_button_click(ButtonId, Modal, State);
        _ ->
            {noreply, State}
    end.

handle_modal_button_click(ButtonId, Modal, State = #iso_state{callback = Cb, user_state = US}) ->
    %% Find the button in the modal and call user's handler
    case iso_focus:find_element(Modal, ButtonId) of
        #button{id = Id, on_click = Handler} ->
            case call_handler(Cb, {click, Id, Handler}, US) of
                {noreply, NewUS} ->
                    do_update(fun(_) -> NewUS end, State);
                {modal, NewModal, NewUS} ->
                    NewState = activate_modal(State#iso_state{user_state = NewUS}, NewModal),
                    FinalState = render_diff(NewState),
                    {noreply, FinalState};
                Other ->
                    handle_special_result(Other, State, undefined)
            end;
        _ ->
            {noreply, State}
    end.

%%====================================================================
%% Internal: Element activation
%%====================================================================

handle_activate(State = #iso_state{bounds = _Bounds, callback = Cb, user_state = US}) ->
    {Tree, Container, FocusedChild, _Ids, _Where} = active_focus(State),
    case iso_engine:activation_target(Tree, Container, FocusedChild) of
        #button{id = Id, on_click = Handler} ->
            case call_handler(Cb, {click, Id, Handler}, US) of
                {noreply, NewUS} ->
                    do_update(fun(_) -> NewUS end, State);
                {modal, Modal, NewUS} ->
                    NewState = activate_modal(State#iso_state{user_state = NewUS}, Modal),
                    FinalState = render_diff(NewState),
                    {noreply, FinalState};
                {switch, NewModule, Args} ->
                    do_switch(NewModule, Args, State);
                {push, NewModule, Args} ->
                    do_push(NewModule, Args, State);
                {push, NewModule, Args, NewUS} ->
                    do_push(NewModule, Args, State#iso_state{user_state = NewUS});
                {fullscreen, TargetId, NewUS} ->
                    enter_fullscreen(TargetId, NewUS, State, undefined);
                {toggle_fullscreen, TargetId, NewUS} ->
                    toggle_fullscreen(TargetId, NewUS, State, undefined);
                {exit_fullscreen, NewUS} ->
                    exit_fullscreen(NewUS, State, undefined);
                pop ->
                    do_pop(State);
                {stop, Reason, _NewUS} ->
                    {stop, Reason, State}
            end;
        #input{id = Id, value = Value, on_submit = Handler} ->
            case call_handler(Cb, {submit, Id, Value, Handler}, US) of
                {noreply, NewUS} -> do_update(fun(_) -> NewUS end, State);
                {switch, NewModule, Args} -> do_switch(NewModule, Args, State);
                {push, NewModule, Args} -> do_push(NewModule, Args, State);
                {push, NewModule, Args, NewUS} -> do_push(NewModule, Args, State#iso_state{user_state = NewUS});
                {fullscreen, TargetId, NewUS} -> enter_fullscreen(TargetId, NewUS, State, undefined);
                {toggle_fullscreen, TargetId, NewUS} -> toggle_fullscreen(TargetId, NewUS, State, undefined);
                {exit_fullscreen, NewUS} -> exit_fullscreen(NewUS, State, undefined);
                pop -> do_pop(State);
                {stop, Reason, _NewUS} -> {stop, Reason, State}
            end;
        #list{id = Id, items = Items, selected = SelIdx} ->
            Event = {list_select, Id, SelIdx, iso_engine:list_selected_item(Items, SelIdx)},
            case call_handler_with_debug(Cb, Event, US, State) of
                {unhandled, NewUS, NewState} ->
                    apply_view_update(NewUS, NewState, Tree);
                {handled, {noreply, NewUS}, _} ->
                    apply_view_update(NewUS, State, Tree);
                {handled, {modal, Modal, NewUS}, _} ->
                    NewState = activate_modal(State#iso_state{user_state = NewUS}, Modal),
                    FinalState = render_diff(NewState),
                    {noreply, FinalState};
                {handled, {switch, NewModule, Args}, _} ->
                    do_switch(NewModule, Args, State);
                {handled, {push, NewModule, Args}, _} ->
                    do_push(NewModule, Args, State);
                {handled, {push, NewModule, Args, NewUS}, _} ->
                    do_push(NewModule, Args, State#iso_state{user_state = NewUS});
                {handled, pop, _} ->
                    do_pop(State);
                {handled, {stop, Reason, _NewUS}, _} ->
                    {stop, Reason, State};
                {handled, Other, _} ->
                    handle_special_result(Other, State, Tree)
            end;
        #table{id = Id, selected_row = SelRow} = Table ->
            %% Enter on a table - activate the selected row
            RowData = iso_engine:table_row_data(Table, SelRow),
            Event = {table_activate, Id, SelRow, RowData},
            case call_handler_with_debug(Cb, Event, US, State) of
                {unhandled, NewUS, NewState} ->
                    apply_view_update(NewUS, NewState, Tree);
                {handled, {noreply, NewUS}, _} ->
                    apply_view_update(NewUS, State, Tree);
                {handled, {modal, Modal, NewUS}, _} ->
                    NewState = activate_modal(State#iso_state{user_state = NewUS}, Modal),
                    FinalState = render_diff(NewState),
                    {noreply, FinalState};
                {handled, {switch, NewModule, Args}, _} ->
                    do_switch(NewModule, Args, State);
                {handled, {push, NewModule, Args}, _} ->
                    do_push(NewModule, Args, State);
                {handled, {push, NewModule, Args, NewUS}, _} ->
                    do_push(NewModule, Args, State#iso_state{user_state = NewUS});
                {handled, pop, _} ->
                    do_pop(State);
                {handled, {stop, Reason, _NewUS}, _} ->
                    {stop, Reason, State};
                {handled, Other, _} ->
                    handle_special_result(Other, State, Tree)
            end;
        #tree{id = Id, selected = SelId} when SelId =/= undefined ->
            handle_tree_activate(Id, SelId, Cb, US, State, Tree);
        #tree{} ->
            {noreply, State};
        _ ->
            %% Check if we're in a tabs widget with a table (focused_child is tab id)
            handle_activate_in_tabs(Container, Tree, Cb, US, State)
    end.


%% Handle Enter when focused on a tab that contains a table
handle_activate_in_tabs(Container, Tree, Cb, US, State) ->
    case iso_focus:find_element(Tree, Container) of
        #tabs{tabs = TabList, active_tab = ActiveTab0} ->
            ActiveTab = iso_engine:resolve_active_tab(ActiveTab0, [T#tab.id || T <- TabList]),
            case lists:keyfind(ActiveTab, #tab.id, TabList) of
                #tab{content = Content} ->
                    case iso_engine:find_table_in_content(Content) of
                        {ok, #table{id = Id, selected_row = SelRow} = Table} ->
                            RowData = iso_engine:table_row_data(Table, SelRow),
                            Event = {table_activate, Id, SelRow, RowData},
                            case call_handler_with_debug(Cb, Event, US, State) of
                                {unhandled, NewUS, NewState} ->
                                    apply_view_update(NewUS, NewState, Tree);
                                {handled, {noreply, NewUS}, _} ->
                                    apply_view_update(NewUS, State, Tree);
                                {handled, {modal, Modal, NewUS}, _} ->
                                    NewState = activate_modal(State#iso_state{user_state = NewUS}, Modal),
                                    FinalState = render_diff(NewState),
                                    {noreply, FinalState};
                                {handled, {switch, NewModule, Args}, _} ->
                                    do_switch(NewModule, Args, State);
                                {handled, {push, NewModule, Args}, _} ->
                                    do_push(NewModule, Args, State);
                                {handled, {push, NewModule, Args, NewUS}, _} ->
                                    do_push(NewModule, Args, State#iso_state{user_state = NewUS});
                                {handled, pop, _} ->
                                    do_pop(State);
                                {handled, {stop, Reason, _NewUS}, _} ->
                                    {stop, Reason, State};
                                {handled, Other, _} ->
                                    handle_special_result(Other, State, Tree)
                            end;
                        false ->
                            {noreply, State}
                    end;
                false ->
                    {noreply, State}
            end;
        _ ->
            {noreply, State}
    end.

%%====================================================================
%% Internal: Arrow key navigation within container
%%====================================================================

handle_arrow(Dir, State = #iso_state{bounds = Bounds, callback = Cb, user_state = US}) ->
    case handle_input_cursor(Dir, false, State) of
        unhandled ->
            {Tree, Container, Child, _Ids, Where} = active_focus(State),
            handle_arrow_non_input(Dir, State, Container, Child, Tree, Bounds, Cb, US, Where);
        Result ->
            Result
    end.

handle_arrow_non_input(Dir, State, undefined, Child, Tree, _Bounds, _Cb, _US, modal) ->
    %% Modal subtree without a #box{focusable=true} container: navigate
    %% across the modal's flat list of focusable buttons/inputs.
    FlatIds = iso_focus:collect_children(#box{children = modal_children(Tree)}, undefined),
    case {Dir, FlatIds} of
        {_, []} -> {noreply, State};
        {up, _} ->
            NewChild = iso_focus:prev_focus(FlatIds, Child),
            navigate_modal_to_child(State, NewChild);
        {down, _} ->
            NewChild = iso_focus:next_focus(FlatIds, Child),
            navigate_modal_to_child(State, NewChild);
        {left, _} ->
            NewChild = iso_focus:prev_focus(FlatIds, Child),
            navigate_modal_to_child(State, NewChild);
        {right, _} ->
            NewChild = iso_focus:next_focus(FlatIds, Child),
            navigate_modal_to_child(State, NewChild)
    end;
handle_arrow_non_input(Dir, State, Container, Child, Tree, Bounds, Cb, US, _Where) ->
    %% Get children of current container
    ChildIds = iso_focus:collect_children(Tree, Container),
    case iso_focus:find_element(Tree, Container) of
        #tabs{id = Id, tabs = TabList, active_tab = ActiveTab} = Tabs ->
            %% For tabs: left/right navigates tabs, up/down navigates within active tab content
            case Dir of
                left ->
                    NewTabs = iso_engine:navigate_tabs(left, Tabs),
                    NewActiveTab = NewTabs#tabs.active_tab,
                    NewTree = iso_tree:update(Tree, Container, NewTabs),
                    NewUS = case call_handler(Cb, {tab_change, Id, NewActiveTab}, US) of
                        {noreply, S} -> S;
                        _ -> US
                    end,
                    NewState = State#iso_state{tree = NewTree, user_state = NewUS, focused_child = NewActiveTab},
                    FinalState = render_diff(NewState),
                    {noreply, FinalState};
                right ->
                    NewTabs = iso_engine:navigate_tabs(right, Tabs),
                    NewActiveTab = NewTabs#tabs.active_tab,
                    NewTree = iso_tree:update(Tree, Container, NewTabs),
                    NewUS = case call_handler(Cb, {tab_change, Id, NewActiveTab}, US) of
                        {noreply, S} -> S;
                        _ -> US
                    end,
                    NewState = State#iso_state{tree = NewTree, user_state = NewUS, focused_child = NewActiveTab},
                    FinalState = render_diff(NewState),
                    {noreply, FinalState};
                UpOrDown when UpOrDown =:= up; UpOrDown =:= down ->
                    %% Navigate within active tab content (e.g., table rows)
                    %% Default to first tab if active_tab is undefined
                    EffectiveTab = case ActiveTab of
                        undefined -> case TabList of [#tab{id = First}|_] -> First; [] -> undefined end;
                        _ -> ActiveTab
                    end,
                    case lists:keyfind(EffectiveTab, #tab.id, TabList) of
                        #tab{content = Content} ->
                            case iso_engine:find_table_in_content(Content) of
                                {ok, Table} ->
                                    NewTable = iso_engine:navigate_table(UpOrDown, Table, Tree, Bounds),
                                    NewTabs = iso_engine:update_tab_content(Tabs, EffectiveTab, Table, NewTable),
                                    NewTree = iso_tree:update(Tree, Container, NewTabs),
                                    NewState = State#iso_state{tree = NewTree},
                                    FinalState = render_diff(NewState),
                                    {noreply, FinalState};
                                false ->
                                    {noreply, State}
                            end;
                        false ->
                            {noreply, State}
                    end
            end;
        #box{} ->
            %% For box, navigate focused child widgets before switching child focus.
            case iso_engine:navigate_element(Dir, Child, Tree, Bounds, Cb, US) of
                {ok, NewTree, NewUS} ->
                    case _Where of
                        main ->
                            apply_view_update(NewUS, State#iso_state{tree = NewTree}, NewTree);
                        modal ->
                            NewState = set_active_tree(modal,
                                                       State#iso_state{user_state = NewUS},
                                                       NewTree),
                            {noreply, render_diff(NewState)}
                    end;
                unhandled ->
                    case Dir of
                        up ->
                            NewChild = iso_focus:prev_focus(ChildIds, Child),
                            NewState0 = set_active_child(_Where, State, NewChild),
                            NewState = update_cursor_timer(NewState0),
                            FinalState = render_diff(NewState),
                            {noreply, FinalState};
                        down ->
                            NewChild = iso_focus:next_focus(ChildIds, Child),
                            NewState0 = set_active_child(_Where, State, NewChild),
                            NewState = update_cursor_timer(NewState0),
                            FinalState = render_diff(NewState),
                            {noreply, FinalState};
                        _ ->
                            {noreply, State}
                    end
            end;
        _ ->
            %% Container is a navigable element (table, list, tree, scroll)
            case iso_engine:navigate_element(Dir, Container, Tree, Bounds, Cb, US) of
                {ok, NewTree, NewUS} ->
                    case _Where of
                        main ->
                            apply_view_update(NewUS, State#iso_state{tree = NewTree}, NewTree);
                        modal ->
                            NewState = set_active_tree(modal,
                                                       State#iso_state{user_state = NewUS},
                                                       NewTree),
                            {noreply, render_diff(NewState)}
                    end;
                unhandled ->
                    {noreply, State}
            end
    end.

navigate_modal_to_child(State, NewChild) ->
    NewState0 = set_active_child(modal, State, NewChild),
    NewState = update_cursor_timer(NewState0),
    {noreply, render_diff(NewState)}.

handle_page(Dir, State = #iso_state{focused_container = Container, focused_child = Child,
                                    tree = Tree, bounds = Bounds,
                                    callback = Cb, user_state = US}) ->
    case iso_focus:find_element(Tree, Container) of
        #tabs{tabs = TabList, active_tab = ActiveTab0} = Tabs ->
            ActiveTab = iso_engine:resolve_active_tab(ActiveTab0, [T#tab.id || T <- TabList]),
            case lists:keyfind(ActiveTab, #tab.id, TabList) of
                #tab{content = Content} ->
                    case iso_engine:page_navigate_tab_content(Dir, Container, Tabs, Content, Tree, Bounds, Cb, US) of
                        {ok, NewTree, NewUS} ->
                            apply_view_update(NewUS, State#iso_state{tree = NewTree}, NewTree);
                        unhandled ->
                            unhandled
                    end;
                false ->
                    unhandled
            end;
        #box{} ->
            case iso_engine:page_navigate_element(Dir, Child, Tree, Bounds, Cb, US) of
                {ok, NewTree, NewUS} ->
                    apply_view_update(NewUS, State#iso_state{tree = NewTree}, NewTree);
                unhandled ->
                    unhandled
            end;
        _ ->
            case iso_engine:page_navigate_element(Dir, Container, Tree, Bounds, Cb, US) of
                {ok, NewTree, NewUS} ->
                    apply_view_update(NewUS, State#iso_state{tree = NewTree}, NewTree);
                unhandled ->
                    unhandled
            end
    end.










%% Update table in tab content


%%====================================================================
%% Internal: Text input handling
%%====================================================================

handle_char_input(Char, State = #iso_state{callback = Cb, user_state = US}) ->
    {Tree, _FC, _Ch, _Ids, Where} = active_focus(State),
    InputId = focused_input_id(State),
    case iso_engine:apply_char_input(Tree, InputId, Char) of
        {ok, NewTree, Id, NewValue} ->
            NewUS = case call_handler(Cb, {input, Id, NewValue}, US) of
                {noreply, S} -> S;
                _ -> US
            end,
            NewState = set_active_tree(Where, State#iso_state{user_state = NewUS}, NewTree),
            FinalState = render_diff(NewState),
            {noreply, FinalState};
        false ->
            forward_event({char, Char}, State)
    end.

handle_backspace(State = #iso_state{callback = Cb, user_state = US}) ->
    {Tree, _FC, _Ch, _Ids, Where} = active_focus(State),
    InputId = focused_input_id(State),
    case iso_engine:apply_backspace(Tree, InputId) of
        {ok, NewTree, Id, NewValue} ->
            NewUS = case call_handler(Cb, {input, Id, NewValue}, US) of
                {noreply, S} -> S;
                _ -> US
            end,
            NewState = set_active_tree(Where, State#iso_state{user_state = NewUS}, NewTree),
            FinalState = render_diff(NewState),
            {noreply, FinalState};
        false ->
            {noreply, State}
    end.

handle_delete(State = #iso_state{callback = Cb, user_state = US}) ->
    {Tree, _FC, _Ch, _Ids, Where} = active_focus(State),
    InputId = focused_input_id(State),
    case iso_engine:apply_delete_input(Tree, InputId) of
        {ok, NewTree, Id, NewValue} ->
            NewUS = case call_handler(Cb, {input, Id, NewValue}, US) of
                {noreply, S} -> S;
                _ -> US
            end,
            NewState = set_active_tree(Where, State#iso_state{user_state = NewUS}, NewTree),
            FinalState = render_diff(NewState),
            {noreply, FinalState};
        false ->
            {noreply, State}
    end.

handle_input_cursor(Dir, _Select, _State)
        when Dir =/= left, Dir =/= right, Dir =/= home, Dir =/= 'end' ->
    unhandled;
handle_input_cursor(Dir, Select, State) ->
    {Tree, _FC, _Ch, _Ids, Where} = active_focus(State),
    case focused_input_id(State) of
        undefined ->
            unhandled;
        InputId ->
            case iso_engine:move_input_cursor(Tree, InputId, Dir, Select) of
                {ok, NewTree} ->
                    render_input_state(Where, NewTree, State);
                false ->
                    unhandled
            end
    end.

handle_input_select_all(State) ->
    {Tree, _FC, _Ch, _Ids, Where} = active_focus(State),
    case focused_input_id(State) of
        undefined ->
            unhandled;
        InputId ->
            case iso_engine:select_all_input(Tree, InputId) of
                {ok, NewTree} ->
                    render_input_state(Where, NewTree, State);
                false ->
                    unhandled
            end
    end.

handle_input_drag(_Col, _Row, State = #iso_state{modal = Modal}) when Modal =/= undefined ->
    {noreply, State};
handle_input_drag(Col, _Row, State = #iso_state{tree = Tree, bounds = Bounds}) ->
    case focused_input_id(State) of
        undefined ->
            {noreply, State};
        InputId ->
            case iso_focus:find_element(Tree, InputId) of
                #input{} = Input ->
                    case iso_bounds:find_element_bounds(Tree, InputId, Bounds) of
                        {ok, InputBounds} ->
                            Pos = input_position_from_col(Input, InputBounds, Col),
                            case iso_engine:position_input_cursor(Tree, InputId, Pos, true) of
                                {ok, NewTree} -> render_input_state(main, NewTree, State);
                                false -> {noreply, State}
                            end;
                        not_found ->
                            {noreply, State}
                    end;
                _ ->
                    {noreply, State}
            end
    end.

render_input_state(Where, NewTree, State) ->
    NewState0 = set_active_tree(Where, State, NewTree),
    NewState = update_cursor_timer(NewState0),
    FinalState = render_diff(NewState),
    {noreply, FinalState}.

focused_input_id(State) ->
    {Tree, FocusedContainer, FocusedChild, _Ids, _Where} = active_focus(State),
    case iso_focus:find_element(Tree, FocusedChild) of
        #input{} ->
            FocusedChild;
        _ ->
            case iso_focus:find_element(Tree, FocusedContainer) of
                #input{} -> FocusedContainer;
                _ -> undefined
            end
    end.

input_position_from_col(#input{value = Value}, #bounds{x = X}, Col) ->
    Len = length(input_chars(Value)),
    min(max(0, Col - X - 2), Len).

input_chars(Value) when is_binary(Value) ->
    unicode:characters_to_list(Value);
input_chars(Value) when is_list(Value) ->
    unicode:characters_to_list(unicode:characters_to_binary(Value)).


%%====================================================================
%% Internal: Mouse handling
%%====================================================================

handle_scroll(Dir, Lines, Col, Row, State = #iso_state{tree = Tree, bounds = Bounds}) ->
    case iso_hit:find_at(Tree, Col, Row, Bounds) of
        {list_item, ListId, _ItemIdx} ->
            scroll_list(Dir, Lines, ListId, State);
        {list, ListId} ->
            scroll_list(Dir, Lines, ListId, State);
        {table_row, TableId, _RowIdx} ->
            scroll_table(Dir, Lines, TableId, State);
        {table, TableId} ->
            scroll_table(Dir, Lines, TableId, State);
        {tree_toggle, TreeId, _NodeId} ->
            scroll_tree(Dir, Lines, TreeId, State);
        {tree_node, TreeId, _NodeId} ->
            scroll_tree(Dir, Lines, TreeId, State);
        {tree, TreeId} ->
            scroll_tree(Dir, Lines, TreeId, State);
        _ ->
            case iso_engine:find_scroll_at(Tree, Col, Row, Bounds) of
                {ok, ScrollId} ->
                    scroll_container(Dir, Lines, ScrollId, State);
                not_found ->
                    scroll_focused(Dir, Lines, State)
            end
    end.

scroll_list(Dir, Lines, ListId, State = #iso_state{tree = Tree, bounds = Bounds,
                                                   callback = Cb, user_state = US}) ->
    case iso_focus:find_element(Tree, ListId) of
        #list{} = List ->
            NewList = iso_engine:navigate_list(Dir, Lines, List, Tree, Bounds),
            NewTree = iso_tree:update(Tree, ListId, NewList),
            Event = {list_select, ListId, NewList#list.selected,
                     iso_engine:list_selected_item(NewList#list.items, NewList#list.selected)},
            NewUS = iso_engine:selection_user_state(Cb, Event, US),
            apply_view_update(NewUS, State#iso_state{tree = NewTree}, NewTree);
        _ ->
            {noreply, State}
    end.

scroll_table(Dir, Lines, TableId, State = #iso_state{tree = Tree, bounds = Bounds,
                                                     callback = Cb, user_state = US}) ->
    case iso_focus:find_element(Tree, TableId) of
        #table{} = Table ->
            NewTable = iso_engine:navigate_table(Dir, Lines, Table, Tree, Bounds),
            NewTree = iso_tree:update(Tree, TableId, NewTable),
            Event = {table_select, TableId, NewTable#table.selected_row,
                     iso_engine:table_row_data(NewTable, NewTable#table.selected_row)},
            NewUS = iso_engine:selection_user_state(Cb, Event, US),
            apply_view_update(NewUS, State#iso_state{tree = NewTree}, NewTree);
        _ ->
            {noreply, State}
    end.

scroll_tree(Dir, Lines, TreeId, State = #iso_state{tree = Tree, bounds = Bounds,
                                                   user_state = US}) ->
    case iso_focus:find_element(Tree, TreeId) of
        #tree{} = TreeEl ->
            NewTreeEl = iso_engine:scroll_tree(Dir, Lines, TreeEl, Tree, Bounds),
            NewTree = iso_tree:update(Tree, TreeId, NewTreeEl),
            apply_view_update(US, State#iso_state{tree = NewTree}, NewTree);
        _ ->
            {noreply, State}
    end.

scroll_container(Dir, Lines, ScrollId, State = #iso_state{tree = Tree, bounds = Bounds}) ->
    case iso_focus:find_element(Tree, ScrollId) of
        #scroll{} = Scroll ->
            NewScroll = iso_engine:navigate_scroll(Dir, Lines, Scroll, Tree, Bounds),
            NewTree = iso_tree:update(Tree, ScrollId, NewScroll),
            NewState = State#iso_state{tree = NewTree},
            FinalState = render_diff(NewState),
            {noreply, FinalState};
        _ ->
            {noreply, State}
    end.

scroll_focused(Dir, Lines, State = #iso_state{tree = Tree,
                                              focused_child = FocusedChild,
                                              focused_container = FocusedContainer}) ->
    case iso_engine:scroll_target(Tree, FocusedChild, FocusedContainer) of
        {list, Id} ->
            scroll_list(Dir, Lines, Id, State);
        {table, Id} ->
            scroll_table(Dir, Lines, Id, State);
        {tree, Id} ->
            scroll_tree(Dir, Lines, Id, State);
        {scroll, Id} ->
            scroll_container(Dir, Lines, Id, State);
        undefined ->
            {noreply, State}
    end.


handle_mouse_click(Col, Row, State = #iso_state{tree = Tree, bounds = Bounds,
                                                callback = Cb, user_state = US}) ->
    case iso_hit:find_at(Tree, Col, Row, Bounds) of
        {tab, TabsId, TabId} ->
            case iso_focus:find_element(Tree, TabsId) of
                #tabs{} = Tabs ->
                    NewTabs = Tabs#tabs{active_tab = TabId},
                    NewTree = iso_tree:update(Tree, TabsId, NewTabs),
                    NewUS = case call_handler(Cb, {tab_change, TabsId, TabId}, US) of
                        {noreply, S} -> S;
                        _ -> US
                    end,
                    NewState = State#iso_state{tree = NewTree,
                                               user_state = NewUS,
                                               focused_container = TabsId,
                                               focused_child = TabId},
                    FinalState = render_diff(NewState),
                    {noreply, FinalState};
                _ -> {noreply, State}
            end;
        {tabs_container, TabsId} ->
            %% Clicked on tabs widget but not on a specific tab
            ChildIds = iso_focus:collect_children(Tree, TabsId),
            FirstChild = case ChildIds of [C|_] -> C; [] -> undefined end,
            NewState = State#iso_state{focused_container = TabsId, focused_child = FirstChild},
            FinalState = render_diff(NewState),
            {noreply, FinalState};
        {box, BoxId} ->
            %% Clicked on box container (border or empty space)
            ChildIds = iso_focus:collect_children(Tree, BoxId),
            FirstChild = case ChildIds of [C|_] -> C; [] -> undefined end,
            NewState = State#iso_state{focused_container = BoxId, focused_child = FirstChild},
            FinalState = render_diff(NewState),
            {noreply, FinalState};
        {button, ButtonId} ->
            %% Find which container owns this button
            Container = iso_engine:focus_container_for(Tree, ButtonId),
            NewState = State#iso_state{focused_container = Container, focused_child = ButtonId},
            handle_activate(NewState);
        {input, InputId} ->
            %% Find which container owns this input
            Container = iso_engine:focus_container_for(Tree, InputId),
            case iso_focus:find_element(Tree, InputId) of
                #input{} = Input ->
                    case iso_bounds:find_element_bounds(Tree, InputId, Bounds) of
                        {ok, InputBounds} ->
                            Pos = input_position_from_col(Input, InputBounds, Col),
                            case iso_engine:start_input_selection(Tree, InputId, Pos) of
                                {ok, NewTree} ->
                                    NewState0 = State#iso_state{
                                        tree = NewTree,
                                        focused_container = Container,
                                        focused_child = InputId
                                    },
                                    NewState = update_cursor_timer(NewState0),
                                    FinalState = render_diff(NewState),
                                    {noreply, FinalState};
                                false ->
                                    {noreply, State}
                            end;
                        not_found ->
                            {noreply, State}
                    end;
                _ ->
                    {noreply, State}
            end;
        {table_header, TableId, ColumnId} ->
            case iso_focus:find_element(Tree, TableId) of
                #table{} = Table ->
                    Container = iso_engine:focus_container_for(Tree, TableId),
                    FocusedState = State#iso_state{focused_container = Container,
                                                  focused_child = TableId},
                    SortedTable = iso_el_table:toggle_sort(Table, ColumnId),
                    case SortedTable =:= Table of
                        false ->
                            NewTree = iso_tree:update(Tree, TableId, SortedTable),
                            Event = {table_header_click, TableId, ColumnId},
                            NewUS = iso_engine:selection_user_state(Cb, Event, US),
                            apply_view_update(NewUS, FocusedState#iso_state{tree = NewTree}, NewTree);
                        true ->
                            Event = {table_header_click, TableId, ColumnId},
                            case call_handler_with_debug(Cb, Event, US, FocusedState) of
                                {unhandled, NewUS, NewState} ->
                                    do_update(fun(_) -> NewUS end, NewState);
                                {handled, {noreply, NewUS}, _} ->
                                    do_update(fun(_) -> NewUS end, FocusedState);
                                {handled, {modal, Modal, NewUS}, _} ->
                                    NewState = activate_modal(FocusedState#iso_state{user_state = NewUS}, Modal),
                                    FinalState = render_diff(NewState),
                                    {noreply, FinalState};
                                {handled, {switch, NewModule, Args}, _} ->
                                    do_switch(NewModule, Args, FocusedState);
                                {handled, {push, NewModule, Args}, _} ->
                                    do_push(NewModule, Args, FocusedState);
                                {handled, {push, NewModule, Args, NewUS}, _} ->
                                    do_push(NewModule, Args, FocusedState#iso_state{user_state = NewUS});
                                {handled, pop, _} ->
                                    do_pop(FocusedState);
                                {handled, {stop, Reason, _NewUS}, _} ->
                                    {stop, Reason, FocusedState};
                                {handled, Other, _} ->
                                    handle_special_result(Other, FocusedState, undefined)
                            end
                    end;
                _ -> {noreply, State}
            end;
        {table_row, TableId, RowIdx} ->
            %% Click on a specific table row.
            case iso_focus:find_element(Tree, TableId) of
                #table{} = Table ->
                    Container = iso_engine:focus_container_for(Tree, TableId),
                    FocusedState = State#iso_state{focused_container = Container,
                                                  focused_child = TableId},
                    case Table#table.activate_on_reclick andalso
                         Table#table.selected_row =:= RowIdx of
                        true ->
                            handle_activate(FocusedState);
                        false ->
                            NewTable = Table#table{selected_row = RowIdx},
                            NewTree = iso_tree:update(Tree, TableId, NewTable),
                            Event = {table_select, TableId, RowIdx, iso_engine:table_row_data(NewTable, RowIdx)},
                            NewUS = iso_engine:selection_user_state(Cb, Event, US),
                            apply_view_update(NewUS, FocusedState#iso_state{tree = NewTree}, NewTree)
                    end;
                _ -> {noreply, State}
            end;
        {table, TableId} ->
            %% Clicked on table but not on a specific row
            Container = iso_engine:focus_container_for(Tree, TableId),
            NewState = State#iso_state{focused_container = Container, focused_child = TableId},
            FinalState = render_diff(NewState),
            {noreply, FinalState};
        {list_item, ListId, ItemIdx} ->
            %% Click on a specific list item - select it and notify callback
            case iso_focus:find_element(Tree, ListId) of
                #list{} = List ->
                    NewList = List#list{selected = ItemIdx},
                    NewTree = iso_tree:update(Tree, ListId, NewList),
                    Container = iso_engine:focus_container_for(Tree, ListId),
                    Event = {list_select, ListId, ItemIdx,
                             iso_engine:list_selected_item(NewList#list.items, ItemIdx)},
                    NewUS = iso_engine:selection_user_state(Cb, Event, US),
                    apply_view_update(NewUS, State#iso_state{tree = NewTree,
                                               focused_container = Container,
                                               focused_child = ListId}, NewTree);
                _ -> {noreply, State}
            end;
        {list, ListId} ->
            %% Clicked on list but not on a specific item
            Container = iso_engine:focus_container_for(Tree, ListId),
            NewState = State#iso_state{focused_container = Container, focused_child = ListId},
            FinalState = render_diff(NewState),
            {noreply, FinalState};
        {tree_toggle, TreeId, NodeId} ->
            case iso_focus:find_element(Tree, TreeId) of
                #tree{} = TreeEl ->
                    Container = iso_engine:focus_container_for(Tree, TreeId),
                    FocusedState = State#iso_state{focused_container = Container,
                                                  focused_child = TreeId},
                    SelectedTreeEl = iso_tree_nav:select(NodeId, TreeEl, Bounds),
                    NewTreeEl = iso_tree_nav:toggle_selected(SelectedTreeEl, Bounds),
                    NewTree = iso_tree:update(Tree, TreeId, NewTreeEl),
                    NewUS = iso_engine:maybe_tree_selection_user_state(Cb, TreeEl, NewTreeEl, US),
                    apply_view_update(NewUS, FocusedState#iso_state{tree = NewTree,
                                                                    user_state = NewUS}, NewTree);
                _ ->
                    {noreply, State}
            end;
        {tree_node, TreeId, NodeId} ->
            case iso_focus:find_element(Tree, TreeId) of
                #tree{} = TreeEl ->
                    Container = iso_engine:focus_container_for(Tree, TreeId),
                    FocusedState = State#iso_state{focused_container = Container,
                                                  focused_child = TreeId},
                    WasSelected = TreeEl#tree.selected =:= NodeId,
                    NewTreeEl = iso_tree_nav:select(NodeId, TreeEl, Bounds),
                    NewTree = iso_tree:update(Tree, TreeId, NewTreeEl),
                    NewUS = iso_engine:maybe_tree_selection_user_state(Cb, TreeEl, NewTreeEl, US),
                    NewState = FocusedState#iso_state{tree = NewTree, user_state = NewUS},
                    case WasSelected of
                        true ->
                            handle_tree_activate(TreeId, NodeId, Cb, NewUS, NewState, NewTree);
                        false ->
                            apply_view_update(NewUS, NewState, NewTree)
                    end;
                _ ->
                    {noreply, State}
            end;
        {tree, TreeId} ->
            Container = iso_engine:focus_container_for(Tree, TreeId),
            NewState = State#iso_state{focused_container = Container, focused_child = TreeId},
            FinalState = render_diff(NewState),
            {noreply, FinalState};
        {status_bar_item, Key} ->
            handle_shortcut_click(Key, State);
        not_found ->
            forward_event({mouse, click, left, Col, Row}, State, Tree)
    end.

handle_tree_activate(TreeId, NodeId, Cb, US, State, MergeFromTree) ->
    Event = {tree_activate, TreeId, NodeId},
    case call_handler_with_debug(Cb, Event, US, State) of
        {unhandled, NewUS, NewState} ->
            apply_view_update(NewUS, NewState, MergeFromTree);
        {handled, {noreply, NewUS}, _} ->
            apply_view_update(NewUS, State, MergeFromTree);
        {handled, {modal, Modal, NewUS}, _} ->
            NewState = activate_modal(State#iso_state{user_state = NewUS}, Modal),
            FinalState = render_diff(NewState),
            {noreply, FinalState};
        {handled, {switch, NewModule, Args}, _} ->
            do_switch(NewModule, Args, State);
        {handled, {push, NewModule, Args}, _} ->
            do_push(NewModule, Args, State);
        {handled, {push, NewModule, Args, NewUS}, _} ->
            do_push(NewModule, Args, State#iso_state{user_state = NewUS});
        {handled, pop, _} ->
            do_pop(State);
        {handled, {stop, Reason, _NewUS}, _} ->
            {stop, Reason, State};
        {handled, Other, _} ->
            handle_special_result(Other, State, MergeFromTree)
    end.

%%====================================================================
%% Internal: State update and rendering
%%====================================================================

do_update(UpdateFun, State = #iso_state{user_state = US}) ->
    NewUS = UpdateFun(US),
    NewState = rebuild_view_state(NewUS, State, undefined),
    FinalState = render_diff(NewState),
    {noreply, FinalState}.

apply_view_update(NewUS, State, MergeFromTree) ->
    NewState = rebuild_view_state(NewUS, State, MergeFromTree),
    FinalState = render_diff(NewState),
    {noreply, FinalState}.

rebuild_view_state(NewUS, State = #iso_state{fullscreen = undefined}, MergeFromTree) ->
    BaseTree = rebuild_base_tree(NewUS, State, MergeFromTree),
    {Container, Child, ContainerIds} =
        resolve_focus(BaseTree, State#iso_state.focused_container,
                      State#iso_state.focused_child),
    State#iso_state{
        user_state = NewUS,
        tree = BaseTree,
        focused_container = Container,
        focused_child = Child,
        container_ids = ContainerIds
    };
rebuild_view_state(NewUS, State = #iso_state{fullscreen = FS0}, MergeFromTree) ->
    BaseTree = rebuild_base_tree(NewUS, State, MergeFromTree),
    case fullscreen_tree(BaseTree, FS0#fullscreen.id) of
        {ok, FullTree} ->
            {Container, Child, ContainerIds} =
                resolve_focus(FullTree, State#iso_state.focused_container,
                              State#iso_state.focused_child),
            State#iso_state{
                user_state = NewUS,
                tree = FullTree,
                fullscreen = FS0#fullscreen{tree = BaseTree},
                focused_container = Container,
                focused_child = Child,
                container_ids = ContainerIds
            };
        not_found ->
            {Container, Child, ContainerIds} =
                resolve_focus(BaseTree, FS0#fullscreen.focused_container,
                              FS0#fullscreen.focused_child),
            State#iso_state{
                user_state = NewUS,
                tree = BaseTree,
                fullscreen = undefined,
                focused_container = Container,
                focused_child = Child,
                container_ids = ContainerIds
            }
    end.

rebuild_base_tree(NewUS, State = #iso_state{callback = Cb}, MergeFromTree) ->
    SourceTree = merge_source_tree(State, MergeFromTree),
    ContextTree = case SourceTree of
        undefined -> State#iso_state.tree;
        _ -> SourceTree
    end,
    RawTree = iso_engine:call_view(Cb, NewUS, ContextTree),
    case SourceTree of
        undefined -> RawTree;
        OldTree -> iso_tree:merge_state(OldTree, RawTree)
    end.

merge_source_tree(#iso_state{fullscreen = undefined}, undefined) ->
    undefined;
merge_source_tree(#iso_state{fullscreen = undefined}, MergeFromTree) ->
    MergeFromTree;
merge_source_tree(#iso_state{fullscreen = #fullscreen{id = Id, tree = BaseTree},
                             tree = FullTree}, undefined) ->
    iso_tree:update(BaseTree, Id, FullTree);
merge_source_tree(#iso_state{fullscreen = #fullscreen{id = Id, tree = BaseTree}}, MergeFromTree) ->
    iso_tree:update(BaseTree, Id, MergeFromTree).

resolve_focus(Tree, CurrentContainer, CurrentChild) ->
    ContainerIds = iso_focus:collect_containers(Tree),
    Container = case lists:member(CurrentContainer, ContainerIds) of
        true -> CurrentContainer;
        false -> case ContainerIds of [C | _] -> C; [] -> undefined end
    end,
    ChildIds = iso_focus:collect_children(Tree, Container),
    Child = case lists:member(CurrentChild, ChildIds) of
        true -> CurrentChild;
        false -> case ChildIds of [Ch | _] -> Ch; [] -> undefined end
    end,
    {Container, Child, ContainerIds}.

fullscreen_focus(Tree, Id) ->
    ContainerIds = iso_focus:collect_containers(Tree),
    Container = case lists:member(Id, ContainerIds) of
        true -> Id;
        false -> case ContainerIds of [C | _] -> C; [] -> undefined end
    end,
    ChildIds = iso_focus:collect_children(Tree, Container),
    Child = case ChildIds of [Ch | _] -> Ch; [] -> undefined end,
    {Container, Child, ContainerIds}.

enter_fullscreen(Id, NewUS, State, MergeFromTree) ->
    BaseTree = rebuild_base_tree(NewUS, State, MergeFromTree),
    case fullscreen_tree(BaseTree, Id) of
        {ok, FullTree} ->
            {Container, Child, ContainerIds} = fullscreen_focus(FullTree, Id),
            Saved = fullscreen_saved_state(Id, BaseTree, State),
            NewState = State#iso_state{
                user_state = NewUS,
                tree = FullTree,
                fullscreen = Saved,
                focused_container = Container,
                focused_child = Child,
                container_ids = ContainerIds,
                prev_screen = undefined
            },
            iso_tty:clear(),
            {noreply, render_diff(NewState)};
        not_found ->
            apply_view_update(NewUS, State, MergeFromTree)
    end.

fullscreen_saved_state(Id, BaseTree, #iso_state{fullscreen = undefined} = State) ->
    #fullscreen{
        id = Id,
        tree = BaseTree,
        focused_container = State#iso_state.focused_container,
        focused_child = State#iso_state.focused_child,
        container_ids = State#iso_state.container_ids
    };
fullscreen_saved_state(Id, BaseTree, #iso_state{fullscreen = FS}) ->
    FS#fullscreen{id = Id, tree = BaseTree}.

toggle_fullscreen(Id, NewUS, State = #iso_state{fullscreen = #fullscreen{id = Id}},
                  MergeFromTree) ->
    exit_fullscreen(NewUS, State, MergeFromTree);
toggle_fullscreen(Id, NewUS, State, MergeFromTree) ->
    enter_fullscreen(Id, NewUS, State, MergeFromTree).

exit_fullscreen(NewUS, State = #iso_state{fullscreen = undefined}, MergeFromTree) ->
    apply_view_update(NewUS, State, MergeFromTree);
exit_fullscreen(NewUS, State = #iso_state{fullscreen = FS, callback = Cb,
                                          tree = FullTree}, _MergeFromTree) ->
    BaseWithActive = iso_tree:update(FS#fullscreen.tree, FS#fullscreen.id, FullTree),
    BaseTree = iso_tree:merge_state(BaseWithActive, iso_engine:call_view(Cb, NewUS, BaseWithActive)),
    {Container, Child, ContainerIds} =
        resolve_focus(BaseTree, FS#fullscreen.focused_container,
                      FS#fullscreen.focused_child),
    NewState = State#iso_state{
        user_state = NewUS,
        tree = BaseTree,
        fullscreen = undefined,
        focused_container = Container,
        focused_child = Child,
        container_ids = ContainerIds,
        prev_screen = undefined
    },
    iso_tty:clear(),
    {noreply, render_diff(NewState)}.

fullscreen_tree(Tree, Id) ->
    case iso_focus:find_element(Tree, Id) of
        undefined -> not_found;
        Element -> {ok, stretch_fullscreen(Element)}
    end.

stretch_fullscreen(#box{} = E) -> E#box{x = 0, y = 0, width = fill, height = fill};
stretch_fullscreen(#panel{} = E) -> E#panel{x = 0, y = 0, width = fill, height = fill};
stretch_fullscreen(#vbox{} = E) -> E#vbox{x = 0, y = 0, width = fill, height = fill};
stretch_fullscreen(#hbox{} = E) -> E#hbox{x = 0, y = 0, width = fill, height = fill};
stretch_fullscreen(#scroll{} = E) -> E#scroll{x = 0, y = 0, width = fill, height = fill};
stretch_fullscreen(#tabs{} = E) -> E#tabs{x = 0, y = 0, width = fill, height = fill};
stretch_fullscreen(#table{} = E) -> E#table{x = 0, y = 0, width = fill, height = fill};
stretch_fullscreen(#list{} = E) -> E#list{x = 0, y = 0, width = fill, height = fill};
stretch_fullscreen(#tree{} = E) -> E#tree{x = 0, y = 0, width = fill, height = fill};
stretch_fullscreen(#text{} = E) -> E#text{x = 0, y = 0, width = fill, height = fill};
stretch_fullscreen(#button{} = E) -> E#button{x = 0, y = 0, width = fill, height = fill};
stretch_fullscreen(#input{} = E) -> E#input{x = 0, y = 0, width = fill, height = fill};
stretch_fullscreen(#header{} = E) -> E#header{x = 0, y = 0, width = fill, height = fill};
stretch_fullscreen(#status_bar{} = E) -> E#status_bar{x = 0, y = 0, width = fill, height = fill};
stretch_fullscreen(#progress_bar{} = E) -> E#progress_bar{x = 0, y = 0, width = fill, height = fill};
stretch_fullscreen(#sparkline{} = E) -> E#sparkline{x = 0, y = 0, width = fill, height = fill};
stretch_fullscreen(#stat_row{} = E) -> E#stat_row{x = 0, y = 0, width = fill, height = fill};
stretch_fullscreen(Element) -> Element.

%% Switch to a completely different callback module
do_switch(NewModule, Args, State) ->
    try iso_engine:init_focus_state(NewModule, Args) of
        {NewUS, NewTree, ContainerIds, NewContainer, NewChild} ->
            NewState = State#iso_state{
                callback = NewModule,
                user_state = NewUS,
                tree = NewTree,
                focused_container = NewContainer,
                focused_child = NewChild,
                container_ids = ContainerIds,
                modal = undefined,
                modal_focus = undefined,
                debug_event = undefined,
                fullscreen = undefined,
                prev_screen = undefined  %% Reset screen buffer on switch
            },
            %% Clear screen before rendering new view (different layout may leave garbage)
            iso_tty:clear(),
            FinalState = render_diff(NewState),
            {noreply, FinalState}
    catch
        error:{badmatch, {error, Reason}} ->
            error_logger:error_msg("Failed to switch to ~p: ~p~n", [NewModule, Reason]),
            {noreply, State};
        Class:Reason:Stack ->
            error_logger:error_msg("Crash switching to ~p: ~p:~p~n~p~n",
                                   [NewModule, Class, Reason, Stack]),
            {noreply, State}
    end.

%% Push current view onto stack and switch to new module
do_push(NewModule, Args, State = #iso_state{
        callback = Cb, user_state = US, tree = Tree,
        focused_container = FC, focused_child = FCh,
        container_ids = CIds, nav_stack = Stack}) ->
    SavedTree = case State#iso_state.fullscreen of
        #fullscreen{tree = BaseTree} -> BaseTree;
        undefined -> Tree
    end,
    %% Save current view state to stack
    Entry = #nav_entry{
        callback = Cb,
        user_state = US,
        tree = SavedTree,
        focused_container = FC,
        focused_child = FCh,
        container_ids = CIds
    },
    NewStack = [Entry | Stack],
    %% Switch to new module (reuse do_switch logic but preserve stack)
    try NewModule:init(Args) of
        {ok, NewUS} ->
            NewTree = iso_engine:call_view(NewModule, NewUS, undefined),
            ContainerIds = iso_focus:collect_containers(NewTree),
            NewContainer = case ContainerIds of [C|_] -> C; [] -> undefined end,
            ChildIds = iso_focus:collect_children(NewTree, NewContainer),
            NewChild = case ChildIds of [Ch|_] -> Ch; [] -> undefined end,
            NewState = State#iso_state{
                callback = NewModule,
                user_state = NewUS,
                tree = NewTree,
                focused_container = NewContainer,
                focused_child = NewChild,
                container_ids = ContainerIds,
                modal = undefined,
                modal_focus = undefined,
                debug_event = undefined,
                fullscreen = undefined,
                nav_stack = NewStack,
                prev_screen = undefined  %% Reset screen buffer on push
            },
            iso_tty:clear(),
            FinalState = render_diff(NewState),
            {noreply, FinalState};
        {error, Reason} ->
            error_logger:error_msg("Failed to push to ~p: ~p~n", [NewModule, Reason]),
            {noreply, State}
    catch
        Class:Reason:Stacktrace ->
            error_logger:error_msg("Crash pushing to ~p: ~p:~p~n~p~n",
                                   [NewModule, Class, Reason, Stacktrace]),
            {noreply, State}
    end.

%% Pop back to previous view from stack
do_pop(State = #iso_state{nav_stack = []}) ->
    %% Nothing to pop - stay on current view
    {noreply, State};
do_pop(State = #iso_state{nav_stack = [Entry | Rest]}) ->
    #nav_entry{
        callback = Cb,
        user_state = US,
        tree = OldTree,
        focused_container = FC,
        focused_child = FCh
    } = Entry,
    %% Re-render the view to get fresh data (e.g., updated process list)
    %% but merge back the saved widget state (e.g., selection, sort, scroll).
    NewTree = iso_tree:merge_state(OldTree, iso_engine:call_view(Cb, US, OldTree)),
    %% Re-collect containers in case the tree structure changed
    ContainerIds = iso_focus:collect_containers(NewTree),
    %% Validate that saved focus is still valid, otherwise pick first
    NewFC = case lists:member(FC, ContainerIds) of
        true -> FC;
        false -> case ContainerIds of [C|_] -> C; [] -> undefined end
    end,
    %% Validate focused child within container
    ChildIds = iso_focus:collect_children(NewTree, NewFC),
    NewFCh = case lists:member(FCh, ChildIds) of
        true -> FCh;
        false -> case ChildIds of [Ch|_] -> Ch; [] -> undefined end
    end,
    NewState = State#iso_state{
        callback = Cb,
        user_state = US,
        tree = NewTree,
        focused_container = NewFC,
        focused_child = NewFCh,
        container_ids = ContainerIds,
        modal = undefined,
        modal_focus = undefined,
        debug_event = undefined,
        fullscreen = undefined,
        nav_stack = Rest,
        prev_screen = undefined  %% Reset screen buffer on pop
    },
    iso_tty:clear(),
    FinalState = render_diff(NewState),
    {noreply, FinalState}.

forward_event(Event, State) ->
    forward_event(Event, State, undefined).

forward_event(Event, State = #iso_state{callback = Cb, user_state = US}, MergeFromTree) ->
    %% Store event in debug_event for display
    StateWithDebug = State#iso_state{debug_event = Event},
    case call_handler(Cb, {event, Event}, US) of
        {noreply, NewUS} ->
            case MergeFromTree of
                undefined -> do_update(fun(_) -> NewUS end, StateWithDebug);
                _ -> apply_view_update(NewUS, StateWithDebug, MergeFromTree)
            end;
        {unhandled, NewUS} ->
            case MergeFromTree of
                undefined -> do_update(fun(_) -> NewUS end, StateWithDebug);
                _ -> apply_view_update(NewUS, StateWithDebug, MergeFromTree)
            end;
        {fullscreen, Id, NewUS} ->
            enter_fullscreen(Id, NewUS, StateWithDebug, MergeFromTree);
        {toggle_fullscreen, Id, NewUS} ->
            toggle_fullscreen(Id, NewUS, StateWithDebug, MergeFromTree);
        {exit_fullscreen, NewUS} ->
            exit_fullscreen(NewUS, StateWithDebug, MergeFromTree);
        {switch, NewModule, Args} -> do_switch(NewModule, Args, State);
        {push, NewModule, Args} -> do_push(NewModule, Args, State);
        {push, NewModule, Args, NewUS} -> do_push(NewModule, Args, State#iso_state{user_state = NewUS});
        pop -> do_pop(State);
        {modal, Modal, NewUS} ->
            %% Apply pending tree updates (if any), set modal, render.
            Rebuilt = rebuild_view_state(NewUS, StateWithDebug, MergeFromTree),
            {noreply, render_diff(activate_modal(Rebuilt, Modal))};
        {stop, Reason, _NewUS} -> {stop, Reason, StateWithDebug}
    end.

handle_special_result({fullscreen, Id, NewUS}, State, MergeFromTree) ->
    enter_fullscreen(Id, NewUS, State, MergeFromTree);
handle_special_result({toggle_fullscreen, Id, NewUS}, State, MergeFromTree) ->
    toggle_fullscreen(Id, NewUS, State, MergeFromTree);
handle_special_result({exit_fullscreen, NewUS}, State, MergeFromTree) ->
    exit_fullscreen(NewUS, State, MergeFromTree);
handle_special_result(_Other, State, _MergeFromTree) ->
    {noreply, State}.

call_handler(Cb, Event, US) ->
    case erlang:function_exported(Cb, handle_event, 2) of
        true -> Cb:handle_event(Event, US);
        false -> {noreply, US}
    end.

%% Call handler and set debug_event if unhandled
call_handler_with_debug(Cb, Event, US, State) ->
    case erlang:function_exported(Cb, handle_event, 2) of
        true ->
            case Cb:handle_event(Event, US) of
                {unhandled, NewUS} ->
                    {unhandled, NewUS, State#iso_state{debug_event = Event}};
                Other ->
                    {handled, Other, State}
            end;
        false ->
            {unhandled, US, State#iso_state{debug_event = Event}}
    end.

render_tree(Tree, Bounds, FocusedContainer, FocusedChild) ->
    iso_tty:write(iso_render:render_two_level(Tree, Bounds, FocusedContainer, FocusedChild)).

%% @doc Render with differential updates - returns updated state with new screen buffer.
%% Also handles lifecycle callbacks (on_mount/on_unmount).
render_diff(State = #iso_state{tree = Tree, bounds = Bounds,
                               focused_container = Container, focused_child = Child,
                               modal = Modal, modal_focus = MF,
                               prev_screen = PrevScreen,
                               mounted_ids = OldMounted,
                               cursor_visible = CursorVisible}) ->
    #bounds{width = W, height = H} = Bounds,

    %% Collect current element IDs and handle lifecycle
    CurrentElements = collect_elements_with_id(Tree),
    ModalElements = case Modal of
        undefined -> #{};
        _ -> collect_elements_with_id(Modal)
    end,
    AllCurrentElements = maps:merge(CurrentElements, ModalElements),

    %% Detect mounts and unmounts
    NewMounted = handle_lifecycle(OldMounted, AllCurrentElements),

    %% Render options including cursor visibility for blinking cursor support
    RenderOpts = #{cursor_visible => CursorVisible},

    %% Generate ANSI output for current frame. When a modal is active,
    %% focus indicators are driven by the modal's own focus tracking so
    %% buttons/inputs inside the modal can render their focused state.
    AnsiOutput = case Modal of
        undefined ->
            iso_render:render_two_level(Tree, Bounds, Container, Child, RenderOpts);
        _ ->
            {ModalC, ModalCh} = case MF of
                #modal_focus{container = MC, child = MCh} -> {MC, MCh};
                undefined -> {undefined, undefined}
            end,
            [iso_render:render_dimmed(Tree, Bounds, Child),
             iso_render:render_two_level(Modal, Bounds, ModalC, ModalCh, RenderOpts)]
    end,
    case iso_unicode:contains_wide(AnsiOutput) of
        true ->
            %% The screen diff model is cell-based and cannot safely round-trip
            %% wide glyphs like emoji. Fall back to a full redraw for these frames.
            iso_tty:write([<<"\e[2J\e[H">>, AnsiOutput]),
            State#iso_state{prev_screen = undefined, mounted_ids = NewMounted};
        false ->
            %% Build new screen buffer from ANSI output
            NewScreen = iso_screen:from_ansi(AnsiOutput, W, H),
            %% Diff against previous screen and output only changes
            case PrevScreen of
                undefined ->
                    %% First render - output everything
                    iso_tty:write(iso_screen:to_ansi(NewScreen));
                _ ->
                    case iso_screen:get_size(PrevScreen) of
                        {W, H} ->
                            %% Same size - diff render
                            DiffOutput = iso_screen:diff(PrevScreen, NewScreen),
                            case DiffOutput of
                                [] ->
                                    %% No changes - nothing to output
                                    ok;
                                _ ->
                                    iso_tty:write(DiffOutput)
                            end;
                        _ ->
                            %% Size changed - full render
                            iso_tty:write(iso_screen:to_ansi(NewScreen))
                    end
            end,
            %% Return updated state with new screen buffer and mounted elements
            State#iso_state{prev_screen = NewScreen, mounted_ids = NewMounted}
    end.

%%====================================================================
%% Internal: Lifecycle management
%%====================================================================

%% Handle lifecycle transitions - call on_mount for new elements, on_unmount for removed
handle_lifecycle(OldMounted, NewElements) ->
    OldIds = maps:keys(OldMounted),
    NewIds = maps:keys(NewElements),

    %% Elements that were removed (unmounted)
    Unmounted = OldIds -- NewIds,
    lists:foreach(fun(Id) ->
        Element = maps:get(Id, OldMounted),
        call_lifecycle(on_unmount, Element)
    end, Unmounted),

    %% Elements that are new (mounted)
    Mounted = NewIds -- OldIds,
    lists:foreach(fun(Id) ->
        Element = maps:get(Id, NewElements),
        call_lifecycle(on_mount, Element)
    end, Mounted),

    NewElements.

%% Call lifecycle callback if defined
call_lifecycle(on_mount, Element) ->
    case get_lifecycle_callback(Element, on_mount) of
        undefined -> ok;
        Fun when is_function(Fun, 1) ->
            try Fun(Element) catch _:_ -> ok end
    end;
call_lifecycle(on_unmount, Element) ->
    case get_lifecycle_callback(Element, on_unmount) of
        undefined -> ok;
        Fun when is_function(Fun, 1) ->
            try Fun(Element) catch _:_ -> ok end
    end.

%% Extract lifecycle callback from element record
get_lifecycle_callback(Element, CallbackName) when is_tuple(Element) ->
    %% Use record_info to find the callback field position
    %% For now, we'll check common element types that have lifecycle hooks
    try
        case CallbackName of
            on_mount -> element_on_mount(Element);
            on_unmount -> element_on_unmount(Element)
        end
    catch
        _:_ -> undefined
    end;
get_lifecycle_callback(_, _) -> undefined.

%% Get on_mount field from various element types
element_on_mount(#text{on_mount = V}) -> V;
element_on_mount(#button{on_mount = V}) -> V;
element_on_mount(#input{on_mount = V}) -> V;
element_on_mount(#box{on_mount = V}) -> V;
element_on_mount(#vbox{on_mount = V}) -> V;
element_on_mount(#hbox{on_mount = V}) -> V;
element_on_mount(#panel{on_mount = V}) -> V;
element_on_mount(#table{on_mount = V}) -> V;
element_on_mount(#tabs{on_mount = V}) -> V;
element_on_mount(#tree{on_mount = V}) -> V;
element_on_mount(#progress_bar{on_mount = V}) -> V;
element_on_mount(#sparkline{on_mount = V}) -> V;
element_on_mount(#stat_row{on_mount = V}) -> V;
element_on_mount(#status_bar{on_mount = V}) -> V;
element_on_mount(#header{on_mount = V}) -> V;
element_on_mount(_) -> undefined.

%% Get on_unmount field from various element types
element_on_unmount(#text{on_unmount = V}) -> V;
element_on_unmount(#button{on_unmount = V}) -> V;
element_on_unmount(#input{on_unmount = V}) -> V;
element_on_unmount(#box{on_unmount = V}) -> V;
element_on_unmount(#vbox{on_unmount = V}) -> V;
element_on_unmount(#hbox{on_unmount = V}) -> V;
element_on_unmount(#panel{on_unmount = V}) -> V;
element_on_unmount(#table{on_unmount = V}) -> V;
element_on_unmount(#tabs{on_unmount = V}) -> V;
element_on_unmount(#tree{on_unmount = V}) -> V;
element_on_unmount(#progress_bar{on_unmount = V}) -> V;
element_on_unmount(#sparkline{on_unmount = V}) -> V;
element_on_unmount(#stat_row{on_unmount = V}) -> V;
element_on_unmount(#status_bar{on_unmount = V}) -> V;
element_on_unmount(#header{on_unmount = V}) -> V;
element_on_unmount(_) -> undefined.

%% Collect all elements with IDs from the tree
collect_elements_with_id(Tree) ->
    collect_elements_with_id(Tree, #{}).

collect_elements_with_id(Element, Acc) when is_tuple(Element) ->
    %% Check if element has an id field (not undefined)
    Id = get_element_id(Element),
    NewAcc = case Id of
        undefined -> Acc;
        _ -> maps:put(Id, Element, Acc)
    end,
    %% Recurse into children
    Children = get_children(Element),
    lists:foldl(fun(Child, A) -> collect_elements_with_id(Child, A) end, NewAcc, Children);
collect_elements_with_id(_, Acc) ->
    Acc.

%% Get id from element (returns undefined if no id)
get_element_id(#text{id = Id}) -> Id;
get_element_id(#button{id = Id}) -> Id;
get_element_id(#input{id = Id}) -> Id;
get_element_id(#box{id = Id}) -> Id;
get_element_id(#vbox{id = Id}) -> Id;
get_element_id(#hbox{id = Id}) -> Id;
get_element_id(#panel{id = Id}) -> Id;
get_element_id(#table{id = Id}) -> Id;
get_element_id(#tabs{id = Id}) -> Id;
get_element_id(#tree{id = Id}) -> Id;
get_element_id(#progress_bar{id = Id}) -> Id;
get_element_id(#sparkline{id = Id}) -> Id;
get_element_id(#stat_row{id = Id}) -> Id;
get_element_id(#status_bar{id = Id}) -> Id;
get_element_id(#header{id = Id}) -> Id;
get_element_id(_) -> undefined.

%% Get children from element (for tree traversal)
get_children(#box{children = C}) -> C;
get_children(#vbox{children = C}) -> C;
get_children(#hbox{children = C}) -> C;
get_children(#panel{children = C}) -> C;
get_children(#tabs{tabs = Tabs}) ->
    %% Extract content from all tabs
    lists:flatmap(fun(#tab{content = Content}) -> Content end, Tabs);
get_children(#tree{}) -> [];  %% tree_nodes are not element records
get_children(_) -> [].

%%====================================================================
%% Internal: Cursor blink timer management
%%====================================================================

%% @doc Update cursor blink timer based on whether the focused element is an input.
%% Starts timer when focusing an input, stops when leaving input.
-spec update_cursor_timer(#iso_state{}) -> #iso_state{}.
update_cursor_timer(State = #iso_state{cursor_timer = OldTimer}) ->
    {Tree, _FC, FocusedChild, _Ids, _Where} = active_focus(State),
    FocusedElement = iso_focus:find_element(Tree, FocusedChild),
    IsInput = is_record(FocusedElement, input),
    case {IsInput, OldTimer} of
        {true, undefined} ->
            %% Focusing on input, no timer running - start it
            Timer = erlang:send_after(500, self(), cursor_blink),
            State#iso_state{cursor_visible = true, cursor_timer = Timer};
        {false, undefined} ->
            %% Not an input, no timer - nothing to do
            State;
        {true, _} ->
            %% Focusing on input, timer already running - reset visibility
            State#iso_state{cursor_visible = true};
        {false, _} ->
            %% Not an input but timer running - stop it
            erlang:cancel_timer(OldTimer),
            State#iso_state{cursor_visible = true, cursor_timer = undefined}
    end.


handle_shortcut_click(Key, State) ->
    case iso_shortcuts:parse(Key) of
        enter -> handle_activate(State);
        tab -> handle_focus_next(State);
        btab -> handle_focus_prev(State);
        escape -> handle_input(escape, State);
        {key, up} -> handle_arrow(up, State);
        {key, down} -> handle_arrow(down, State);
        {key, left} -> handle_arrow(left, State);
        {key, right} -> handle_arrow(right, State);
        Event when Event =/= undefined -> forward_event(Event, State);
        undefined -> {noreply, State}
    end.

maybe_cancel_timer(undefined) ->
    ok;
maybe_cancel_timer(Timer) ->
    erlang:cancel_timer(Timer),
    ok.
