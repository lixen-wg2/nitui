%%%-------------------------------------------------------------------
%%% @doc Demo Tree Page - live application / supervision tree.
%%% @end
%%%-------------------------------------------------------------------
-module(demo_tree).

-behaviour(nit_callback).

-include("nit_elements.hrl").

-export([init/1, view/1, handle_event/2]).

init(_Args) ->
    {ok, #{}}.

view(_State) ->
    Apps = lists:sort(application:which_applications()),
    AppNodes = [app_node(App) || App <- Apps],
    #vbox{children = [
        #header{
            title = "Supervision Tree",
            subtitle = atom_to_list(node()),
            items = [{"Apps", integer_to_list(length(Apps))},
                     {"Processes", integer_to_list(length(erlang:processes()))}]
        },
        #tree{
            id = sup_tree,
            height = fill,
            focusable = true,
            nodes = AppNodes
        },
        #status_bar{items = [
            {"H", "Home"},
            {"Up/Down", "Select"},
            {"Left/Right", "Collapse/Expand"},
            {"Enter", "Details"},
            {"Q", "Quit"}
        ]}
    ]}.

handle_event({tree_activate, sup_tree, Pid}, State) when is_pid(Pid) ->
    {push, process_detail, #{pid => Pid}, State};
handle_event({tree_activate, sup_tree, _NodeId}, State) ->
    {noreply, State};
handle_event(Event, State) ->
    case nit_shortcuts:handle(Event, State, [
        {["h", escape], fun(_) -> {switch, demo_home, #{}} end},
        {"q", {stop, normal}}
    ]) of
        nomatch -> {unhandled, State};
        Result -> Result
    end.

%%====================================================================
%% Tree construction
%%====================================================================

app_node({Name, _Desc, Vsn}) ->
    Children = case app_root_sup(Name) of
        undefined -> [];
        RootSup   -> [sup_node(Name, RootSup)]
    end,
    Label = io_lib:format("~ts ~ts", [atom_to_list(Name), Vsn]),
    #tree_node{
        id = {app, Name},
        label = lists:flatten(Label),
        icon = <<"📦"/utf8>>,
        expanded = false,
        children = Children
    }.

app_root_sup(Name) ->
    case application_controller:get_master(Name) of
        undefined -> undefined;
        Master ->
            case application_master:get_child(Master) of
                {Pid, _} when is_pid(Pid) -> Pid;
                _ -> undefined
            end
    end.

sup_node(_ParentId, Pid) ->
    Children = sup_children(Pid),
    #tree_node{
        id = Pid,
        label = sup_label(Pid),
        icon = sup_icon(Pid),
        expanded = false,
        children = Children
    }.

sup_children(SupPid) ->
    try supervisor:which_children(SupPid) of
        Specs -> [child_node(C) || C <- Specs]
    catch _:_ -> []
    end.

child_node({Id, Pid, supervisor, _Modules}) when is_pid(Pid) ->
    sup_node(Id, Pid);
child_node({Id, Pid, worker, Modules}) when is_pid(Pid) ->
    #tree_node{
        id = Pid,
        label = worker_label(Id, Pid, Modules),
        icon = worker_icon(Pid)
    };
child_node({Id, undefined, _Type, _Modules}) ->
    #tree_node{id = {dead, Id}, label = label_text(Id) ++ " (not running)",
               icon = <<"💤"/utf8>>}.

%%====================================================================
%% Labels and icons
%%====================================================================

sup_label(Pid) ->
    Name = process_label(Pid),
    case sup_strategy(Pid) of
        undefined -> Name;
        Strategy  -> lists:flatten(io_lib:format("~ts [~ts]",
                                                 [Name, atom_to_list(Strategy)]))
    end.

worker_label(_Id, Pid, Modules) ->
    Name = process_label(Pid),
    case Modules of
        [Mod | _] when is_atom(Mod) ->
            ModStr = atom_to_list(Mod),
            case Name of
                ModStr -> Name;
                _      -> lists:flatten(io_lib:format("~ts (~ts)", [Name, ModStr]))
            end;
        _ -> Name
    end.

process_label(Pid) ->
    case erlang:process_info(Pid, registered_name) of
        {registered_name, Name} when is_atom(Name) -> atom_to_list(Name);
        _ -> pid_to_list(Pid)
    end.

label_text(Id) when is_atom(Id) -> atom_to_list(Id);
label_text(Id) -> lists:flatten(io_lib:format("~p", [Id])).

sup_icon(Pid) ->
    case sup_strategy(Pid) of
        one_for_all        -> <<"🌲"/utf8>>;
        rest_for_one       -> <<"🪴"/utf8>>;
        simple_one_for_one -> <<"🎋"/utf8>>;
        _                  -> <<"🌳"/utf8>>
    end.

worker_icon(Pid) ->
    case erlang:process_info(Pid, current_function) of
        {current_function, {gen_server, _, _}} -> <<"⚙ "/utf8>>;
        {current_function, {gen_statem, _, _}} -> <<"🔁"/utf8>>;
        {current_function, {gen_event,  _, _}} -> <<"📡"/utf8>>;
        _                                      -> <<"🔧"/utf8>>
    end.

sup_strategy(Pid) ->
    try sys:get_state(Pid, 200) of
        State when is_tuple(State), element(1, State) =:= state,
                   tuple_size(State) >= 3 ->
            valid_strategy(element(3, State));
        _ ->
            undefined
    catch _:_ -> undefined
    end.

valid_strategy(one_for_one)        -> one_for_one;
valid_strategy(one_for_all)        -> one_for_all;
valid_strategy(rest_for_one)       -> rest_for_one;
valid_strategy(simple_one_for_one) -> simple_one_for_one;
valid_strategy(_)                  -> undefined.
