%%%-------------------------------------------------------------------
%%% Terminal clipboard support for NitUI
%%%-------------------------------------------------------------------
-module(nit_clipboard).
-moduledoc """
Explicit, write-only terminal clipboard support (OSC 52).

No clipboard queries or reads are issued. `sent` describes terminal
output only: terminals and multiplexers may ignore or refuse OSC 52.
""".

-export([copy/1, encode/2]).
-export_type([error_reason/0, result/0, options/0]).

-define(DEFAULT_MAX_BYTES, 65536).
-define(HARD_MAX_BYTES, 1048576).

-type error_reason() :: disabled | too_large | invalid_text | unavailable | write_failed.
-type result() :: {ok, sent} | {error, error_reason()}.
-type options() :: #{enabled => boolean(), max_bytes => pos_integer(),
                     transport => direct | tmux}.

-doc """
Copy UTF-8 chardata using the active NitUI terminal, never stdio.

App env: `clipboard_enabled` (default `true`), `clipboard_max_bytes`
(`65536`, valid range 1..1048576), `clipboard_transport` (`direct` by
default, or `tmux`). tmux passthrough must be explicitly enabled here and
supported/configured by the multiplexer; its presence is not detected or
assumed.
""".
-spec copy(unicode:chardata()) -> result().
copy(Text) ->
    Options = #{enabled => application:get_env(nitui, clipboard_enabled, true),
                max_bytes => application:get_env(nitui, clipboard_max_bytes,
                                                  ?DEFAULT_MAX_BYTES),
                transport => application:get_env(nitui, clipboard_transport, direct)},
    case encode(Text, Options) of
        {ok, Output} ->
            case nit_tty:write_control(Output) of
                ok -> {ok, sent};
                {error, _} = Error -> Error
            end;
        {error, _} = Error ->
            Error
    end.

-doc """
Pure OSC 52 encoding.

Missing options use the same defaults as `copy/1`, without reading
application env. Only `true` enables encoding; other values return
`disabled`. Invalid limits, transports or option keys return `unavailable`.
The limit counts raw UTF-8 bytes, before base64. Refuse, never truncate.
Empty text is valid and produces an explicit clipboard-clearing write.
""".
-spec encode(unicode:chardata(), options()) -> {ok, binary()} | {error, error_reason()}.
encode(Text, Options) when is_map(Options) ->
    case maps:get(enabled, Options, true) of
        true ->
            Max = maps:get(max_bytes, Options, ?DEFAULT_MAX_BYTES),
            Transport = maps:get(transport, Options, direct),
            Extra = maps:without([enabled, max_bytes, transport], Options),
            case valid_options(Max, Transport) andalso map_size(Extra) =:= 0 of
                true -> encode_text(Text, Max, Transport);
                false -> {error, unavailable}
            end;
        _ ->
            {error, disabled}
    end;
encode(_Text, _Options) ->
    {error, unavailable}.

valid_options(Max, Transport) ->
    is_integer(Max) andalso Max > 0 andalso Max =< ?HARD_MAX_BYTES
        andalso (Transport =:= direct orelse Transport =:= tmux).

encode_text(Text, Max, _Transport) when is_binary(Text), byte_size(Text) > Max ->
    {error, too_large};
encode_text(Text, Max, Transport) ->
    try unicode:characters_to_binary(Text, utf8, utf8) of
        Bin when is_binary(Bin), byte_size(Bin) =< Max ->
            {ok, frame(base64:encode(Bin), Transport)};
        Bin when is_binary(Bin) ->
            {error, too_large};
        _ ->
            %% Includes incomplete UTF-8; never emit the valid prefix.
            {error, invalid_text}
    catch
        _:_ -> {error, invalid_text}
    end.

frame(Base64, direct) ->
    <<"\e]52;c;", Base64/binary, 7>>;
frame(Base64, tmux) ->
    %% DCS tmux passthrough doubles the inner ESC. Base64 contains no ESC,
    %% BEL, ST or query marker, so no user text can escape the OSC payload.
    <<"\ePtmux;\e\e]52;c;", Base64/binary, 7, "\e\\">>.