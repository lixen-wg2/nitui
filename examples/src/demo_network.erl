%%%-------------------------------------------------------------------
%%% @doc Demo Network Page - Network/ports with dummy data
%%% @end
%%%-------------------------------------------------------------------
-module(demo_network).

-behaviour(nit_callback).

-include("nit_elements.hrl").

-export([init/1, view/1, handle_event/2]).

init(_Args) ->
    {ok, #{}}.

view(_State) ->
    #vbox{children = [
        %% Header
        #header{
            title = "Network",
            subtitle = "nonode@nohost",
            items = [{"Ports", "234"}]
        },
        
        %% Stats
        #stat_row{
            items = [
                {"TCP Conns", "45"},
                {"UDP Sockets", "12"},
                {"Files", "177"}
            ]
        },

        %% IO Throughput sparklines
        #text{content = "I/O Throughput:", style = #{bold => true}},
        #hbox{spacing = 4, children = [
            #vbox{children = [
                #text{content = "Input (KB/s):", style = #{fg => green}},
                #sparkline{values = [100,150,120,180,200,175,220,190,250,230,280,260,300,290,320],
                           width = 20, style_type = block, color = green}
            ]},
            #vbox{children = [
                #text{content = "Output (KB/s):", style = #{fg => yellow}},
                #sparkline{values = [80,120,100,140,160,130,180,150,200,180,220,200,250,230,260],
                           width = 20, style_type = block, color = yellow}
            ]}
        ]},

        %% Port table
        #text{content = "Top Ports by I/O:", style = #{bold => true}},
        #table{
            id = port_table,
            height = fill,
            border = single,
            focusable = true,
            columns = [
                #table_col{id = port, header = "Port", width = 12},
                #table_col{id = name, header = "Name", width = 20},
                #table_col{id = input, header = "Input", width = 12, align = right},
                #table_col{id = output, header = "Output", width = 12, align = right}
            ],
            rows = [
                ["#Port<0.5>", "tcp_inet", "1.2 MB", "890 KB"],
                ["#Port<0.6>", "tcp_inet", "567 KB", "234 KB"],
                ["#Port<0.7>", "udp_inet", "123 KB", "45 KB"],
                ["#Port<0.8>", "efile", "89 KB", "12 KB"],
                ["#Port<0.9>", "tty_sl", "45 KB", "67 KB"]
            ],
            selected_row = 1
        },

        %% Status bar
        #status_bar{
            items = [
                {"H", "Home"},
                {"P", "Processes"},
                {"Q", "Quit"}
            ]
        }
    ]}.

handle_event(Event, State) ->
    case nit_shortcuts:handle(Event, State, [
        {["h", escape], fun(_) -> {switch, demo_home, #{}} end},
        {"p", fun(_) -> {switch, demo_processes, #{}} end},
        {"q", {stop, normal}}
    ]) of
        nomatch -> {unhandled, State};
        Result -> Result
    end.
