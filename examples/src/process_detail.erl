%%%-------------------------------------------------------------------
%%% @doc Process detail view - shows detailed info about a process
%%% Demonstrates the {switch, Module, Args} pattern for navigation
%%% @end
%%%-------------------------------------------------------------------
-module(process_detail).

-behaviour(iso_callback).

-include("iso_elements.hrl").

%% NitUI callbacks
-export([init/1, view/1, handle_event/2]).

%%====================================================================
%% NitUI Callbacks
%%====================================================================

init(#{pid_str := PidStr, info := Info}) ->
    {ok, #{pid_display => PidStr, info => Info}};
init(#{pid := Pid, info := Info}) ->
    {ok, #{pid => Pid, info => Info}};
init(#{pid := Pid}) ->
    {ok, #{pid => Pid}}.

view(State) ->
    PidStr = display_pid(State),
    Info = detail_info(State),
    #box{
        id = detail_box,
        border = double,
        title = "Process Detail",
        width = fill,
        height = fill,
        focusable = true,
        children = [
            #vbox{children = [
                #text{content = ["PID: ", PidStr], style = #{bold => true, fg => cyan}},
                #spacer{height = 1},
                #text{content = format_info("Status", maps:get(status, Info, "unknown"))},
                #text{content = format_info("Registered", maps:get(registered_name, Info, "(none)"))},
                #text{content = format_info("Memory", maps:get(memory, Info, "?"))},
                #text{content = format_info("Message Queue", maps:get(message_queue_len, Info, "?"))},
                #text{content = format_info("Reductions", maps:get(reductions, Info, "?"))},
                #spacer{height = 1},
                #text{content = format_info("Current Function", maps:get(current_function, Info, "?")), style = #{fg => yellow}},
                #text{content = format_info("Initial Call", maps:get(initial_call, Info, "?")), style = #{fg => yellow}},
                #spacer{height = 1},
                #button{
                    id = back_btn,
                    label = "Back",
                    width = 12,
                    focusable = true,
                    style = #{fg => white, bg => blue, bold => true}
                }
            ]}
        ]
    }.

handle_event(quit, State) ->
    {stop, normal, State};

handle_event({click, back_btn, _}, _State) ->
    %% Pop back to previous view (preserves state)
    pop;

handle_event({event, escape}, _State) ->
    %% ESC key goes back
    pop;

handle_event(_Event, State) ->
    {unhandled, State}.

%%====================================================================
%% Internal functions
%%====================================================================

get_process_info(undefined) ->
    #{};
get_process_info(Pid) ->
    case erlang:is_process_alive(Pid) of
        false -> #{status => "dead"};
        true ->
            Info = erlang:process_info(Pid, [
                registered_name, memory, message_queue_len, 
                reductions, current_function, initial_call, status
            ]),
            #{
                status => format_value(proplists:get_value(status, Info)),
                registered_name => format_value(proplists:get_value(registered_name, Info)),
                memory => iso_format:bytes(proplists:get_value(memory, Info)),
                message_queue_len => format_value(proplists:get_value(message_queue_len, Info)),
                reductions => format_value(proplists:get_value(reductions, Info)),
                current_function => format_mfa(proplists:get_value(current_function, Info)),
                initial_call => format_mfa(proplists:get_value(initial_call, Info))
            }
    end.

format_info(Label, Value) ->
    [Label, ": ", Value].

format_value(undefined) -> "(none)";
format_value([]) -> "(none)";
format_value(V) when is_atom(V) -> atom_to_list(V);
format_value(V) when is_integer(V) -> integer_to_list(V);
format_value(V) -> lists:flatten(io_lib:format("~p", [V])).

format_mfa(undefined) -> "?";
format_mfa({M, F, A}) ->
    lists:flatten(io_lib:format("~ts:~ts/~B", [atom_to_list(M), atom_to_list(F), A]));
format_mfa(Other) ->
    format_value(Other).

detail_info(#{info := Info}) ->
    Info;
detail_info(#{pid := Pid}) ->
    get_process_info(Pid);
detail_info(_) ->
    #{}.

display_pid(#{pid_display := PidStr}) ->
    PidStr;
display_pid(#{pid := Pid}) ->
    pid_to_string(Pid);
display_pid(_) ->
    "undefined".

pid_to_string(undefined) -> "undefined";
pid_to_string(Pid) -> pid_to_list(Pid).
