-module(nit_clipboard_tests).

-include_lib("eunit/include/eunit.hrl").

ascii_direct_test() ->
    Expected = <<"\e]52;c;aGVsbG8=", 7>>,
    ?assertEqual({ok, Expected}, nit_clipboard:encode(<<"hello">>, #{})),
    ?assertEqual({ok, Expected}, nit_clipboard:encode("hello", #{transport => direct})).

unicode_chardata_test() ->
    Text = [16#e9, [16#4e2d], <<16#1f600/utf8>>],
    Utf8 = <<16#e9/utf8, 16#4e2d/utf8, 16#1f600/utf8>>,
    {ok, Output} = nit_clipboard:encode(Text, #{}),
    ?assertEqual(Utf8, base64:decode(direct_payload(Output))),
    ?assertEqual({ok, Output}, nit_clipboard:encode(Utf8, #{})).

controls_are_only_base64_never_queries_test() ->
    Text = <<"synthetic\e]52;c;?", 7, "\e\\\n\r\t", 0, 127, 16#9b/utf8>>,
    {ok, Output} = nit_clipboard:encode(Text, #{}),
    Payload = direct_payload(Output),
    ?assertEqual(Text, base64:decode(Payload)),
    ?assertEqual(match, re:run(Payload, <<"^[A-Za-z0-9+/]*={0,2}$">>, [{capture, none}])),
    ?assertEqual(nomatch, binary:match(Output, <<"?">>)),
    ?assertEqual([{0, 1}], binary:matches(Output, <<27>>)),
    ?assertEqual([{byte_size(Output) - 1, 1}], binary:matches(Output, <<7>>)).

tmux_frame_test() ->
    ?assertEqual({ok, <<"\ePtmux;\e\e]52;c;aGVsbG8=", 7, "\e\\">>},
                 nit_clipboard:encode(<<"hello">>, #{transport => tmux})).

empty_is_an_explicit_write_test() ->
    ?assertEqual({ok, <<"\e]52;c;", 7>>}, nit_clipboard:encode(<<>>, #{})),
    ?assertEqual({ok, <<"\e]52;c;", 7>>}, nit_clipboard:encode([], #{})),
    ?assertEqual({ok, <<"\ePtmux;\e\e]52;c;", 7, "\e\\">>},
                 nit_clipboard:encode([], #{transport => tmux})).

invalid_text_test_() ->
    [?_assertEqual({error, invalid_text}, nit_clipboard:encode(Text, #{})) || Text <- [
        undefined, 123, 1.0, #{}, {text, <<"synthetic">>}, <<1:1>>,
        <<255>>, <<195>>, <<"valid prefix", 255>>, <<"valid prefix", 226, 130>>,
        [-1], [16#d800], [16#110000], [<<"valid prefix">>, invalid], [$a | $b]
    ]].

raw_byte_bounds_test() ->
    AtDefault = binary:copy(<<"x">>, 65536),
    {ok, Output} = nit_clipboard:encode(AtDefault, #{}),
    ?assertEqual(AtDefault, base64:decode(direct_payload(Output))),
    ?assert(byte_size(Output) > 65536),
    ?assertEqual({error, too_large}, nit_clipboard:encode(<<AtDefault/binary, $x>>, #{})),
    ?assertEqual({error, too_large}, nit_clipboard:encode(lists:duplicate(65537, $x), #{})),
    ?assertMatch({ok, _}, nit_clipboard:encode([16#1f600], #{max_bytes => 4})),
    ?assertEqual({error, too_large}, nit_clipboard:encode([16#1f600], #{max_bytes => 3})),
    ?assertMatch({ok, _}, nit_clipboard:encode(<<"x">>, #{max_bytes => 1})),
    AtHardLimit = binary:copy(<<"x">>, 1048576),
    ?assertMatch({ok, _}, nit_clipboard:encode(AtHardLimit, #{max_bytes => 1048576})),
    ?assertEqual({error, too_large},
                 nit_clipboard:encode(<<AtHardLimit/binary, $x>>, #{max_bytes => 1048576})).

invalid_options_test_() ->
    Options = [#{max_bytes => Limit} || Limit <- [0, -1, 1.5, 1048577, infinity, undefined]]
        ++ [#{transport => auto}, #{transport => <<"tmux">>}, #{max_byte => 1}, [], undefined],
    [?_assertEqual({error, unavailable}, nit_clipboard:encode(<<"synthetic">>, Opt))
     || Opt <- Options].

disabled_takes_precedence_test_() ->
    [?_assertEqual({error, disabled}, nit_clipboard:encode(invalid,
        #{enabled => Enabled, max_bytes => invalid, transport => invalid}))
     || Enabled <- [false, undefined, <<"true">>, 1]].

encode_does_not_read_app_env_test() ->
    with_env(#{clipboard_enabled => false, clipboard_max_bytes => 1,
               clipboard_transport => invalid}, fun() ->
        ?assertMatch({ok, <<"\e]52;c;", _/binary>>},
                     nit_clipboard:encode(<<"synthetic">>, #{}))
    end).

public_copy_sends_one_complete_frame_test_() ->
    [?_test(with_env(Env, fun() ->
        with_tty(ok, fun(Pid, Ref) ->
            Text = <<"synthetic\n", 16#1f600/utf8>>,
            {ok, Expected} = nit_clipboard:encode(Text, #{transport => Transport}),
            ?assertEqual({ok, sent}, nitui:copy_to_clipboard(Text)),
            ?assertEqual([{write, Expected}], tty_events(Pid, Ref))
        end)
    end)) || {Env, Transport} <- [
        {#{}, direct}, {#{clipboard_enabled => true, clipboard_transport => tmux}, tmux}
    ]].

refusals_never_submit_a_prefix_test_() ->
    [?_test(with_env(Env, fun() ->
        with_tty(ok, fun(Pid, Ref) ->
            ?assertEqual({error, Reason}, nit_clipboard:copy(Text)),
            ?assertEqual([], tty_events(Pid, Ref))
        end)
    end)) || {Env, Text, Reason} <- [
        {#{clipboard_enabled => false}, <<"synthetic">>, disabled},
        {#{clipboard_enabled => <<"true">>}, <<"synthetic">>, disabled},
        {#{clipboard_max_bytes => 0}, <<"synthetic">>, unavailable},
        {#{clipboard_max_bytes => 1048577}, <<"synthetic">>, unavailable},
        {#{clipboard_transport => auto}, <<"synthetic">>, unavailable},
        {#{clipboard_max_bytes => 3}, <<"prefix">>, too_large},
        {#{}, binary:copy(<<"x">>, 65537), too_large},
        {#{}, <<"valid prefix", 255>>, invalid_text},
        {#{}, <<"valid prefix", 195>>, invalid_text},
        {#{}, [<<"valid prefix">>, invalid], invalid_text}
    ]].

absent_and_stopped_tty_test() ->
    with_env(#{}, fun() ->
        ?assertEqual(undefined, whereis(nit_tty)),
        ?assertEqual({error, unavailable}, nit_clipboard:copy(<<"synthetic">>)),
        with_tty({stop, normal}, fun(_Pid, _Ref) ->
            ?assertEqual({error, unavailable}, nit_clipboard:copy(<<"synthetic">>))
        end),
        ?assertEqual({error, unavailable}, nitui:copy_to_clipboard(<<"synthetic">>))
    end).

server_failures_are_sanitized_test_() ->
    [?_test(with_env(#{}, fun() ->
        with_tty(Reply, fun(_Pid, _Ref) ->
            ?assertEqual({error, write_failed}, nit_clipboard:copy(<<"synthetic">>))
        end)
    end)) || Reply <- [{error, {private_failure_marker, <<"synthetic">>}}, unexpected,
                       {stop, {private_failure_marker, <<"synthetic">>}}]].

control_write_results_and_no_retry_test_() ->
    [?_test(begin
        Ref = make_ref(),
        State = nit_tty:state_for_test(active, make_ref()),
        {ok, Output} = nit_clipboard:encode(<<"synthetic">>, #{}),
        Timeout = case Mode of timeout -> 20; wrong_ack -> 20; _ -> 1000 end,
        guarded_output(fun() ->
            ?assertEqual(Expected, nit_tty:write_control_for_test(
                State, Output, operations(Mode, Ref), Timeout))
        end),
        Events = drain(Ref),
        ?assertEqual(1, length([ok || {write, _, _} <- Events])),
        [{write, Written, Recipient}] = [E || E = {write, _, _} <- Events],
        ?assertEqual(Output, Written),
        %% The recipient must disappear even on exception or timeout.
        wait_dead(Recipient),
        lists:foreach(fun({monitor, Monitor}) ->
            ?assertEqual(false, erlang:demonitor(Monitor, [info])); (_) -> ok
        end, Events)
    end) || {Mode, Expected} <- [
        {ack, ok}, {timeout, {error, write_failed}}, {down, {error, write_failed}},
        {wrong_ack, {error, write_failed}}, {exception, {error, write_failed}},
        {bad_return, {error, write_failed}}
    ]].

closed_invalid_and_expired_control_writes_test() ->
    Closed = nit_tty:state_for_test(undefined, undefined),
    Active = nit_tty:state_for_test(active, make_ref()),
    ?assertEqual({error, unavailable}, nit_tty:write_control_for_test(Closed, <<>>, #{}, 20)),
    ?assertEqual({error, write_failed}, nit_tty:write_control_for_test(Active, invalid, #{}, 20)),
    ?assertEqual({error, write_failed}, nit_tty:write_control(invalid)),
    Deadline = erlang:monotonic_time(millisecond) - 1,
    ?assertEqual({reply, {error, write_failed}, Active},
                 nit_tty:handle_call({write_control, <<"synthetic">>, Deadline}, unused, Active)),
    ?assertEqual({reply, {error, unavailable}, Closed},
                 nit_tty:handle_call({write_control, <<"synthetic">>, Deadline}, unused, Closed)).

cleanup_disables_control_writes_test_() ->
    [?_test(begin
        Ref = make_ref(),
        State = nit_tty:state_for_test(active, make_ref()),
        Ops = (operations(Mode, Ref))#{reader_stop => fun(active) -> active end,
                                      reinit => fun(active, _) -> cooked end},
        {_, Clean} = nit_tty:cleanup_for_test(State, Ops, 20),
        drain(Ref),
        ?assertEqual({error, unavailable},
                     nit_tty:write_control_for_test(Clean, <<"synthetic">>, Ops, 20)),
        Deadline = erlang:monotonic_time(millisecond) + 1000,
        ?assertEqual({reply, {error, unavailable}, Clean},
                     nit_tty:handle_call({write_control, <<"synthetic">>, Deadline}, unused, Clean)),
        ?assertEqual([], drain(Ref))
    end) || Mode <- [ack, bad_return]].

handles_failure_is_sanitized_without_writing_test() ->
    State = nit_tty:state_for_test(active, make_ref()),
    Ref = make_ref(),
    Ops = #{handles => fun(_) -> error(private_failure_marker) end,
            write => fun(_, _, _) -> self() ! {Ref, unexpected_write}, ok end},
    guarded_output(fun() ->
        ?assertEqual({error, write_failed},
                     nit_tty:write_control_for_test(State, <<"synthetic">>, Ops, 20)),
        ?assertEqual([], drain(Ref))
    end).

control_write_waits_for_matching_ack_test() ->
    Parent = self(),
    Ref = make_ref(),
    WriterRef = make_ref(),
    Ops = #{handles => fun(active) -> #{write => WriterRef} end,
            write => fun(active, <<"synthetic">>, Recipient) ->
                Monitor = erlang:monitor(process, Parent),
                Parent ! {Ref, {pending, Recipient}},
                {ok, Monitor}
            end},
    Owner = spawn(fun() ->
        State = nit_tty:state_for_test(active, make_ref()),
        Result = nit_tty:write_control_for_test(State, <<"synthetic">>, Ops, 1000),
        Parent ! {Ref, {completed, Result}}
    end),
    try
        Recipient = receive {Ref, {pending, Pid}} -> Pid
        after 1000 -> error(no_write)
        end,
        Recipient ! {make_ref(), ok},
        receive {Ref, {completed, _}} -> error(completed_before_ack)
        after 20 -> ok
        end,
        Recipient ! {WriterRef, ok},
        receive {Ref, {completed, Result}} -> ?assertEqual(ok, Result)
        after 1000 -> error(no_completion)
        end,
        wait_dead(Recipient)
    after
        exit(Owner, kill),
        wait_dead(Owner),
        drain(Ref)
    end.

late_ack_cannot_complete_next_write_test() ->
    State = nit_tty:state_for_test(active, make_ref()),
    WriterRef = make_ref(),
    Ref = make_ref(),
    Ops = #{handles => fun(active) -> #{write => WriterRef} end,
            write => fun(active, _, Recipient) ->
                case put(Ref, Recipient) of
                    undefined -> ok;
                    OldRecipient -> OldRecipient ! {WriterRef, ok}
                end,
                {ok, erlang:monitor(process, self())}
            end},
    try
        ?assertEqual({error, write_failed},
                     nit_tty:write_control_for_test(State, <<"synthetic">>, Ops, 20)),
        ?assertEqual({error, write_failed},
                     nit_tty:write_control_for_test(State, <<"synthetic">>, Ops, 20))
    after erase(Ref)
    end.

status_reports_redact_control_payloads_test() ->
    Request = {write_control, <<"synthetic">>, 123},
    Status = #{state => active, message => Request,
               reason => {failure, Request}, log => [{in, Request, self()}, {out, ok, self()}]},
    Redacted = {write_control, redacted},
    ?assertEqual(#{state => active, message => Redacted, reason => {failure, Redacted},
                   log => [{in, Redacted, self()}, {out, ok, self()}]},
                 nit_tty:format_status(Status)),
    ?assertEqual(#{state => active, message => cleanup, log => []},
                 nit_tty:format_status(#{state => active, message => cleanup, log => []})).

direct_payload(<<"\e]52;c;", Tail/binary>>) ->
    Size = byte_size(Tail) - 1,
    <<Payload:Size/binary, 7>> = Tail,
    Payload.

with_env(Values, Fun) ->
    Keys = [clipboard_enabled, clipboard_max_bytes, clipboard_transport],
    Saved = [{Key, application:get_env(nitui, Key)} || Key <- Keys],
    try
        lists:foreach(fun(Key) -> application:unset_env(nitui, Key) end, Keys),
        maps:foreach(fun(Key, Value) -> application:set_env(nitui, Key, Value) end, Values),
        Fun()
    after
        lists:foreach(fun
            ({Key, undefined}) -> application:unset_env(nitui, Key);
            ({Key, {ok, Value}}) -> application:set_env(nitui, Key, Value)
        end, Saved)
    end.

with_tty(Reply, Fun) ->
    %% Fail rather than replacing or sending anything to a real running tty.
    ?assertEqual(undefined, whereis(nit_tty)),
    Parent = self(),
    Ref = make_ref(),
    Pid = spawn(fun() -> fake_tty(Parent, Ref, Reply) end),
    try
        true = register(nit_tty, Pid),
        Fun(Pid, Ref)
    after
        exit(Pid, kill),
        wait_dead(Pid),
        drain(Ref)
    end.

fake_tty(Parent, Ref, Reply) ->
    receive
        {'$gen_call', From, {write_control, Output, Deadline}} when is_integer(Deadline) ->
            Parent ! {Ref, {write, Output}},
            case Reply of
                {stop, Reason} -> exit(Reason);
                _ -> gen_server:reply(From, Reply), fake_tty(Parent, Ref, Reply)
            end;
        {'$gen_call', From, barrier} ->
            gen_server:reply(From, ok),
            fake_tty(Parent, Ref, Reply);
        Message ->
            Parent ! {Ref, {unexpected, Message}},
            fake_tty(Parent, Ref, Reply)
    end.

tty_events(Pid, Ref) ->
    ok = gen_server:call(Pid, barrier),
    drain(Ref).

operations(Mode, Ref) ->
    WriterRef = make_ref(),
    #{handles => fun(active) -> #{write => WriterRef} end,
      write => fun(active, Output, Recipient) ->
          self() ! {Ref, {write, Output, Recipient}},
          case Mode of
              exception -> error({private_failure_marker, Output});
              bad_return -> {error, {private_failure_marker, Output}};
              _ ->
                  Monitor = erlang:monitor(process, self()),
                  self() ! {Ref, {monitor, Monitor}},
                  case Mode of
                      ack -> Recipient ! {WriterRef, ok};
                      wrong_ack -> Recipient ! {make_ref(), ok};
                      down -> self() ! {'DOWN', Monitor, process, self(), private_failure_marker};
                      timeout -> ok
                  end,
                  {ok, Monitor}
          end
      end}.

guarded_output(Fun) ->
    Parent = self(),
    Ref = make_ref(),
    Original = group_leader(),
    Guard = spawn(fun() -> io_guard(Parent, Ref) end),
    Filter = fun(Event, _) -> Parent ! {Ref, {unexpected_log, Event}}, stop end,
    ok = logger:add_primary_filter(?MODULE, {Filter, undefined}),
    try
        true = group_leader(Guard, self()),
        Fun(),
        ?assertEqual([], drain(Ref))
    after
        group_leader(Original, self()),
        logger:remove_primary_filter(?MODULE),
        exit(Guard, kill),
        wait_dead(Guard)
    end.

io_guard(Parent, Ref) ->
    receive
        {io_request, From, ReplyAs, _Request} ->
            Parent ! {Ref, unexpected_io},
            From ! {io_reply, ReplyAs, ok},
            io_guard(Parent, Ref)
    end.

wait_dead(Pid) ->
    Monitor = erlang:monitor(process, Pid),
    receive {'DOWN', Monitor, process, Pid, _} -> ok
    after 1000 -> error(process_still_alive)
    end.

drain(Ref) ->
    receive {Ref, Event} -> [Event | drain(Ref)] after 0 -> [] end.