-module(nit_tty_tests).

-include_lib("eunit/include/eunit.hrl").

cleanup_sequence_and_idempotence_test() ->
    Reader = make_ref(),
    State0 = nit_tty:state_for_test(active, Reader),
    {noreply, State} = nit_tty:handle_cast({set_resize_target, self()}, State0),
    {ok, Clean} = nit_tty:cleanup_for_test(State, operations(ack), 50),
    ?assertEqual([stop, handles, write, reinit], steps()),
    assert_demonitored(),
    ?assertEqual(nit_tty:state_for_test(undefined, undefined), Clean),
    %% The production callback also takes the no-op path, not just the seam.
    ?assertEqual({reply, ok, Clean}, nit_tty:handle_call(cleanup, unused, Clean)),
    ?assertEqual({ok, Clean}, nit_tty:cleanup_for_test(Clean, #{}, 0)),
    ?assertEqual([], steps()).

cleanup_timeout_still_restores_mode_test() ->
    State = nit_tty:state_for_test(active, make_ref()),
    Started = erlang:monotonic_time(millisecond),
    {Result, Clean} = nit_tty:cleanup_for_test(State, operations(timeout), 10),
    Elapsed = erlang:monotonic_time(millisecond) - Started,
    ?assertEqual({error, cleanup_failed}, Result),
    ?assert(Elapsed >= 10),
    ?assert(Elapsed < 1000),
    ?assertEqual([stop, handles, write, reinit], steps()),
    assert_demonitored(),
    assert_closed(Clean),
    %% Do not mask a failed first attempt when the launcher calls cleanup again.
    ?assertEqual({reply, Result, Clean}, nit_tty:handle_call(cleanup, unused, Clean)),
    ?assertEqual({Result, Clean}, nit_tty:cleanup_for_test(Clean, #{}, 0)),
    ?assertEqual([], steps()).

cleanup_writer_down_still_restores_mode_test() ->
    State = nit_tty:state_for_test(active, make_ref()),
    {Result, Clean} = nit_tty:cleanup_for_test(State, operations(down), 1000),
    ?assertEqual({error, cleanup_failed}, Result),
    ?assertEqual([stop, handles, write, reinit], steps()),
    assert_demonitored(),
    assert_closed(Clean).

cleanup_operation_exceptions_are_sanitized_test_() ->
    [?_test(begin
        Ops0 = operations(ack),
        Fail = fun(Args) ->
            step(FailedOp),
            erlang:error({private_failure_marker, Args})
        end,
        Ops = case FailedOp of
            reader_stop -> Ops0#{reader_stop := fun(Tty) -> Fail([Tty]) end,
                                handles := fun(active) ->
                                    step(handles), erlang:error(private_failure_marker)
                                end,
                                reinit := fun(active, Options) ->
                                    ?assertEqual(cooked_options(), Options),
                                    step(reinit), cooked
                                end};
            handles -> Ops0#{handles := fun(Tty) -> Fail([Tty]) end};
            write -> Ops0#{write := fun(Tty, Output, From) ->
                Fail([Tty, Output, From])
            end};
            reinit -> Ops0#{reinit := fun(Tty, Options) -> Fail([Tty, Options]) end}
        end,
        State = nit_tty:state_for_test(active, make_ref()),
        {Result, Clean} = nit_tty:cleanup_for_test(State, Ops, 0),
        ?assertEqual({error, cleanup_failed}, Result),
        ?assertEqual(ExpectedSteps, steps()),
        assert_closed(Clean)
    end) || {FailedOp, ExpectedSteps} <- [
        {reader_stop, [reader_stop, handles, reinit]},
        {handles, [stop, handles, reinit]},
        {write, [stop, handles, write, reinit]},
        {reinit, [stop, handles, write, reinit]}
    ]].

cleanup_unexpected_write_reply_still_restores_mode_test() ->
    Ops = (operations(ack))#{write := fun(_, _, _) ->
        step(write), {error, private_failure_marker}
    end},
    State = nit_tty:state_for_test(active, make_ref()),
    {Result, Clean} = nit_tty:cleanup_for_test(State, Ops, 0),
    ?assertEqual({error, cleanup_failed}, Result),
    ?assertEqual([stop, handles, write, reinit], steps()),
    assert_closed(Clean).

cleanup_waits_for_matching_ack_test() ->
    Parent = self(),
    WriterRef = make_ref(),
    Ops0 = operations(ack),
    Ops = Ops0#{handles := fun(stopped) -> #{write => WriterRef} end,
                write := fun(stopped, Output, From) ->
                    ?assertEqual(reset_output(), Output),
                    ?assertEqual(self(), From),
                    Monitor = erlang:monitor(process, Parent),
                    Parent ! {pending_reset, From, Monitor},
                    {ok, Monitor}
                end,
                reinit := fun(stopped, Options) ->
                    ?assertEqual(cooked_options(), Options),
                    Parent ! restored,
                    cooked
                end},
    {Owner, OwnerMonitor} = spawn_monitor(fun() ->
        State = nit_tty:state_for_test(active, make_ref()),
        {Result, _} = nit_tty:cleanup_for_test(State, Ops, 1000),
        Parent ! {completed, Result}
    end),
    try
        receive {pending_reset, Owner, _} -> ok after 1000 -> error(no_write) end,
        %% Neither another writer's ack nor an unrelated DOWN completes drain.
        Owner ! {make_ref(), ok},
        Owner ! {'DOWN', make_ref(), process, Parent, private_failure_marker},
        receive restored -> error(restored_before_ack) after 20 -> ok end,
        Owner ! {WriterRef, ok},
        receive restored -> ok after 1000 -> error(no_restore) end,
        receive {completed, Result} -> ?assertEqual(ok, Result)
        after 1000 -> error(no_completion)
        end,
        receive {'DOWN', OwnerMonitor, process, Owner, Reason} ->
            ?assertEqual(normal, Reason)
        after 1000 -> error(owner_alive)
        end
    after
        exit(Owner, kill),
        erlang:demonitor(OwnerMonitor, [flush])
    end.

cleanup_drops_writes_and_late_input_test() ->
    Reader = make_ref(),
    State = nit_tty:state_for_test(active, Reader),
    {ok, Clean} = nit_tty:cleanup_for_test(State, operations(ack), 0),
    ?assertEqual([stop, handles, write, reinit], steps()),
    %% Invalid iodata proves writes are dropped before any conversion or IO.
    ?assertEqual({noreply, Clean}, nit_tty:handle_cast({write, #{invalid => data}}, Clean)),
    ?assertEqual({noreply, Clean}, nit_tty:handle_cast({set_resize_target, self()}, Clean)),
    lists:foreach(fun(Message) ->
        ?assertEqual({noreply, Clean}, nit_tty:handle_info(Message, Clean))
    end, [{Reader, {data, <<"late input">>}}, {Reader, eof},
          {Reader, {signal, sigwinch}}, {Reader, {signal, sigcont}},
          {signal, sigwinch}, sigwinch, {make_ref(), ok},
          %% Even a malformed tag must not match the cleared reader reference.
          {undefined, {data, <<"late input">>}}, {undefined, eof}]),
    assert_closed(Clean),
    ?assertEqual([], steps()).

cleanup_already_closed_test() ->
    State = nit_tty:state_for_test(undefined, undefined),
    ?assertEqual({ok, State}, nit_tty:cleanup_for_test(State, #{}, 0)),
    assert_closed(State).

operations(Reply) ->
    WriterRef = make_ref(),
    #{reader_stop => fun(active) -> step(stop), stopped end,
      handles => fun(stopped) -> step(handles), #{write => WriterRef} end,
      write => fun(stopped, Output, From) ->
          step(write),
          ?assertEqual(reset_output(), Output),
          ?assertEqual(self(), From),
          Monitor = erlang:monitor(process, group_leader()),
          put({?MODULE, monitor}, Monitor),
          case Reply of
              ack -> From ! {WriterRef, ok};
              timeout -> ok;
              down -> From ! {'DOWN', Monitor, process, group_leader(), private_failure_marker}
          end,
          {ok, Monitor}
      end,
      reinit => fun(stopped, Options) ->
          step(reinit),
          ?assertEqual(cooked_options(), Options),
          cooked
      end}.

reset_output() ->
    unicode:characters_to_binary([
        nit_terminal:reset(), nit_terminal:mouse_mode_off(),
        nit_terminal:keypad_transmit_mode_off(), nit_terminal:cursor_show(),
        nit_terminal:alternate_screen_off()
    ]).

cooked_options() ->
    #{input => disabled, output => cooked}.

assert_closed(State) ->
    ?assertEqual({reply, {error, terminal_closed}, State},
                 nit_tty:handle_call(get_size, unused, State)).

assert_demonitored() ->
    Monitor = erase({?MODULE, monitor}),
    ?assert(is_reference(Monitor)),
    ?assertEqual(false, erlang:demonitor(Monitor, [info])),
    receive {'DOWN', Monitor, _, _, _} -> error(unflushed_monitor)
    after 0 -> ok
    end.

step(Step) ->
    self() ! {?MODULE, Step},
    ok.

steps() ->
    receive {?MODULE, Step} -> [Step | steps()]
    after 0 -> []
    end.