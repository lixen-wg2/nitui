%%%-------------------------------------------------------------------
%%% @doc NitUI Text Element
%%%
%%% Renders a simple text string.
%%% @end
%%%-------------------------------------------------------------------
-module(nit_el_text).

-behaviour(nit_element).

-include("nit_elements.hrl").

-export([render/3, height/2, width/2, fixed_width/1]).

%%====================================================================
%% nit_element callbacks
%%====================================================================

-spec render(#text{}, #bounds{}, map()) -> iolist().
render(#text{visible = false}, _Bounds, _Opts) ->
    [];
render(#text{content = Content, style = Style, x = X, y = Y} = Text, Bounds, Opts) ->
    ActualX = Bounds#bounds.x + X,
    ActualY = Bounds#bounds.y + Y,
    MaxWidth = text_width(Text, Bounds),
    MaxHeight = max(0, Bounds#bounds.height - Y),
    BaseStyle = maps:get(base_style, Opts, #{}),
    MergedStyle = maps:merge(Style, BaseStyle),
    Lines = lists:sublist(text_lines(Content, MaxWidth, Text#text.wrap), MaxHeight),
    render_lines(Lines, ActualX, ActualY, MergedStyle, 0, []).

-spec height(#text{}, #bounds{}) -> pos_integer() | {flex, non_neg_integer()}.
height(#text{height = fill}, _Bounds) ->
    {flex, 1};
height(#text{height = H}, _Bounds) when is_integer(H) ->
    H;
height(#text{wrap = true, content = Content} = Text, Bounds) ->
    max(1, length(text_lines(Content, text_width(Text, Bounds), true)));
height(#text{}, _Bounds) ->
    1.

-spec width(#text{}, #bounds{}) -> pos_integer().
width(#text{width = auto, wrap = true}, Bounds) -> Bounds#bounds.width;
width(#text{width = auto, content = C}, _Bounds) ->
    string:length(unicode:characters_to_list(iolist_to_binary([C])));
width(#text{width = fill}, Bounds) -> Bounds#bounds.width;
width(#text{width = W}, _Bounds) -> W.

%% Wrapped auto-width text takes the available parent width.
-spec fixed_width(#text{}) -> auto | pos_integer().
fixed_width(#text{width = auto, wrap = true}) -> auto;
fixed_width(#text{width = auto, content = C}) ->
    string:length(unicode:characters_to_list(iolist_to_binary([C])));
fixed_width(#text{width = fill}) -> auto;
fixed_width(#text{width = W}) -> W.

text_width(#text{width = Width, x = X}, Bounds) ->
    Available = max(0, Bounds#bounds.width - X),
    case Width of
        auto -> Available;
        fill -> Available;
        W when is_integer(W) -> max(0, min(W, Available))
    end.

text_lines(_Content, MaxWidth, _Wrap) when MaxWidth =< 0 ->
    [];
text_lines(Content, MaxWidth, false) ->
    [nit_ansi:truncate_content(Content, MaxWidth)];
text_lines(Content, MaxWidth, true) ->
    wrap_content(Content, MaxWidth).

render_lines([], _X, _Y, _Style, _LineIdx, Acc) ->
    lists:reverse(Acc);
render_lines([Line | Rest], X, Y, Style, LineIdx, Acc) ->
    Output = [
        nit_ansi:move_to(Y + LineIdx + 1, X + 1),
        nit_ansi:style_to_ansi(Style),
        Line,
        nit_ansi:reset_style()
    ],
    render_lines(Rest, X, Y, Style, LineIdx + 1, [Output | Acc]).

wrap_content(Content, MaxWidth) ->
    Paragraphs = split_lines(nit_unicode:to_charlist([Content])),
    lists:append([wrap_chars(Paragraph, MaxWidth) || Paragraph <- Paragraphs]).

split_lines(Chars) ->
    split_lines(Chars, [], []).

split_lines([], Current, Acc) ->
    lists:reverse([lists:reverse(Current) | Acc]);
split_lines([$\n | Rest], Current, Acc) ->
    split_lines(Rest, [], [lists:reverse(Current) | Acc]);
split_lines([Char | Rest], Current, Acc) ->
    split_lines(Rest, [Char | Current], Acc).

wrap_chars([], _MaxWidth) ->
    [<<>>];
wrap_chars(Chars, MaxWidth) ->
    wrap_chars(Chars, MaxWidth, [], 0, []).

wrap_chars([], _MaxWidth, [], _LineWidth, Acc) ->
    lists:reverse(Acc);
wrap_chars([], _MaxWidth, Current, _LineWidth, Acc) ->
    lists:reverse([unicode:characters_to_binary(lists:reverse(Current)) | Acc]);
wrap_chars([Char | Rest], MaxWidth, Current, LineWidth, Acc) ->
    CharWidth = nit_unicode:display_width([Char]),
    case LineWidth =:= 0 orelse LineWidth + CharWidth =< MaxWidth of
        true ->
            wrap_chars(Rest, MaxWidth, [Char | Current], LineWidth + CharWidth, Acc);
        false ->
            Line = unicode:characters_to_binary(lists:reverse(Current)),
            wrap_chars([Char | Rest], MaxWidth, [], 0, [Line | Acc])
    end.
