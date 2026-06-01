%%%-------------------------------------------------------------------
%%% @doc NitUI Callback Behaviour
%%%
%%% Defines the behaviour for NitUI UI callback modules.
%%% Callback modules implement this behaviour to create TUI applications.
%%%
%%% Required callbacks:
%%% - init/1: Initialize state from arguments
%%% - view/1: Render state to element tree
%%%
%%% Optional callbacks:
%%% - handle_event/2: Handle UI events (keyboard, mouse, etc.)
%%% @end
%%%-------------------------------------------------------------------
-module(nit_callback).

-include("nit_elements.hrl").

%%====================================================================
%% Type Definitions
%%====================================================================

%% Element tree (any element record from nit_elements.hrl)
-type element() :: tuple().

%% User-defined state
-type state() :: term().

%% Event types sent to handle_event/2
-type click_event() :: {click, Id :: term(), Handler :: term()}.
-type submit_event() :: {submit, Id :: term(), Value :: binary(), Handler :: term()}.
-type input_event() :: {input, Id :: term(), Value :: binary()}.
-type list_select_event() :: {list_select, Id :: term(), Index :: non_neg_integer(), Item :: term()}.
-type tab_change_event() :: {tab_change, Id :: term(), TabId :: term()}.
-type table_activate_event() :: {table_activate, Id :: term(), RowIndex :: pos_integer(), RowData :: list()}.
-type table_select_event() :: {table_select, Id :: term(), RowIndex :: pos_integer(), RowData :: list()}.
-type tree_activate_event() :: {tree_activate, Id :: term(), NodeId :: term()}.
-type tree_select_event() :: {tree_select, Id :: term(), NodeId :: term()}.
-type generic_event() :: {event, term()}.
-type quit_event() :: quit.

-type event() :: click_event()
               | submit_event()
               | input_event()
               | list_select_event()
               | tab_change_event()
               | table_activate_event()
               | table_select_event()
               | tree_activate_event()
               | tree_select_event()
               | generic_event()
               | quit_event().

%% Return types from handle_event/2
-type noreply() :: {noreply, state()}.
-type stop() :: {stop, Reason :: term(), state()}.
-type modal() :: {modal, Modal :: element(), state()}.
-type switch() :: {switch, Module :: module(), Args :: term()}.
-type push() :: {push, Module :: module(), Args :: term()}.
-type push_with_state() :: {push, Module :: module(), Args :: term(), state()}.
-type pop() :: pop.
-type fullscreen() :: {fullscreen, Id :: term(), state()}.
-type toggle_fullscreen() :: {toggle_fullscreen, Id :: term(), state()}.
-type exit_fullscreen() :: {exit_fullscreen, state()}.
-type unhandled() :: {unhandled, state()}.

-type handle_event_result() :: noreply()
                             | stop()
                             | modal()
                             | switch()
                             | push()
                             | push_with_state()
                             | pop()
                             | fullscreen()
                             | toggle_fullscreen()
                             | exit_fullscreen()
                             | unhandled().

%% Return types from init/1
-type init_result() :: {ok, state()}
                     | {ok, state(), element()}.

%%====================================================================
%% Exports for types
%%====================================================================

-export_type([
    element/0,
    state/0,
    event/0,
    handle_event_result/0,
    init_result/0
]).

%%====================================================================
%% Behaviour Callbacks
%%====================================================================

%% @doc Initialize the callback module state.
%% Called once when the UI server starts.
%%
%% Returns:
%% - {ok, State} - Initial state, view/1 will be called to get the tree
%% - {ok, State, Tree} - Initial state and element tree
-callback init(Args :: term()) -> init_result().

%% @doc Render the current state to an element tree.
%% Called after init/1 and after each state update.
%%
%% view/1 MUST be a pure function of State. On the initial render
%% (after init/1 and after a push) the framework invokes view/1
%% twice: the first pass seeds the tree context used by
%% nitui:selected_item/1, and the second pass produces the tree
%% that is actually rendered. Any side effects in view/1 will fire
%% twice on those entry points.
-callback view(State :: state()) -> element().

%% @doc Handle UI events.
%% Called when user interacts with the UI (clicks, key presses, etc.)
%%
%% This callback is optional. If not implemented, events are ignored.
-callback handle_event(Event :: event(), State :: state()) -> handle_event_result().

-optional_callbacks([handle_event/2]).
