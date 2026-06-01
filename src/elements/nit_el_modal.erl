%%%-------------------------------------------------------------------
%%% @doc NitUI Modal Element
%%%
%%% Renders a centered overlay modal with border and title.
%%% @end
%%%-------------------------------------------------------------------
-module(nit_el_modal).

-behaviour(nit_element).

-include("nit_elements.hrl").

-export([render/3, height/2, width/2, fixed_width/1]).

%%====================================================================
%% nit_element callbacks
%%====================================================================

-spec render(#modal{}, #bounds{}, map()) -> iolist().
render(#modal{visible = false}, _Bounds, _Opts) ->
    [];
render(#modal{title = Title, children = Children, border = Border,
              style = Style, width = W, height = H}, Bounds, Opts) ->
    FocusedChild = maps:get(focused_child, Opts, undefined),
    
    %% Calculate modal size
    Width = case W of
        auto -> min(60, Bounds#bounds.width - 4);
        fill -> min(60, Bounds#bounds.width - 4);
        _ -> min(W, Bounds#bounds.width - 2)
    end,
    Height = case H of
        auto -> min(10, Bounds#bounds.height - 4);
        fill -> min(10, Bounds#bounds.height - 4);
        _ -> min(H, Bounds#bounds.height - 2)
    end,
    
    %% Center the modal
    ModalX = (Bounds#bounds.width - Width) div 2,
    ModalY = (Bounds#bounds.height - Height) div 2,
    
    {TL, TR, BL, BR, HZ, VT} = nit_ansi:border_chars(Border),
    ChildBounds = #bounds{x = ModalX + 1, y = ModalY + 1,
                          width = max(1, Width - 2), height = max(1, Height - 2)},
    
    %% Draw modal box (background dimming is handled by caller)
    ModalBox = [
        nit_ansi:reset_style(),  %% Reset any dim styling from background
        nit_ansi:style_to_ansi(Style),
        nit_ansi:move_to(ModalY + 1, ModalX + 1),
        TL, nit_ansi:render_title_line(Title, HZ, Width - 2), TR,
        [[nit_ansi:move_to(ModalY + 1 + Row, ModalX + 1),
          VT, lists:duplicate(Width - 2, $\s), VT]
         || Row <- lists:seq(1, Height - 2)],
        nit_ansi:move_to(ModalY + Height, ModalX + 1),
        BL, nit_ansi:repeat_bin(HZ, Width - 2), BR,
        nit_ansi:reset_style()
    ],
    
    %% Render children inside modal - check if each child is focused
    ChildOutput = lists:map(
        fun(Child) ->
            ChildId = get_element_id(Child),
            ChildFocused = ChildId =:= FocusedChild,
            nit_element:render(Child, ChildBounds, Opts#{focused => ChildFocused})
        end, Children),
    
    [ModalBox, ChildOutput].

-spec height(#modal{}, #bounds{}) -> pos_integer().
height(#modal{height = H}, Bounds) ->
    case H of
        auto -> min(10, Bounds#bounds.height - 4);
        fill -> min(10, Bounds#bounds.height - 4);
        _ -> min(H, Bounds#bounds.height - 2)
    end.

-spec width(#modal{}, #bounds{}) -> pos_integer().
width(#modal{width = W}, Bounds) ->
    case W of
        auto -> min(60, Bounds#bounds.width - 4);
        fill -> min(60, Bounds#bounds.width - 4);
        _ -> min(W, Bounds#bounds.width - 2)
    end.

-spec fixed_width(#modal{}) -> auto | pos_integer().
fixed_width(#modal{width = auto}) -> auto;
fixed_width(#modal{width = fill}) -> auto;
fixed_width(#modal{width = W}) -> W.

%%====================================================================
%% Internal
%%====================================================================

get_element_id(Element) when is_tuple(Element), tuple_size(Element) >= 2 ->
    %% The id field is typically at position 2 in element records
    element(2, Element);
get_element_id(_) ->
    undefined.

