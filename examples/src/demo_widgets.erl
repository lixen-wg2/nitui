%%%-------------------------------------------------------------------
%%% @doc Demo Widgets - Showcases list, tabs, scroll, and table elements.
%%% @end
%%%-------------------------------------------------------------------
-module(demo_widgets).

-behaviour(nit_callback).

-include("nit_elements.hrl").

-export([init/1, view/1, handle_event/2]).

init(_Args) ->
    MenuItems = [
        "Dashboard",
        "Processes",
        "Network",
        "ETS Tables",
        "System Info",
        "Settings",
        "Help"
    ],
    {ok, #{
        menu_items => MenuItems,
        selected_idx => 0,
        log_wrap => false
    }}.

view(State) ->
    #{
        menu_items := MenuItems,
        selected_idx := SelectedIdx,
        log_wrap := LogWrap
    } = State,
    ActiveItem = nitui:selected_item(MenuItems, SelectedIdx, "Dashboard"),
    LogEntries = logs_for(ActiveItem),
    LogTitle = log_title(ActiveItem, LogWrap),
    MetricRows = metric_rows(ActiveItem),
    #vbox{children = [
        #header{
            title = "Widget Demo",
            subtitle = "Lists, tabs, scroll, and tables"
        },

        #hbox{spacing = 0, height = fill, children = [
            #box{
                id = menu_box,
                title = "Menu",
                border = single,
                width = 15,
                height = fill,
                focusable = true,
                children = [
                    #list{
                        id = menu_list,
                        items = MenuItems,
                        selected = SelectedIdx,
                        height = fill,
                        focusable = true,
                        selected_style = #{bg => blue, fg => white, bold => true}
                    }
                ]
            },

            #tabs{
                id = widget_tabs,
                width = fill,
                height = fill,
                focusable = true,
                style = #{fg => cyan},
                tabs = [
                    #tab{id = logs, label = "Logs", content = [
                        #vbox{children = [
                            #text{content = LogTitle, style = #{bold => true}},
                            #scroll{
                                id = log_scroll,
                                height = fill,
                                focusable = true,
                                children = [
                                    #vbox{children = [
                                        #text{content = Entry, wrap = LogWrap}
                                        || Entry <- LogEntries
                                    ]}
                                ]
                            }
                        ]}
                    ]},
                    #tab{id = metrics, label = "Metrics", content = [
                        #vbox{children = [
                            #stat_row{items = [
                                {"Source", item_label(ActiveItem)},
                                {"Rows", integer_to_list(length(MetricRows))},
                                {"Mode", "Synthetic"}
                            ]},
                            #table{
                                id = widget_metric_table,
                                height = fill,
                                border = single,
                                focusable = true,
                                columns = [
                                    #table_col{id = metric, header = "Metric", width = 24},
                                    #table_col{id = value, header = "Value", width = 14, align = right},
                                    #table_col{id = trend, header = "Trend", width = 12}
                                ],
                                rows = MetricRows,
                                selected_row = 1
                            }
                        ]}
                    ]},
                    #tab{id = notes, label = "Notes", content = [
                        #scroll{
                            id = notes_scroll,
                            height = fill,
                            focusable = true,
                            children = [
                                #vbox{children = [
                                    #text{content = Entry, wrap = true}
                                    || Entry <- notes_for(ActiveItem)
                                ]}
                            ]
                        }
                    ]}
                ]
            }
        ]},

        #status_bar{
            items = [
                {"H", "Home"},
                {"Left/Right", "Tabs"},
                {"W", "Wrap"},
                {"F", "Fullscreen"},
                {"Q", "Quit"}
            ]
        }
    ]}.

handle_event({list_select, menu_list, Idx, _Item}, State) ->
    {noreply, State#{selected_idx => Idx}};
handle_event({table_activate, widget_metric_table, _RowIdx, [Metric, Value, Trend]}, State) ->
    Modal = #modal{
        title = "Metric",
        width = 44,
        height = 8,
        style = #{fg => cyan, bold => true},
        children = [
            #vbox{children = [
                #text{content = Metric, style = #{fg => yellow, bold => true}},
                #text{content = ["Value: ", Value]},
                #text{content = ["Trend: ", Trend]},
                #spacer{height = 1},
                #text{content = "Press ESC to close", style = #{fg => white, dim => true}}
            ]}
        ]
    },
    {modal, Modal, State};
handle_event({event, {char, $w}}, State = #{log_wrap := LogWrap}) ->
    {noreply, State#{log_wrap => not LogWrap}};
handle_event({event, {char, $W}}, State = #{log_wrap := LogWrap}) ->
    {noreply, State#{log_wrap => not LogWrap}};
handle_event({event, {char, $f}}, State) ->
    {toggle_fullscreen, widget_tabs, State};
handle_event({event, {char, $F}}, State) ->
    {toggle_fullscreen, widget_tabs, State};
handle_event(Event, State) ->
    case nit_shortcuts:handle(Event, State, [
        {"h", fun(_) -> {switch, demo_home, #{}} end},
        {["q", escape], {stop, normal}}
    ]) of
        nomatch -> {unhandled, State};
        Result -> Result
    end.

logs_for("Dashboard") ->
    make_log_stream(
        [
            "[INFO] Dashboard layout initialized",
            "[INFO] KPI widgets loaded",
            "[DEBUG] Revenue sparkline seeded with demo data",
            "[INFO] Alert summary refreshed",
            "[WARN] Forecast source is using fallback values"
        ],
        fun(N) ->
            lists:flatten(io_lib:format(
                "[TRACE] Dashboard tile ~2..0B completed refresh in ~B ms",
                [N, 8 + (N rem 11)]))
        end);
logs_for("Processes") ->
    make_log_stream(
        [
            "[INFO] Process monitor attached to node demo@localhost",
            "[DEBUG] Enumerating top consumers by reductions",
            "[INFO] Mailbox sampler online",
            "[WARN] Process <0.421.0> exceeded soft queue threshold",
            "[INFO] Scheduler utilization snapshot captured"
        ],
        fun(N) ->
            lists:flatten(io_lib:format(
                "[TRACE] pid=<0.~B.0> reductions=~B mailbox=~B",
                [100 + N, 1200 + N * 37, N rem 9]))
        end);
logs_for("Network") ->
    make_log_stream(
        [
            "[INFO] Network probe started",
            "[INFO] Listening socket verified on port 8080",
            "[DEBUG] DNS cache warmed for demo upstreams",
            "[WARN] Retry budget increased for flaky edge route",
            "[INFO] TLS handshake metrics reset"
        ],
        fun(N) ->
            lists:flatten(io_lib:format(
                "[TRACE] conn=net-~2..0B rx=~BKB tx=~BKB rtt=~Bms",
                [N, 40 + N * 3, 25 + N * 2, 12 + (N rem 17)]))
        end);
logs_for("ETS Tables") ->
    make_log_stream(
        [
            "[INFO] ETS inspector opened",
            "[DEBUG] Sampling cache_index table",
            "[INFO] session_store table stats updated",
            "[WARN] routing_cache reached 78% of demo capacity",
            "[INFO] Expired entries cleanup completed"
        ],
        fun(N) ->
            lists:flatten(io_lib:format(
                "[TRACE] table=demo_cache shard=~2..0B objects=~B memory=~BKB",
                [N, 500 + N * 19, 64 + N * 4]))
        end);
logs_for("System Info") ->
    make_log_stream(
        [
            "[INFO] System overview collected",
            "[DEBUG] CPU topology cached",
            "[INFO] Memory watermark history loaded",
            "[WARN] Disk usage sample is synthetic demo data",
            "[INFO] Uptime counter synchronized"
        ],
        fun(N) ->
            lists:flatten(io_lib:format(
                "[TRACE] sample=~2..0B cpu=~B% mem=~B% load=~.1f",
                [N, 20 + (N rem 35), 35 + (N rem 40), 0.5 + (N rem 8) / 10]))
        end);
logs_for("Settings") ->
    make_log_stream(
        [
            "[INFO] Settings panel mounted",
            "[DEBUG] Theme preset loaded: terminal-classic",
            "[INFO] User preferences hydrated from demo profile",
            "[WARN] Autosave is disabled in demo mode",
            "[INFO] Keyboard shortcut map validated"
        ],
        fun(N) ->
            lists:flatten(io_lib:format(
                "[TRACE] setting=batch-~2..0B applied source=demo_profile version=~B",
                [N, 3 + (N rem 5)]))
        end);
logs_for("Help") ->
    make_log_stream(
        [
            "[INFO] Help index generated",
            "[DEBUG] Command palette tips loaded",
            "[INFO] Keyboard navigation guide prepared",
            "[WARN] External docs links are disabled in demo mode",
            "[INFO] Support shortcuts rendered"
        ],
        fun(N) ->
            lists:flatten(io_lib:format(
                "[TRACE] help-topic=section-~2..0B rendered with ~B examples",
                [N, 2 + (N rem 6)]))
        end);
logs_for(_Other) ->
    make_log_stream(
        [
            "[INFO] Generic log stream initialized"
        ],
        fun(N) ->
            lists:flatten(io_lib:format("[TRACE] fallback event ~2..0B", [N]))
        end).

make_log_stream(BaseEntries, Generator) ->
    BaseEntries ++ [Generator(N) || N <- lists:seq(1, 50)].

metric_rows("Dashboard") ->
    [
        ["Refresh latency", "18 ms", "stable"],
        ["Cards rendered", "8", "up"],
        ["Open alerts", "3", "down"],
        ["Cache hit rate", "94%", "stable"],
        ["Forecast delta", "+2.4%", "up"]
    ];
metric_rows("Processes") ->
    [
        ["Process count", integer_to_list(erlang:system_info(process_count)), "live"],
        ["Process limit", integer_to_list(erlang:system_info(process_limit)), "fixed"],
        ["Run queue", integer_to_list(erlang:statistics(run_queue)), "live"],
        ["Schedulers", integer_to_list(erlang:system_info(schedulers)), "fixed"],
        ["Reductions", nit_format:commas(element(1, erlang:statistics(reductions))), "live"]
    ];
metric_rows("Network") ->
    [
        ["TCP connections", "45", "stable"],
        ["UDP sockets", "12", "stable"],
        ["Input rate", "320 KB/s", "up"],
        ["Output rate", "260 KB/s", "up"],
        ["Retry budget", "72%", "down"]
    ];
metric_rows("ETS Tables") ->
    [
        ["Tables", integer_to_list(length(ets:all())), "live"],
        ["ETS memory", nit_format:bytes(erlang:memory(ets)), "live"],
        ["Named tables", "18", "stable"],
        ["Objects sampled", "12,480", "up"],
        ["Cleanup queue", "4", "down"]
    ];
metric_rows("System Info") ->
    [
        ["OTP release", erlang:system_info(otp_release), "fixed"],
        ["Atom count", nit_format:commas(erlang:system_info(atom_count)), "live"],
        ["Ports", nit_format:commas(erlang:system_info(port_count)), "live"],
        ["Total memory", nit_format:bytes(erlang:memory(total)), "live"],
        ["Node", atom_to_list(node()), "fixed"]
    ];
metric_rows("Settings") ->
    [
        ["Theme", "terminal-classic", "fixed"],
        ["Autosave", "disabled", "fixed"],
        ["Profiles", "3", "stable"],
        ["Pending changes", "0", "stable"],
        ["Shortcut maps", "validated", "fixed"]
    ];
metric_rows("Help") ->
    [
        ["Topics", "12", "stable"],
        ["Examples", "37", "stable"],
        ["Search index", "ready", "fixed"],
        ["External links", "disabled", "fixed"],
        ["Last render", "6 ms", "stable"]
    ];
metric_rows(_Other) ->
    [
        ["Events", "50", "stable"],
        ["Status", "ready", "fixed"],
        ["Warnings", "0", "stable"]
    ].

notes_for(ActiveItem) ->
    Label = item_label(ActiveItem),
    [
        ["Current area: ", Label],
        "Status: healthy",
        "Owner: demo runtime",
        "Sampling: synthetic values with selected live BEAM counters",
        "Last update: refreshed during render"
    ].

log_title(ActiveItem, LogWrap) ->
    lists:flatten(io_lib:format("Logs (~s) [w:~s]", [
        item_label(ActiveItem),
        on_off(LogWrap)
    ])).

item_label(undefined) ->
    "";
item_label(Item) when is_binary(Item) ->
    unicode:characters_to_list(Item);
item_label(Item) when is_list(Item) ->
    Item;
item_label({_, Label}) ->
    item_label(Label);
item_label(Item) ->
    lists:flatten(io_lib:format("~p", [Item])).

on_off(true) -> "on";
on_off(false) -> "off".
