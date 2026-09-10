-module(nit_table_sort_header_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("nitui/include/nit_elements.hrl").

sortable_headers_always_reserve_indicator_space_test() ->
    T = table(auto, left, <<"Name">>),
    ?assertEqual([<<"Name  ">>, <<"N  ">>], headers(T)),
    ?assertEqual([<<"Name ^">>, <<"N  ">>], headers(T#table{sort_by = first})),
    ?assertEqual([<<"Name v">>, <<"N  ">>],
                 headers(T#table{sort_by = first, sort_dir = desc})),
    ?assertEqual([<<"Name  ">>, <<"N ^">>], headers(T#table{sort_by = second})),
    ?assertEqual([<<"Name  ">>, <<"N  ">>], headers(T#table{sort_by = missing})),
    ?assertEqual([<<"Name">>, <<"N">>], headers(T#table{sortable = false})).

aligned_labels_and_data_do_not_move_test_() ->
    [?_test(begin
        T = table({fixed, 10}, Align, <<"Name">>),
        InitialHeader = rendered_row(T, 0),
        InitialData = rendered_row(T, 1),
        %% Exercise native sorting, including activating a different column.
        lists:foldl(fun(Id, Prev) ->
            Next = nit_el_table:toggle_sort(Prev, Id),
            Header = rendered_row(Next, 0),
            ?assertEqual(InitialHeader, without_indicator(Header)),
            ?assertEqual(InitialData, rendered_row(Next, 1)),
            Label = case Id of first -> <<"Name">>; second -> <<"N">> end,
            Suffix = case Next#table.sort_dir of asc -> <<" ^">>; desc -> <<" v">> end,
            ?assertNotEqual(nomatch, binary:match(Header, <<Label/binary, Suffix/binary>>)),
            Next
        end, T, [first, first, second, second, first])
    end) || Align <- [left, center, right]].

auto_widths_are_independent_of_sorted_column_test_() ->
    [?_test(begin
        T0 = table(auto, Align, <<"Name">>),
        T = T0#table{columns = [C#table_col{width = auto} || C <- T0#table.columns]},
        Initial = rendered_row(T, 0),
        lists:foreach(fun(Sorted) ->
            ?assertEqual([6, 3], nit_el_table:column_widths(Sorted, Sorted#table.rows, 30)),
            ?assertEqual(Initial, without_indicator(rendered_row(Sorted, 0)))
        end, sort_states(T))
    end) || Align <- [left, center, right]].

unicode_and_narrow_headers_keep_geometry_test_() ->
    [?_test(begin
        T = table({fixed, Width}, Align, Text),
        Initial = rendered_row(T, 0),
        lists:foreach(fun(Sorted) ->
            Header = rendered_row(Sorted, 0),
            ?assertEqual(30, nit_unicode:display_width(Header)),
            ?assertEqual(Initial, without_indicator(Header)),
            ?assertEqual([Width, 10], nit_el_table:column_widths(Sorted, [], 30))
        end, sort_states(T))
    end) || Align <- [left, center, right], Width <- [0, 1, 2, 3, 4, 5, 8],
            Text <- [<<"Name">>, <<"界語"/utf8>>, <<"e", 16#301/utf8, "界"/utf8>>]].

nonsortable_header_rendering_unchanged_test_() ->
    [?_test(begin
        T = (table({fixed, 10}, Align, <<"Name">>))#table{sortable = false},
        Header = rendered_row(T, 0),
        ?assertEqual({Start, 4}, binary:match(Header, <<"Name">>)),
        ?assertEqual(Header, rendered_row(T#table{sort_by = first, sort_dir = desc}, 0))
    end) || {Align, Start} <- [{left, 0}, {center, 3}, {right, 6}]].

table(Width, Align, Header) ->
    #table{id = headers, width = 30, height = 2, sortable = true,
           header_separator = false, column_separator = "|", zebra = false,
           columns = [#table_col{id = first, header = Header, width = Width, align = Align},
                      #table_col{id = second, header = <<"N">>, width = {fixed, 10}, align = Align}],
           rows = [[<<"x">>, <<"1">>]]}.

sort_states(T) ->
    [T#table{sort_by = Id, sort_dir = Dir}
     || Id <- [undefined, first, second, missing], Dir <- [asc, desc]].

headers(T) ->
    [unicode:characters_to_binary(H) || H <- nit_el_table:header_values(T)].

without_indicator(Header) ->
    binary:replace(Header, [<<"^">>, <<"v">>], <<" ">>, [global]).

rendered_row(T, Y) ->
    Output = iolist_to_binary(nit_el_table:render(T, #bounds{width = 30, height = 2}, #{})),
    Clean = re:replace(Output, <<"\e\\[[0-9;]*m|\e\\([AB]">>, <<>>,
                       [global, {return, binary}]),
    [_Before, RowAndRest] = binary:split(Clean, nit_ansi:move_to(Y, 0)),
    hd(binary:split(RowAndRest, <<"\e">>)).
