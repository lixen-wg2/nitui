%%%-------------------------------------------------------------------
%%% @doc Status Bar Element
%%%
%%% Displays a bottom status bar with keyboard shortcuts.
%%% @end
%%%-------------------------------------------------------------------
-module(nit_el_status_bar).

-behaviour(nit_element).

-include("nit_elements.hrl").

-export([render/3, height/2, width/2, fixed_width/1, item_at/4]).

%%====================================================================
%% nit_element callbacks
%%====================================================================

render(#status_bar{visible = false}, _Bounds, _Opts) ->
    [];
render(#status_bar{items = Items, separator = Sep, x = X, y = Y,
                   key_style = KeyStyle, label_style = LabelStyle,
                   style = Style}, Bounds, Opts) ->
    ActualX = Bounds#bounds.x + X,
    ActualY = Bounds#bounds.y + Y,
    SepBin = unicode:characters_to_binary(Sep),
    
    BaseStyle = maps:get(base_style, Opts, #{}),
    MergedKeyStyle = maps:merge(maps:merge(BaseStyle, Style), KeyStyle),
    MergedLabelStyle = maps:merge(maps:merge(BaseStyle, Style), LabelStyle),
    
    %% Build output for each item: [K]Label
    ItemOutputs = lists:map(
        fun({Key, Label}) ->
            KeyBin = unicode:characters_to_binary(Key),
            LabelBin = unicode:characters_to_binary(Label),
            [
                nit_ansi:style_to_ansi(MergedKeyStyle),
                <<"[">>, KeyBin, <<"]">>,
                nit_ansi:reset_style(),
                nit_ansi:style_to_ansi(MergedLabelStyle),
                LabelBin,
                nit_ansi:reset_style()
            ]
        end,
        Items
    ),
    
    %% Join with separator
    Joined = lists:join(SepBin, ItemOutputs),
    
    %% Clear the line first (fill with spaces)
    ClearLine = list_to_binary(lists:duplicate(Bounds#bounds.width, $ )),
    
    [
        nit_ansi:move_to(ActualY, ActualX),
        nit_ansi:style_to_ansi(maps:merge(BaseStyle, Style)),
        ClearLine,
        nit_ansi:move_to(ActualY, ActualX),
        nit_ansi:reset_style(),
        Joined
    ].

height(#status_bar{}, _Bounds) -> 1.

width(#status_bar{}, Bounds) -> Bounds#bounds.width.

fixed_width(#status_bar{width = fill}) -> auto;
fixed_width(#status_bar{width = W}) -> W.

%%====================================================================
%% Hit testing helpers
%%====================================================================

-spec item_at(#status_bar{}, integer(), integer(), #bounds{}) ->
    {ok, binary() | string()} | not_found.
item_at(#status_bar{items = Items, separator = Sep, x = X, y = Y}, Col, Row, Bounds) ->
    ActualX = Bounds#bounds.x + X,
    ActualY = Bounds#bounds.y + Y,
    case Row =:= ActualY + 1 of
        false ->
            not_found;
        true ->
            find_item_at(item_spans(Items, Sep, ActualX + 1), Col)
    end.

item_spans(Items, Sep, StartCol) ->
    SepWidth = text_width(Sep),
    {Spans, _NextCol} = lists:foldl(
        fun({Key, Label}, {Acc, CurrentCol}) ->
            ItemWidth = shortcut_width(Key, Label),
            Span = {CurrentCol, CurrentCol + ItemWidth - 1, Key},
            {[Span | Acc], CurrentCol + ItemWidth + SepWidth}
        end,
        {[], StartCol},
        Items),
    lists:reverse(Spans).

find_item_at([], _Col) ->
    not_found;
find_item_at([{StartCol, EndCol, Key} | _Rest], Col) when Col >= StartCol, Col =< EndCol ->
    {ok, Key};
find_item_at([_ | Rest], Col) ->
    find_item_at(Rest, Col).

shortcut_width(Key, Label) ->
    2 + text_width(Key) + text_width(Label).

text_width(Value) ->
    nit_unicode:display_width(Value).
