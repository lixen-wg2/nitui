%%%-------------------------------------------------------------------
%%% NitUI Text View Element
%%%-------------------------------------------------------------------
-module(nit_el_text_view).
-moduledoc """
Read-only wrapped text, with source-grapheme selection.

Only `render/3`, the size callbacks and `bounds/2` accept parent allocations.
Interaction functions accept resolved bounds; mouse coordinates are
one-based terminal coordinates. No clipboard or terminal cursor state
is changed here.
""".
-behaviour(nit_element).

-include("nit_elements.hrl").

-export([render/3, height/2, width/2, fixed_width/1]).
-export([bounds/2, key/3, mouse/5, scroll/4, copy_text/2, hit_action/4, merge/2]).

%% Lines share source boundary indexes at soft wraps. A boundary shared by
%% two lines belongs to the next line (including for cursor navigation).
-record(line, {start = 0, stop = 0, cells = [], width = 0, hard = false}).
-record(cell, {index, col, width, text}).
-record(layout, {lines, count, size, width, height, bar = false}).

%%====================================================================
%% Allocation and element callbacks
%%====================================================================

-spec bounds(#text_view{}, #bounds{}) -> #bounds{}.
bounds(View, Parent) ->
    X = clamp(View#text_view.x, max(0, Parent#bounds.width)),
    Y = clamp(View#text_view.y, max(0, Parent#bounds.height)),
    W = dimension(View#text_view.width, max(0, Parent#bounds.width - X)),
    AvailableH = max(0, Parent#bounds.height - Y),
    H = case View#text_view.height of
        auto when W =:= 0 -> 0;
        auto ->
            Lines = wrap(display_source(View), W),
            min(AvailableH, tuple_size(Lines) + toolbar_height(View, AvailableH));
        Value -> dimension(Value, AvailableH)
    end,
    #bounds{x = Parent#bounds.x + X, y = Parent#bounds.y + Y, width = W, height = H}.

-spec height(#text_view{}, #bounds{}) -> non_neg_integer() | {flex, 1}.
height(#text_view{height = fill}, _Parent) -> {flex, 1};
height(View, Parent) -> (bounds(View, Parent))#bounds.height.

-spec width(#text_view{}, #bounds{}) -> non_neg_integer().
width(View, Parent) ->
    dimension(View#text_view.width, max(0, Parent#bounds.width - View#text_view.x)).

-spec fixed_width(#text_view{}) -> auto | non_neg_integer().
fixed_width(#text_view{width = fill}) -> auto;
fixed_width(#text_view{width = W}) -> W.

-spec render(#text_view{}, #bounds{}, map()) -> iolist().
render(#text_view{visible = false}, _Parent, _Opts) -> [];
render(View, Parent, Opts) ->
    Bounds = bounds(View, Parent),
    case Bounds#bounds.width > 0 andalso Bounds#bounds.height > 0 of
        false -> [];
        true ->
            Layout = layout(display_source(View), View, Bounds),
            Offset = safe_offset(View#text_view.offset, Layout),
            Style = maps:merge(maps:get(base_style, Opts, #{}), View#text_view.style),
            Range = selection(View, Layout#layout.size),
            Pos = clamp(View#text_view.cursor_pos, Layout#layout.size),
            Cursor = case maps:get(focused, Opts, false) of
                true -> {line_at(Pos, Layout), Pos};
                false -> none
            end,
            [render_rows(View, Bounds, Layout, Offset, Style, Range, Cursor),
             render_bar(Bounds, Layout, Offset, Style),
             render_toolbar(View, Bounds, Style)]
    end.

%%====================================================================
%% Read-only interaction and rebuild state
%%====================================================================

-spec key(#text_view{}, term(), #bounds{}) -> #text_view{}.
key(View, {ctrl, $a}, Bounds) ->
    with_source(View, fun(Graphemes) ->
        Layout = layout(Graphemes, View, Bounds),
        reveal(View#text_view{cursor_pos = Layout#layout.size,
                              selection_anchor = 0, copy_status = idle}, Layout)
    end);
key(View, {key, {shift, Dir}}, Bounds) -> navigate(View, Dir, true, Bounds);
key(View, {key, Dir}, Bounds) -> navigate(View, Dir, false, Bounds);
key(View, _Event, _Bounds) -> View.

navigate(View, Dir, Shift, Bounds) ->
    case lists:member(Dir, [left, right, up, down, home, 'end', page_up, page_down]) of
        false -> View;
        true ->
            with_source(View, fun(Graphemes) ->
                Layout = layout(Graphemes, View, Bounds),
                Pos = clamp(View#text_view.cursor_pos, Layout#layout.size),
                Next = case {Shift, Dir, selection(View, Layout#layout.size)} of
                    {false, left, {Start, _}} -> Start;
                    {false, right, {_, Stop}} -> Stop;
                    _ -> move(Dir, Pos, Layout)
                end,
                Anchor = case {Shift, View#text_view.selection_anchor} of
                    {false, _} -> undefined;
                    {true, undefined} -> Pos;
                    {true, A} -> clamp(A, Layout#layout.size)
                end,
                reveal(View#text_view{cursor_pos = Next, selection_anchor = Anchor,
                                      copy_status = idle}, Layout)
            end)
    end.

-spec mouse(#text_view{}, press | drag | release, integer(), integer(), #bounds{}) -> #text_view{}.
mouse(View, press, Col, Row, Bounds) ->
    with_source(View, fun(Graphemes) ->
        Layout = layout(Graphemes, View, Bounds),
        X = Col - 1 - Bounds#bounds.x,
        Y = Row - 1 - Bounds#bounds.y,
        case X >= 0 andalso X < Layout#layout.width andalso
             Y >= 0 andalso Y < Layout#layout.height of
            false -> View;
            true ->
                Offset = safe_offset(View#text_view.offset, Layout),
                Pos = hit_position(X, Y + Offset, Layout),
                View#text_view{cursor_pos = Pos, selection_anchor = Pos,
                               offset = Offset, copy_status = idle}
        end
    end);
mouse(#text_view{selection_anchor = undefined} = View, _Phase, _Col, _Row, _Bounds) ->
    View;
mouse(View, Phase, Col, Row, Bounds) when Phase =:= drag; Phase =:= release ->
    with_source(View, fun(Graphemes) ->
        Layout = layout(Graphemes, View, Bounds),
        H = Layout#layout.height,
        W = Layout#layout.width,
        case H > 0 andalso W > 0 of
            false -> View;
            true ->
                Y = Row - 1 - Bounds#bounds.y,
                Delta = if Y < 0 -> Y; Y >= H -> Y - H + 1; true -> 0 end,
                Offset = safe_offset(safe_offset(View#text_view.offset, Layout) + Delta, Layout),
                X = clamp(Col - 1 - Bounds#bounds.x, W),
                Pos = hit_position(X, Offset + clamp(Y, H - 1), Layout),
                View#text_view{cursor_pos = Pos, offset = Offset, copy_status = idle,
                               selection_anchor = clamp(View#text_view.selection_anchor,
                                                        Layout#layout.size)}
        end
    end);
mouse(View, _Phase, _Col, _Row, _Bounds) -> View.

-spec scroll(#text_view{}, up | down, integer(), #bounds{}) -> #text_view{}.
scroll(View, Direction, Lines, Bounds) when Direction =:= up; Direction =:= down ->
    Layout = layout(display_source(View), View, Bounds),
    Amount = max(0, Lines),
    Delta = case Direction of up -> -Amount; down -> Amount end,
    View#text_view{offset = safe_offset(safe_offset(View#text_view.offset, Layout) + Delta,
                                       Layout)};
scroll(View, _Direction, _Lines, _Bounds) -> View.

-spec copy_text(#text_view{}, selection | all) ->
    {ok, binary()} | {error, no_selection | invalid_text}.
copy_text(View, Mode) ->
    case source(View) of
        {error, invalid_text} = Error -> Error;
        {ok, Binary, _Graphemes} when Mode =:= all -> {ok, Binary};
        {ok, _Binary, Graphemes} when Mode =:= selection ->
            case selection(View, length(Graphemes)) of
                none -> {error, no_selection};
                {Start, Stop} ->
                    {ok, unicode:characters_to_binary(
                           lists:sublist(lists:nthtail(Start, Graphemes), Stop - Start))}
            end
    end.

%% Only complete toolbar labels are active. Coordinates outside the widget,
%% in label spacing, or in clipped label fragments are ordinary text hits.
-spec hit_action(#text_view{}, integer(), integer(), #bounds{}) -> selection | all | text.
hit_action(#text_view{visible = true, show_toolbar = true}, Col, Row,
           #bounds{x = X, y = Y, width = W, height = H})
        when H > 0, W > 0, Row =:= Y + H, Col > X, Col =< X + W ->
    Local = Col - X - 1,
    case [Action || {Start, Label, Action} <- toolbar_labels(W),
                    Local >= Start, Local < Start + byte_size(Label)] of
        [Action] -> Action;
        [] -> text
    end;
hit_action(_View, _Col, _Row, _Bounds) -> text.

-spec merge(#text_view{}, #text_view{}) -> #text_view{}.
merge(#text_view{content = Content} = Old, #text_view{content = Content} = New) ->
    New#text_view{cursor_pos = Old#text_view.cursor_pos,
                  selection_anchor = Old#text_view.selection_anchor,
                  offset = Old#text_view.offset, copy_status = Old#text_view.copy_status};
merge(_Old, New) ->
    New#text_view{cursor_pos = 0, selection_anchor = undefined,
                  offset = 0, copy_status = idle}.

%%====================================================================
%% Source and linear layout
%%====================================================================

source(#text_view{content = Content}) ->
    try unicode:characters_to_binary(Content) of
        Binary when is_binary(Binary) ->
            {ok, Binary, string:to_graphemes(unicode:characters_to_list(Binary))};
        _ -> {error, invalid_text}
    catch error:_ -> {error, invalid_text}
    end.

with_source(View, Fun) ->
    case source(View) of
        {ok, _, Graphemes} -> Fun(Graphemes);
        {error, invalid_text} -> View
    end.

display_source(View) ->
    case source(View) of
        {ok, _, Graphemes} -> Graphemes;
        {error, invalid_text} -> []
    end.

layout(Graphemes, View, Bounds) ->
    W = max(0, Bounds#bounds.width),
    H = max(0, Bounds#bounds.height - toolbar_height(View, Bounds#bounds.height)),
    Full = wrap(Graphemes, max(1, W)),
    Bar = View#text_view.show_scrollbar andalso W > 1 andalso H > 0
          andalso tuple_size(Full) > H,
    {Width, Lines} = case Bar of
        true -> {W - 1, wrap(Graphemes, W - 1)};
        false -> {W, Full}
    end,
    #layout{lines = Lines, count = tuple_size(Lines), size = length(Graphemes),
            width = Width, height = H, bar = Bar}.

wrap(Graphemes, Width) ->
    list_to_tuple(wrap(Graphemes, Width, 0, 0, 0, [], [])).

wrap([], _Width, Index, Start, Col, Cells, Lines) ->
    lists:reverse([line(Start, Index, Col, Cells, false) | Lines]);
wrap([G | Rest] = Remaining, Width, Index, Start, Col, Cells, Lines) ->
    case is_newline(G) of
        true ->
            wrap(Rest, Width, Index + 1, Index + 1, 0, [],
                 [line(Start, Index, Col, Cells, true) | Lines]);
        false ->
            {Text, CellWidth} = display(G, Col, Width),
            case Col > 0 andalso Col + CellWidth > Width of
                true ->
                    wrap(Remaining, Width, Index, Index, 0, [],
                         [line(Start, Index, Col, Cells, false) | Lines]);
                false ->
                    Cell = #cell{index = Index, col = Col, width = CellWidth, text = Text},
                    wrap(Rest, Width, Index + 1, Start, Col + CellWidth, [Cell | Cells], Lines)
            end
    end.

line(Start, Stop, Col, Cells, Hard) ->
    #line{start = Start, stop = Stop, width = Col, cells = lists:reverse(Cells), hard = Hard}.

is_newline($\n) -> true;
is_newline($\r) -> true;
is_newline([$\r, $\n]) -> true;
is_newline(16#2028) -> true;
is_newline(16#2029) -> true;
is_newline(_) -> false.

display($\t, Col, Width) ->
    Size = min(Width, 8 - Col rem 8),
    {binary:copy(<<" ">>, Size), Size};
display(G, _Col, Width) ->
    Chars = case is_integer(G) of true -> [G]; false -> G end,
    Safe = [safe_char(C) || C <- Chars],
    Size = grapheme_width(Safe),
    case Size of
        0 -> {unicode:characters_to_binary([16#25CC | Safe]), 1};
        _ when Size > Width -> {<<16#FFFD/utf8>>, 1};
        _ -> {unicode:characters_to_binary(Safe), Size}
    end.

safe_char(C) when C < 32; C >= 16#7F, C =< 16#9F -> 16#FFFD;
safe_char(C) when C =:= 16#200E; C =:= 16#200F;
                  C >= 16#202A, C =< 16#202E;
                  C >= 16#2066, C =< 16#2069 -> 16#FFFD;
safe_char(C) -> C.

grapheme_width(Chars) ->
    Width = nit_unicode:display_width(Chars),
    %% Only emoji sequences override the codepoint widths. A joiner, VS16 or
    %% enclosing keycap after an ordinary letter does not make it wide.
    case Width =/= 2 andalso
         (regional_pair(Chars) orelse keycap(Chars) orelse emoji_sequence(Chars)) of
        true -> 2;
        false -> Width
    end.

keycap([Base, 16#FE0F, 16#20E3]) -> keycap([Base, 16#20E3]);
keycap([Base, 16#20E3]) when Base =:= $#; Base =:= $*; Base >= $0, Base =< $9 -> true;
keycap(_) -> false.

emoji_sequence([Base, _ | _] = Chars) when Base >= 16#A9 ->
    %% OTP 29's bundled PCRE2 supports these Unicode binary properties.
    %% Exclude ASCII keycap bases here: a digit plus VS16 alone stays narrow.
    %% Require complete pictographic components on both sides of each ZWJ;
    %% skin tones must follow an Emoji_Modifier_Base, including text defaults.
    Component = <<"(?:\\p{Emoji_Modifier_Base}\\x{FE0F}?\\p{Emoji_Modifier}|"
                  "\\p{Extended_Pictographic}\\x{FE0F}?)">>,
    Pattern = <<"\\A(?:\\p{Emoji}\\x{FE0F}|"
                "\\p{Emoji_Modifier_Base}\\x{FE0F}?\\p{Emoji_Modifier}|",
                Component/binary, "(?:\\x{200D}", Component/binary, ")+)\\z">>,
    re:run(Chars, Pattern, [unicode, {capture, none}]) =:= match;
emoji_sequence(_) -> false.

regional_pair([A, B]) when A >= 16#1F1E6, A =< 16#1F1FF,
                          B >= 16#1F1E6, B =< 16#1F1FF -> true;
regional_pair(_) -> false.

%%====================================================================
%% Position mapping
%%====================================================================

selection(#text_view{selection_anchor = undefined}, _Size) -> none;
selection(#text_view{selection_anchor = Anchor, cursor_pos = Cursor}, Size) ->
    A = clamp(Anchor, Size),
    C = clamp(Cursor, Size),
    case A =:= C of true -> none; false -> {min(A, C), max(A, C)} end.

selected(Index, {Start, Stop}) -> Index >= Start andalso Index < Stop;
selected(_Index, none) -> false.

line_at(Pos, #layout{lines = Lines, count = Count}) ->
    line_at(Pos, Lines, 0, Count - 1).

line_at(_Pos, _Lines, Low, Low) -> Low;
line_at(Pos, Lines, Low, High) ->
    Mid = (Low + High + 1) div 2,
    case (element(Mid + 1, Lines))#line.start =< Pos of
        true -> line_at(Pos, Lines, Mid, High);
        false -> line_at(Pos, Lines, Low, Mid - 1)
    end.

cursor_col(Pos, #line{cells = Cells, width = Width}) ->
    cursor_col(Pos, Cells, Width).

cursor_col(Pos, [#cell{index = Index, col = Col} | _], _Width) when Index >= Pos -> Col;
cursor_col(Pos, [_ | Rest], Width) -> cursor_col(Pos, Rest, Width);
cursor_col(_Pos, [], Width) -> Width.

hit_position(Col, Row, #layout{lines = Lines, count = Count}) ->
    Line = element(clamp(Row, Count - 1) + 1, Lines),
    hit_cells(Col, Line#line.cells, Line#line.stop).

hit_cells(Col, [#cell{index = Index, col = X, width = W} | _], _Stop) when Col < X + W ->
    Index;
hit_cells(Col, [_ | Rest], Stop) -> hit_cells(Col, Rest, Stop);
hit_cells(_Col, [], Stop) -> Stop.

move(left, Pos, _Layout) -> max(0, Pos - 1);
move(right, Pos, Layout) -> min(Layout#layout.size, Pos + 1);
move(Dir, Pos, Layout) ->
    Row = line_at(Pos, Layout),
    Line = element(Row + 1, Layout#layout.lines),
    case Dir of
        home -> Line#line.start;
        'end' -> Line#line.stop;
        up -> move_vertical(Pos, Row, Row - 1, Layout);
        down -> move_vertical(Pos, Row, Row + 1, Layout);
        page_up -> move_vertical(Pos, Row, Row - max(1, Layout#layout.height), Layout);
        page_down -> move_vertical(Pos, Row, Row + max(1, Layout#layout.height), Layout)
    end.

move_vertical(Pos, Row, TargetRow, Layout) ->
    Target = clamp(TargetRow, Layout#layout.count - 1),
    case Target =:= Row of
        true -> Pos;
        false ->
            Current = element(Row + 1, Layout#layout.lines),
            Col = cursor_col(Pos, Current),
            Line = element(Target + 1, Layout#layout.lines),
            Hit = hit_position(Col, Target, Layout),
            %% A soft line's end belongs to the next row. Keep vertical
            %% movement on its target row instead of getting stuck at EOF
            %% or skipping a row when landing beyond a short wrapped line.
            case Hit =:= Line#line.stop andalso not Line#line.hard andalso
                 Target < Layout#layout.count - 1 of
                true -> (lists:last(Line#line.cells))#cell.index;
                false -> Hit
            end
    end.

reveal(View, Layout) ->
    Offset = safe_offset(View#text_view.offset, Layout),
    Row = line_at(View#text_view.cursor_pos, Layout),
    H = max(1, Layout#layout.height),
    Next = if Row < Offset -> Row; Row >= Offset + H -> Row - H + 1; true -> Offset end,
    View#text_view{offset = safe_offset(Next, Layout)}.

safe_offset(Offset, Layout) ->
    clamp(Offset, max(0, Layout#layout.count - max(1, Layout#layout.height))).

clamp(Value, Max) -> min(max(0, Value), Max).

dimension(Value, Available) when is_integer(Value) -> clamp(Value, Available);
dimension(_Value, Available) -> Available.

toolbar_height(#text_view{show_toolbar = true}, H) when H > 0 -> 1;
toolbar_height(_View, _H) -> 0.

%%====================================================================
%% Rendering (only visible rows, without source/control bytes in ANSI)
%%====================================================================

render_rows(View, Bounds, Layout, Offset, Style, Range, Cursor) ->
    [begin
         RowIndex = Offset + Row,
         Line = case RowIndex < Layout#layout.count of
             true -> element(RowIndex + 1, Layout#layout.lines);
             false -> #line{start = -1, stop = -1}
         end,
         render_line(View, Line, Bounds#bounds.x, Bounds#bounds.y + Row,
                     Layout#layout.width, RowIndex, Style, Range, Cursor)
     end || Row <- lists:seq(0, Layout#layout.height - 1)].

render_line(View, Line, X, Y, Width, Row, Style, Range, Cursor) ->
    %% Clearing each row also removes stale selection and text on rebuild.
    Clear = paint(X, Y, binary:copy(<<" ">>, Width), Style),
    Cells = render_cell_runs(Line#line.cells, View, X, Y, Row, Style, Range, Cursor),
    EndSelected = Line#line.hard andalso selected(Line#line.stop, Range),
    EndCursor = Cursor =:= {Row, Line#line.stop},
    End = case (EndSelected orelse EndCursor) andalso Line#line.width < Width of
        true -> paint(X + Line#line.width, Y, <<" ">>,
                      cell_style(Line#line.stop, Row, View, Style, Range, Cursor));
        false -> []
    end,
    %% At EOF on an exactly full line there is no spare insertion cell.
    %% Highlight the final whole grapheme instead of writing past the edge.
    FullCursor = case EndCursor andalso Line#line.width =:= Width andalso Width > 0 of
        true ->
            Last = lists:last(Line#line.cells),
            LastStyle = cell_style(Last#cell.index, Row, View, Style, Range, none),
            paint(X + Last#cell.col, Y, Last#cell.text,
                  maps:merge(LastStyle, #{reverse => true, underline => true}));
        false -> []
    end,
    [Clear, Cells, End, FullCursor].

%% Contiguous cells with the same style are one terminal write run. In
%% particular, don't surround every ASCII character with cursor/style escapes.
render_cell_runs([], _View, _X, _Y, _Row, _Style, _Range, _Cursor) -> [];
render_cell_runs([Cell | Rest], View, X, Y, Row, Style, Range, Cursor) ->
    CellStyle = cell_style(Cell#cell.index, Row, View, Style, Range, Cursor),
    {Texts, Remaining} = cell_run(Rest, View, Row, Style, Range, Cursor,
                                 CellStyle, [Cell#cell.text]),
    [paint(X + Cell#cell.col, Y, Texts, CellStyle),
     render_cell_runs(Remaining, View, X, Y, Row, Style, Range, Cursor)].

cell_run([Cell | Rest] = Cells, View, Row, Style, Range, Cursor, RunStyle, Acc) ->
    case cell_style(Cell#cell.index, Row, View, Style, Range, Cursor) of
        RunStyle -> cell_run(Rest, View, Row, Style, Range, Cursor,
                             RunStyle, [Cell#cell.text | Acc]);
        _ -> {lists:reverse(Acc), Cells}
    end;
cell_run([], _View, _Row, _Style, _Range, _Cursor, _RunStyle, Acc) ->
    {lists:reverse(Acc), []}.

cell_style(Index, Row, View, Style, Range, Cursor) ->
    Selected = case selected(Index, Range) of
        true -> maps:merge(Style, View#text_view.selection_style);
        false -> Style
    end,
    case Cursor =:= {Row, Index} of
        true -> maps:merge(Selected, #{reverse => true, underline => true});
        false -> Selected
    end.

paint(X, Y, Text, Style) ->
    [nit_ansi:move_to(Y, X), nit_ansi:reset_style(),
     nit_ansi:style_to_ansi(Style), Text, nit_ansi:reset_style()].

render_bar(_Bounds, #layout{bar = false}, _Offset, _Style) -> [];
render_bar(Bounds, #layout{height = H, count = Total}, Offset, Style) ->
    Thumb = max(1, H * H div Total),
    Top = Offset * (H - Thumb) div (Total - H),
    BarStyle = maps:merge(Style, #{fg => gray}),
    [paint(Bounds#bounds.x + Bounds#bounds.width - 1, Bounds#bounds.y + Row,
           case Row >= Top andalso Row < Top + Thumb of
               true -> <<"█"/utf8>>;
               false -> <<"░"/utf8>>
           end, BarStyle) || Row <- lists:seq(0, H - 1)].

render_toolbar(#text_view{show_toolbar = false}, _Bounds, _Style) -> [];
render_toolbar(View, #bounds{x = X, y = Y, width = W, height = H}, Style) ->
    Labels = [[Label, <<" ">>] || {_Start, Label, _Action} <- toolbar_labels(W)],
    Text = nit_unicode:truncate([Labels, status(View#text_view.copy_status),
                                 <<"Ctrl-A all, Shift-arrows select">>], W),
    Padding = binary:copy(<<" ">>, max(0, W - nit_unicode:display_width(Text))),
    paint(X, Y + H - 1, [Text, Padding], maps:merge(Style, #{dim => true})).

toolbar_labels(Width) ->
    Copy = <<"[y Copy]">>,
    Labels = [{0, Copy, selection}, {byte_size(Copy) + 1, <<"[Y Copy all]">>, all}],
    [Label || {Start, Text, _Action} = Label <- Labels, Start + byte_size(Text) =< Width].

status(idle) -> <<>>;
status({ok, sent}) -> <<"Sent to terminal (clipboard unverified) | ">>;
status({error, disabled}) -> <<"Clipboard disabled | ">>;
status({error, too_large}) -> <<"Too large; select less | ">>;
status({error, invalid_text}) -> <<"Invalid UTF-8 text | ">>;
status({error, unavailable}) -> <<"Clipboard unavailable | ">>;
status({error, write_failed}) -> <<"Terminal write failed | ">>;
status({error, no_selection}) -> <<"No selection | ">>;
status(_) -> <<>>.