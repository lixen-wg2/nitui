%%%-------------------------------------------------------------------
%%% @doc NitUI application callback module.
%%% @end
%%%-------------------------------------------------------------------
-module(nitui_app).

-behaviour(application).

-export([start/2, stop/1]).

%% Internal
-export([filter_sigwinch/2]).

%%--------------------------------------------------------------------
%% @doc Start the NitUI application.
%% @end
%%--------------------------------------------------------------------
-spec start(application:start_type(), term()) -> {ok, pid()} | {error, term()}.
start(_StartType, _StartArgs) ->
    %% Filter out "supervisor received unexpected message: sigwinch" warnings.
    %% The BEAM delivers sigwinch to supervisors in the process tree and
    %% OTP supervisors log a warning for any unexpected message.
    logger:add_primary_filter(nit_sigwinch_filter, {fun filter_sigwinch/2, []}),
    nit_sup:start_link().

%%--------------------------------------------------------------------
%% @doc Stop the NitUI application.
%% @end
%%--------------------------------------------------------------------
-spec stop(term()) -> ok.
stop(_State) ->
    logger:remove_primary_filter(nit_sigwinch_filter),
    ok.

%%====================================================================
%% Internal
%%====================================================================

%% @doc Logger filter that suppresses resize signal noise.
%% The BEAM/runtime TTY layers may deliver raw sigwinch atoms or
%% {Ref, {signal, sigwinch}} messages. OTP gen_servers/supervisors log
%% unexpected messages before user code can do anything useful with them.
filter_sigwinch(#{msg := {report, Report}}, _Extra) ->
    case sigwinch_report(Report) of
        true -> stop;
        false -> ignore
    end;
filter_sigwinch(_LogEvent, _Extra) ->
    ignore.

sigwinch_report(#{label := {gen_server, no_handle_info}} = Report) ->
    sigwinch_message(maps:get(message, Report, undefined));
sigwinch_report(#{label := {supervisor, unexpected_msg}} = Report) ->
    sigwinch_message(maps:get(msg, Report, maps:get(message, Report, undefined)));
sigwinch_report(_Report) ->
    false.

sigwinch_message(sigwinch) ->
    true;
sigwinch_message({signal, sigwinch}) ->
    true;
sigwinch_message({_Ref, {signal, sigwinch}}) ->
    true;
sigwinch_message(_Msg) ->
    false.
