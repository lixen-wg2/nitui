%%%-------------------------------------------------------------------
%%% @doc NitUI Spacer Element
%%%
%%% A flexible spacer that fills remaining vertical space in a vbox.
%%% Use this to push elements (like status_bar) to the bottom of the screen.
%%%
%%% Example:
%%%   #vbox{children = [
%%%       #header{...},
%%%       #text{...},
%%%       #spacer{},           %% Fills remaining space
%%%       #status_bar{...}     %% Now at the bottom
%%%   ]}
%%% @end
%%%-------------------------------------------------------------------
-module(nit_el_spacer).

-behaviour(nit_element).

-include("nit_elements.hrl").

-export([render/3, height/2, width/2, fixed_width/1]).

%%====================================================================
%% nit_element callbacks
%%====================================================================

-spec render(#spacer{}, #bounds{}, map()) -> iolist().
render(#spacer{visible = false}, _Bounds, _Opts) ->
    [];
render(#spacer{}, _Bounds, _Opts) ->
    %% Spacer renders nothing - it just takes up space
    [].

-spec height(#spacer{}, #bounds{}) -> pos_integer() | {flex, non_neg_integer()}.
height(#spacer{height = auto, min_height = Min}, _Bounds) ->
    %% Return {flex, MinHeight} to signal vbox this element should expand
    {flex, Min};
height(#spacer{height = H}, _Bounds) when is_integer(H) ->
    H.

-spec width(#spacer{}, #bounds{}) -> pos_integer().
width(#spacer{}, Bounds) ->
    Bounds#bounds.width.

-spec fixed_width(#spacer{}) -> auto.
fixed_width(#spacer{}) ->
    auto.

