%%%-------------------------------------------------------------------
%%% @doc Unit tests for iso_input module.
%%%
%%% Tests the input parsing functionality including:
%%% - Arrow keys and navigation keys
%%% - Special keys (enter, tab, backspace, escape, delete)
%%% - Control characters
%%% - Regular characters (ASCII and UTF-8)
%%% - Mouse events (SGR format)
%%% - Incomplete escape sequence buffering
%%% @end
%%%-------------------------------------------------------------------
-module(iso_input_tests).

-include_lib("eunit/include/eunit.hrl").

%%====================================================================
%% Test helpers
%%====================================================================

%% Start iso_input, set target, send data, collect events, stop
send_and_receive(Data) ->
    {ok, _Pid} = iso_input:start_link(),
    iso_input:set_target(self()),
    iso_input:handle_data(Data),
    %% Small delay to allow async cast to process
    timer:sleep(10),
    Events = receive_all_events(),
    iso_input:stop(),
    Events.

%% For buffering tests - send data in parts
send_parts_and_receive(DataList) ->
    {ok, _Pid} = iso_input:start_link(),
    iso_input:set_target(self()),
    lists:foreach(fun(Data) ->
        iso_input:handle_data(Data),
        timer:sleep(10)
    end, DataList),
    Events = receive_all_events(),
    iso_input:stop(),
    Events.

receive_all_events() ->
    receive_all_events([]).

receive_all_events(Acc) ->
    receive
        {input, Event} ->
            receive_all_events([Event | Acc])
    after 50 ->
        lists:reverse(Acc)
    end.

%%====================================================================
%% Arrow key tests
%%====================================================================

up_arrow_test() ->
    ?assertEqual([{key, up}], send_and_receive(<<"\e[A">>)).

down_arrow_test() ->
    ?assertEqual([{key, down}], send_and_receive(<<"\e[B">>)).

right_arrow_test() ->
    ?assertEqual([{key, right}], send_and_receive(<<"\e[C">>)).

left_arrow_test() ->
    ?assertEqual([{key, left}], send_and_receive(<<"\e[D">>)).

shift_right_arrow_test() ->
    ?assertEqual([{key, {shift, right}}], send_and_receive(<<"\e[1;2C">>)).

shift_left_arrow_test() ->
    ?assertEqual([{key, {shift, left}}], send_and_receive(<<"\e[1;2D">>)).

%%====================================================================
%% Navigation key tests
%%====================================================================

home_key_test() ->
    ?assertEqual([{key, home}], send_and_receive(<<"\e[H">>)).

end_key_test() ->
    ?assertEqual([{key, 'end'}], send_and_receive(<<"\e[F">>)).

shift_home_key_test() ->
    ?assertEqual([{key, {shift, home}}], send_and_receive(<<"\e[1;2H">>)).

shift_end_key_test() ->
    ?assertEqual([{key, {shift, 'end'}}], send_and_receive(<<"\e[1;2F">>)).

page_up_test() ->
    ?assertEqual([{key, page_up}], send_and_receive(<<"\e[5~">>)).

page_down_test() ->
    ?assertEqual([{key, page_down}], send_and_receive(<<"\e[6~">>)).

delete_key_test() ->
    ?assertEqual([delete], send_and_receive(<<"\e[3~">>)).

shift_tab_test() ->
    ?assertEqual([{key, btab}], send_and_receive(<<"\e[Z">>)).

%%====================================================================
%% Special key tests
%%====================================================================

tab_key_test() ->
    ?assertEqual([tab], send_and_receive(<<9>>)).

enter_key_test() ->
    ?assertEqual([enter], send_and_receive(<<13>>)).

backspace_key_test() ->
    ?assertEqual([backspace], send_and_receive(<<127>>)).

escape_key_test() ->
    ?assertEqual([escape], send_and_receive(<<27>>)).

%%====================================================================
%% Control character tests
%%====================================================================

ctrl_a_test() ->
    ?assertEqual([{ctrl, $a}], send_and_receive(<<1>>)).

ctrl_c_test() ->
    ?assertEqual([{ctrl, $c}], send_and_receive(<<3>>)).

ctrl_z_test() ->
    ?assertEqual([{ctrl, $z}], send_and_receive(<<26>>)).

ctrl_at_test() ->
    ?assertEqual([{ctrl, $@}], send_and_receive(<<0>>)).

%%====================================================================
%% Regular character tests
%%====================================================================

single_letter_test() ->
    ?assertEqual([{char, $a}], send_and_receive(<<"a">>)).

uppercase_letter_test() ->
    ?assertEqual([{char, $Z}], send_and_receive(<<"Z">>)).

digit_test() ->
    ?assertEqual([{char, $5}], send_and_receive(<<"5">>)).

space_test() ->
    ?assertEqual([{char, $ }], send_and_receive(<<" ">>)).

multiple_chars_test() ->
    ?assertEqual([{char, $a}, {char, $b}, {char, $c}], send_and_receive(<<"abc">>)).

special_chars_test() ->
    ?assertEqual([{char, $!}, {char, $@}, {char, $#}], send_and_receive(<<"!@#">>)).

%%====================================================================
%% UTF-8 character tests
%%====================================================================

umlaut_test() ->
    %% ä = 228, UTF-8 encoded as <<195, 164>>
    ?assertEqual([{char, 228}], send_and_receive(<<228/utf8>>)).

euro_sign_test() ->
    %% € = 8364, UTF-8 encoded as <<226, 130, 172>>
    ?assertEqual([{char, 8364}], send_and_receive(<<8364/utf8>>)).

emoji_test() ->
    %% 😀 = 128512, UTF-8 encoded as <<240, 159, 152, 128>>
    ?assertEqual([{char, 128512}], send_and_receive(<<128512/utf8>>)).

%%====================================================================
%% Mouse event tests (SGR format)
%%====================================================================

left_click_test() ->
    ?assertEqual([{mouse, click, left, 10, 5}], send_and_receive(<<"\e[<0;10;5M">>)).

right_click_test() ->
    ?assertEqual([{mouse, click, right, 20, 15}], send_and_receive(<<"\e[<2;20;15M">>)).

middle_click_test() ->
    ?assertEqual([{mouse, click, middle, 5, 10}], send_and_receive(<<"\e[<1;5;10M">>)).

mouse_release_test() ->
    ?assertEqual([{mouse, release, left, 10, 5}], send_and_receive(<<"\e[<0;10;5m">>)).

mouse_motion_test() ->
    ?assertEqual([{mouse, motion, left, 15, 20}], send_and_receive(<<"\e[<32;15;20M">>)).

scroll_test() ->
    ?assertEqual([{mouse, scroll, up, 10, 5}], send_and_receive(<<"\e[<64;10;5M">>)).

scroll_down_test() ->
    ?assertEqual([{mouse, scroll, down, 10, 5}], send_and_receive(<<"\e[<65;10;5M">>)).

%%====================================================================
%% Mixed input tests
%%====================================================================

chars_then_arrow_test() ->
    ?assertEqual([{char, $a}, {char, $b}, {key, up}], send_and_receive(<<"ab\e[A">>)).

arrow_then_chars_test() ->
    ?assertEqual([{key, down}, {char, $x}, {char, $y}], send_and_receive(<<"\e[Bxy">>)).

escape_then_char_test() ->
    ?assertEqual([escape, {char, $a}], send_and_receive(<<"\ea">>)).

%%====================================================================
%% Incomplete sequence buffering tests
%%====================================================================

incomplete_escape_buffered_test() ->
    %% Send incomplete sequence then complete it
    ?assertEqual([{key, up}], send_parts_and_receive([<<"\e[">>, <<"A">>])).

incomplete_mouse_buffered_test() ->
    %% Send partial mouse sequence then complete it
    ?assertEqual([{mouse, click, left, 10, 5}], send_parts_and_receive([<<"\e[<0;10">>, <<";5M">>])).

incomplete_long_csi_buffered_test() ->
    %% F5 split after more than one parameter byte should still buffer correctly
    ?assertEqual([{key, f5}], send_parts_and_receive([<<"\e[15">>, <<"~">>])).
