%%%-------------------------------------------------------------------
%%% @doc Unit tests for nit_format.
%%% @end
%%%-------------------------------------------------------------------
-module(nit_format_tests).

-include_lib("eunit/include/eunit.hrl").

commas_test() ->
    ?assertEqual(<<"0">>, nit_format:commas(0)),
    ?assertEqual(<<"1,234,567">>, nit_format:commas(1234567)),
    ?assertEqual(<<"-9,876">>, nit_format:commas(-9876)).

bytes_test() ->
    ?assertEqual(<<"?">>, nit_format:bytes(undefined)),
    ?assertEqual(<<"512 B">>, nit_format:bytes(512)),
    ?assertEqual(<<"1.5 KB">>, nit_format:bytes(1536)),
    ?assertEqual(<<"2.0 MB">>, nit_format:bytes(2 * 1024 * 1024)).

duration_test() ->
    ?assertEqual(<<"01:02:03">>, nit_format:duration(3723)),
    ?assertEqual(<<"2d 03:04:05">>, nit_format:duration(2 * 86400 + 3 * 3600 + 4 * 60 + 5)),
    ?assertEqual(<<"-00:00:12">>, nit_format:duration(-12)).
