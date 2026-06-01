%%%-------------------------------------------------------------------
%%% @doc Demo application for NitUI TUI framework.
%%%
%%% Simple demo showing how to use nitui with callbacks:
%%% - init/1 - return initial state (a map)
%%% - view/1 - return the UI tree based on state
%%% - handle_event/2 - handle events and return new state
%%% @end
%%%-------------------------------------------------------------------
-module(demo_main).

-behaviour(iso_callback).

-include_lib("nitui/include/iso_elements.hrl").

%% NitUI callbacks
-export([init/1, view/1, handle_event/2]).

%%====================================================================
%% NitUI Callbacks
%%====================================================================

init(_Args) ->
    {ok, #{name => "", selected_pid => undefined}}.

view(State) ->
    #{name := Name, selected_pid := SelectedPid} = State,
    ProcessList = get_process_list(),
    SelectedRow = find_pid_row(SelectedPid, ProcessList),
    #hbox{spacing = 1, children = [
        #box{
            id = main_box,
            border = double,
            title = "NitUI Demo",
            focusable = true,
            style = #{fg => cyan, bold => true},
            children = [
                #vbox{children = [
                    #text{content = "Welcome to NitUI!", style = #{bold => true}},
                    #text{content = "Tab/Arrows to navigate, Enter to activate"},
                    #text{content = "Ctrl+C to quit", style = #{fg => green}},
                    #spacer{height = 1},
                    #hbox{spacing = 1, children = [
                        #text{content = "Name:"},
                        #input{id = name_input, width = 30,
                               value = Name, placeholder = "Enter your name",
                               focusable = true}
                    ]},
                    #spacer{height = 1},
                    #hbox{spacing = 2, children = [
                        #button{id = greet_btn, label = "Greet",
                                focusable = true, style = #{fg => green}},
                        #button{id = quit_btn, label = "Quit",
                                focusable = true, style = #{fg => red}}
                    ]}
                ]}
            ]
        },
        #tabs{
            id = demo_tabs,
            height = fill,
            focusable = true,
            style = #{fg => cyan},
            tabs = [
                #tab{id = processes, label = "Processes", content = [
                    #table{
                        id = proc_table,
                        columns = [
                            #table_col{id = pid, header = "PID", width = 12},
                            #table_col{id = name, header = "Name"},
                            #table_col{id = mem, header = "Mem", width = 10, align = right}
                        ],
                        rows = ProcessList,
                        selected_row = SelectedRow
                    }
                ]},
                #tab{id = apps, label = "Apps", content = [
                    #vbox{children = [
                        #text{content = "Running Applications:", style = #{bold => true}},
                        #text{content = "  kernel", style = #{fg => green}},
                        #text{content = "  stdlib", style = #{fg => green}},
                        #text{content = "  demo", style = #{fg => cyan}}
                    ]}
                ]},
                #tab{id = memory, label = "Memory", content = [
                    #vbox{children = [
                        #text{content = "Memory Usage:", style = #{bold => true}},
                        #text{content = "  Total: 24.5 MB"},
                        #text{content = "  Processes: 8.2 MB", style = #{fg => yellow}},
                        #text{content = "  Atoms: 1.1 MB", style = #{fg => cyan}}
                    ]}
                ]}
            ]
        }
    ]}.

handle_event(quit, State) ->
    %% Just return stop - iso_server:terminate will cleanup and halt
    {stop, normal, State};

handle_event({click, greet_btn, _}, State) ->
    Name = maps:get(name, State, ""),
    Greeting = case iolist_size([Name]) of
        0 -> "Hello, stranger!";
        _ -> ["Hello, ", Name, "!"]
    end,
    Modal = #modal{
        title = "Greeting",
        width = 40, height = 7,
        style = #{fg => cyan, bold => true},
        children = [
            #vbox{children = [
                #text{content = Greeting, style = #{fg => yellow, bold => true}},
                #spacer{height = 1},
                #text{content = "Press ESC to close", style = #{fg => white, dim => true}}
            ]}
        ]
    },
    {modal, Modal, State};

handle_event({click, quit_btn, _}, State) ->
    handle_event(quit, State);

handle_event({input, name_input, Value}, State) ->
    {noreply, State#{name => Value}};

handle_event({table_activate, proc_table, _RowIdx, [PidStr | _]}, State) ->
    %% Convert PID string to actual PID and push to process detail view
    %% Save the selected PID so we can restore selection when popping back
    Pid = try list_to_pid(unicode:characters_to_list(PidStr)) catch _:_ -> undefined end,
    NewState = State#{selected_pid => Pid},
    {push, process_detail, #{pid => Pid}, NewState};

handle_event({event, escape}, State) ->
    %% ESC exits the application
    {stop, normal, State};

handle_event(_Event, State) ->
    {unhandled, State}.

%%====================================================================
%% Internal functions
%%====================================================================

get_process_list() ->
    Procs = erlang:processes(),
    lists:map(fun(Pid) ->
        Info = erlang:process_info(Pid, [registered_name, memory]),
        Name = case proplists:get_value(registered_name, Info) of
            undefined -> "(unnamed)";
            [] -> "(unnamed)";
            RegName when is_atom(RegName) -> atom_to_list(RegName)
        end,
        Mem = proplists:get_value(memory, Info, 0),
        MemStr = iso_format:bytes(Mem),
        [pid_to_list(Pid), Name, MemStr]
    end, lists:sublist(Procs, 20)).  %% Limit to 20 processes

%% Find which row contains the given PID, returns 1 if not found
find_pid_row(undefined, _Rows) -> 1;
find_pid_row(Pid, Rows) ->
    PidStr = pid_to_list(Pid),
    find_pid_row(PidStr, Rows, 1).

find_pid_row(_PidStr, [], _Idx) -> 1;  %% Not found, default to row 1
find_pid_row(PidStr, [[PidStr | _] | _], Idx) -> Idx;  %% Found it
find_pid_row(PidStr, [_ | Rest], Idx) -> find_pid_row(PidStr, Rest, Idx + 1).
