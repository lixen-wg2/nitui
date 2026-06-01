%%%-------------------------------------------------------------------
%%% @doc Demo Home Page - Observer-style dashboard with dummy data
%%% @end
%%%-------------------------------------------------------------------
-module(demo_home).

-behaviour(iso_callback).

-include("iso_elements.hrl").

-export([init/1, view/1, handle_event/2]).

init(_Args) ->
    %% Initialize with real system stats
    Stats = collect_stats(),
    %% Start with empty history for sparklines
    {ok, Stats#{
        reductions_history => [],
        io_history => [],
        gc_history => []
    }}.

%% Collect real Erlang system statistics
collect_stats() ->
    {UptimeSecs, _} = erlang:statistics(wall_clock),
    Memory = erlang:memory(),
    #{
        procs => erlang:system_info(process_count),
        ports => erlang:system_info(port_count),
        ets_count => length(ets:all()),
        atoms => erlang:system_info(atom_count),
        uptime_secs => UptimeSecs div 1000,
        otp_release => erlang:system_info(otp_release),
        node_name => atom_to_list(node()),
        total_mem => proplists:get_value(total, Memory, 0),
        proc_mem => proplists:get_value(processes, Memory, 0),
        atom_mem => proplists:get_value(atom, Memory, 0),
        schedulers => erlang:system_info(schedulers),
        reductions => element(1, erlang:statistics(reductions)),
        io_in => element(1, erlang:statistics(io)),
        io_out => element(2, erlang:statistics(io))
    }.

view(State) ->
    #{procs := Procs, ports := Ports, ets_count := Ets, atoms := Atoms,
      uptime_secs := Uptime, otp_release := OtpRel, node_name := NodeName,
      total_mem := TotalMem, proc_mem := ProcMem, atom_mem := AtomMem,
      schedulers := Scheds, reductions_history := RedHist,
      io_history := IoHist, gc_history := GcHist} = State,

    %% Format values
    UptimeStr = iso_format:duration(Uptime),
    TotalMemMB = TotalMem div (1024 * 1024),
    ProcMemMB = ProcMem div (1024 * 1024),
    AtomMemMB = AtomMem div (1024 * 1024),

    #vbox{children = [
        %% Header bar
        #header{
            title = "NitUI Observer",
            subtitle = NodeName,
            items = [
                {"Uptime", UptimeStr},
                {"OTP", OtpRel}
            ]
        },

        %% Stats row
        #stat_row{
            items = [
                {"Procs", iso_format:commas(Procs)},
                {"Ports", iso_format:commas(Ports)},
                {"ETS", iso_format:commas(Ets)},
                {"Atoms", iso_format:commas(Atoms)}
            ]
        },

        #text{content = "Quick Actions:", style = #{bold => true}},
        #hbox{spacing = 2, children = [
            #button{
                id = home_processes_btn,
                label = "Processes",
                focusable = true,
                style = #{fg => white, bg => blue, bold => true}
            },
            #button{
                id = home_network_btn,
                label = "Network",
                focusable = true,
                style = #{fg => white, bg => magenta, bold => true}
            },
            #button{
                id = home_widgets_btn,
                label = "Widgets",
                focusable = true,
                style = #{fg => white, bg => green, bold => true}
            }
        ]},

        %% Scheduler utilization section (show available schedulers)
        #text{content = "Scheduler Utilization:", style = #{bold => true}},
        scheduler_bars(Scheds),

        %% Memory section
        #text{content = "Memory Usage:", style = #{bold => true}},
        #hbox{spacing = 2, children = [
            #vbox{children = [
                #text{content = io_lib:format("Total: ~B MB", [TotalMemMB])},
                #progress_bar{value = TotalMemMB, max = max(1, TotalMemMB * 2), width = 25, show_percent = true}
            ]},
            #vbox{children = [
                #text{content = io_lib:format("Processes: ~B MB", [ProcMemMB])},
                #progress_bar{value = ProcMemMB, max = max(1, TotalMemMB), width = 25, color = cyan}
            ]},
            #vbox{children = [
                #text{content = io_lib:format("Atoms: ~B MB", [AtomMemMB])},
                #progress_bar{value = AtomMemMB, max = max(1, TotalMemMB div 10), width = 25, color = magenta}
            ]}
        ]},

        %% Sparklines section
        #text{content = "Trends (last 15s):", style = #{bold => true}},
        #hbox{spacing = 3, children = [
            #vbox{children = [
                #text{content = "Reductions:", style = #{dim => true}},
                #sparkline{values = pad_history(RedHist), width = 15, style_type = braille, color = green}
            ]},
            #vbox{children = [
                #text{content = "IO Bytes:", style = #{dim => true}},
                #sparkline{values = pad_history(IoHist), width = 15, style_type = block, color = yellow}
            ]},
            #vbox{children = [
                #text{content = "GC Runs:", style = #{dim => true}},
                #sparkline{values = pad_history(GcHist), width = 15, style_type = ascii, color = cyan}
            ]}
        ]},

        %% Spacer pushes status bar to bottom
        #spacer{},

        %% Status bar at bottom
        #status_bar{
            items = [
                {"H", "Home"},
                {"P", "Processes"},
                {"N", "Network"},
                {"E", "ETS"},
                {"T", "Tree"},
                {"V", "Virtual"},
                {"W", "Widgets"},
                {"Q", "Quit"}
            ]
        }
    ]}.

%% Generate scheduler progress bars dynamically
scheduler_bars(Scheds) when Scheds =< 4 ->
    #hbox{spacing = 1, children = lists:flatten([
        [#text{content = integer_to_list(N) ++ ":", width = 2},
         #progress_bar{value = rand:uniform(100), max = 100, width = 20}]
        || N <- lists:seq(1, Scheds)
    ])};
scheduler_bars(Scheds) ->
    %% Show first 4 schedulers for larger systems
    #hbox{spacing = 1, children = lists:flatten([
        [#text{content = integer_to_list(N) ++ ":", width = 2},
         #progress_bar{value = rand:uniform(100), max = 100, width = 15}]
        || N <- lists:seq(1, min(4, Scheds))
    ]) ++ [#text{content = lists:flatten(io_lib:format("(~B total)", [Scheds]))}]}.

%% Pad history to 15 values for sparkline
pad_history([]) -> [0];
pad_history(H) when length(H) < 15 -> H ++ lists:duplicate(15 - length(H), 0);
pad_history(H) -> H.

%% Handle periodic tick event to refresh stats
handle_event(tick, State) ->
    #{reductions := PrevRed, io_in := PrevIoIn, io_out := PrevIoOut,
      reductions_history := RedHist, io_history := IoHist, gc_history := GcHist} = State,

    %% Collect fresh stats
    NewStats = collect_stats(),
    #{reductions := NewRed, io_in := NewIoIn, io_out := NewIoOut} = NewStats,

    %% Calculate deltas (changes since last tick)
    RedDelta = max(0, NewRed - PrevRed),
    IoDelta = max(0, (NewIoIn + NewIoOut) - (PrevIoIn + PrevIoOut)),
    %% Get GC count - use a simple random for demo since exact GC stats vary
    GcDelta = rand:uniform(10),

    %% Normalize deltas to fit sparkline (0-100 range)
    NormRed = min(100, RedDelta div 10000),
    NormIo = min(100, IoDelta div 1000),

    %% Update history (keep last 15 values)
    NewRedHist = lists:sublist([NormRed | RedHist], 15),
    NewIoHist = lists:sublist([NormIo | IoHist], 15),
    NewGcHist = lists:sublist([GcDelta | GcHist], 15),

    %% Merge new stats with updated history
    UpdatedState = maps:merge(NewStats, #{
        reductions_history => NewRedHist,
        io_history => NewIoHist,
        gc_history => NewGcHist
    }),
    {noreply, UpdatedState};
handle_event({click, home_processes_btn, _}, _State) ->
    {switch, demo_processes, #{}};
handle_event({click, home_network_btn, _}, _State) ->
    {switch, demo_network, #{}};
handle_event({click, home_widgets_btn, _}, _State) ->
    {switch, demo_widgets, #{}};

handle_event(Event, State) ->
    case iso_shortcuts:handle(Event, State, [
        {"p", fun(_) -> {switch, demo_processes, #{}} end},
        {"n", fun(_) -> {switch, demo_network, #{}} end},
        {"e", fun(_) -> {switch, demo_ets, #{}} end},
        {"t", fun(_) -> {switch, demo_tree, #{}} end},
        {"v", fun(_) -> {switch, demo_virtual, #{}} end},
        {"w", fun(_) -> {switch, demo_widgets, #{}} end},
        {["q", escape], {stop, normal}}
    ]) of
        nomatch -> {unhandled, State};
        Result -> Result
    end.
