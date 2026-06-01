%%%-------------------------------------------------------------------
%%% @doc Signal handler for NitUI.
%%%
%%% This is a gen_event handler that registers with erl_signal_server
%%% to receive Unix signals. When SIGWINCH (terminal resize) is received,
%%% it notifies nit_tty which then forwards the event to nit_server.
%%% @end
%%%-------------------------------------------------------------------
-module(nit_sighandler).

-behaviour(gen_event).

%% gen_event callbacks
-export([init/1, handle_event/2, handle_call/2, handle_info/2, 
         terminate/2, code_change/3]).

-record(state, {
    parent :: pid()
}).

%%====================================================================
%% gen_event callbacks
%%====================================================================

init(#{parent := Parent}) ->
    %% Register for SIGWINCH (terminal resize)
    ok = os:set_signal(sigwinch, handle),
    {ok, #state{parent = Parent}}.

handle_event(sigwinch, #state{parent = Parent} = State) ->
    %% Notify the parent (nit_tty) about the resize signal
    Parent ! {signal, sigwinch},
    {ok, State};
handle_event(_Signal, State) ->
    %% Ignore other signals
    {ok, State}.

handle_call(_Request, State) ->
    {ok, ok, State}.

handle_info(_Info, State) ->
    {ok, State}.

terminate(_Reason, _State) ->
    %% Unregister signal handler
    try os:set_signal(sigwinch, default)
    catch _:_ -> ok
    end,
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
