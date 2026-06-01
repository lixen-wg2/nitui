%%%-------------------------------------------------------------------
%%% @doc NitUI Button Element
%%%
%%% Renders a clickable button with focus indication.
%%% @end
%%%-------------------------------------------------------------------
-module(nit_el_button).

-behaviour(nit_element).

-include("nit_elements.hrl").

-export([render/3, height/2, width/2, fixed_width/1]).

%%====================================================================
%% nit_element callbacks
%%====================================================================

-spec render(#button{}, #bounds{}, map()) -> iolist().
render(#button{visible = false}, _Bounds, _Opts) ->
    [];
render(#button{label = Label, style = Style, x = X, y = Y, width = W}, Bounds, Opts) ->
    ActualX = Bounds#bounds.x + X,
    ActualY = Bounds#bounds.y + Y,
    Focused = maps:get(focused, Opts, false),
    Hovered = maps:get(hovered, Opts, false),
    BaseStyle = maps:get(base_style, Opts, #{}),
    
    LabelBin = iolist_to_binary([Label]),
    LabelLen = string:length(unicode:characters_to_list(LabelBin)),
    Width = case W of
        auto -> LabelLen + button_padding_width();
        fill -> max(LabelLen + button_padding_width(), Bounds#bounds.width - X);
        _ -> W
    end,
    
    StateStyle = button_state_style(Style, Focused, Hovered),
    MergedStyle = maps:merge(StateStyle, BaseStyle),
    
    Padding = max(0, Width - LabelLen),
    LeftPad = Padding div 2,
    RightPad = Padding - LeftPad,
    [
        nit_ansi:move_to(ActualY + 1, ActualX + 1),
        nit_ansi:style_to_ansi(MergedStyle),
        lists:duplicate(LeftPad, $\s), LabelBin, lists:duplicate(RightPad, $\s),
        nit_ansi:reset_style()
    ].

-spec height(#button{}, #bounds{}) -> pos_integer().
height(#button{}, _Bounds) -> 1.

-spec width(#button{}, #bounds{}) -> pos_integer().
width(#button{label = Label, width = W}, _Bounds) ->
    case W of
        auto ->
            LabelBin = iolist_to_binary([Label]),
            string:length(unicode:characters_to_list(LabelBin)) + button_padding_width();
        fill -> _Bounds#bounds.width;
        _ -> W
    end.

-spec fixed_width(#button{}) -> auto | pos_integer().
fixed_width(#button{width = auto, label = Label}) ->
    LabelBin = iolist_to_binary([Label]),
    string:length(unicode:characters_to_list(LabelBin)) + button_padding_width();
fixed_width(#button{width = fill}) -> auto;
fixed_width(#button{width = W}) -> W.

button_padding_width() ->
    4.

button_state_style(Style, true, _Hovered) ->
    maps:merge(Style, #{bold => true, underline => true});
button_state_style(Style, false, true) ->
    case maps:is_key(bg, Style) of
        true -> maps:merge(Style, #{bold => true, underline => true});
        false -> maps:merge(Style, #{bg => bright_black, bold => true})
    end;
button_state_style(Style, false, false) ->
    Style.
