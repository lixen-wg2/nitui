%%%-------------------------------------------------------------------
%%% @doc NitUI Element Behaviour
%%%
%%% Defines the callbacks that element modules must implement.
%%% Each element type (text, box, button, etc.) has its own module
%%% that implements this behaviour.
%%%
%%% This allows users to create custom elements by implementing
%%% this behaviour in their own modules.
%%% @end
%%%-------------------------------------------------------------------
-module(iso_element).

-include("iso_elements.hrl").

%% Callback definitions
-callback render(Element :: tuple(), Bounds :: #bounds{}, Opts :: map()) -> iolist().
%% Render the element to ANSI escape sequences.
%% Opts may contain:
%%   - focused => boolean() - whether this element has focus
%%   - focused_child => term() - ID of focused child (for containers)
%%   - base_style => map() - style to merge with element style (e.g., for dimming)

-callback height(Element :: tuple(), Bounds :: #bounds{}) -> pos_integer() | {flex, non_neg_integer()}.
%% Calculate the height of the element given available bounds.
%% Returns pos_integer() for fixed heights, or {flex, MinHeight} for flexible elements.

-callback width(Element :: tuple(), Bounds :: #bounds{}) -> pos_integer().
%% Calculate the width of the element given available bounds.

-callback fixed_width(Element :: tuple()) -> auto | pos_integer().
%% Returns the fixed width of an element, or 'auto' if it should fill remaining space.
%% Used by hbox layout to distribute space among children.

%% API for dispatching to element modules
-export([render/3, height/2, width/2, fixed_width/1]).
-export([children/1]).

%%====================================================================
%% API
%%====================================================================

%% @doc Get the module for an element type
-spec element_module(atom()) -> module().
element_module(text) -> iso_el_text;
element_module(box) -> iso_el_box;
element_module(panel) -> iso_el_panel;
element_module(vbox) -> iso_el_vbox;
element_module(hbox) -> iso_el_hbox;
element_module(button) -> iso_el_button;
element_module(input) -> iso_el_input;
element_module(table) -> iso_el_table;
element_module(tabs) -> iso_el_tabs;
element_module(modal) -> iso_el_modal;
element_module(tab) -> iso_el_tab;
element_module(table_col) -> iso_el_table_col;
%% Observer-style elements
element_module(progress_bar) -> iso_el_progress_bar;
element_module(sparkline) -> iso_el_sparkline;
element_module(stat_row) -> iso_el_stat_row;
element_module(status_bar) -> iso_el_status_bar;
element_module(header) -> iso_el_header;
element_module(tree) -> iso_el_tree;
element_module(tree_node) -> iso_el_tree;  %% tree_node is handled by tree
element_module(spacer) -> iso_el_spacer;
element_module(scroll) -> iso_el_scroll;
element_module(list) -> iso_el_list;
element_module(_Unknown) -> undefined.

%% @doc Render an element by dispatching to its module
-spec render(tuple(), #bounds{}, map()) -> iolist().
render(Element, Bounds, Opts) when is_tuple(Element) ->
    Type = element(1, Element),
    case element_module(Type) of
        undefined -> [];
        Mod -> Mod:render(Element, Bounds, Opts)
    end;
render(_, _, _) -> [].

%% @doc Get element height by dispatching to its module.
%% Returns pos_integer() for fixed heights, or {flex, MinHeight} for flexible elements.
-spec height(tuple(), #bounds{}) -> pos_integer() | {flex, non_neg_integer()}.
height(Element, Bounds) when is_tuple(Element) ->
    Type = element(1, Element),
    case element_module(Type) of
        undefined -> 1;
        Mod -> Mod:height(Element, Bounds)
    end;
height(_, _) -> 1.

%% @doc Get element width by dispatching to its module
-spec width(tuple(), #bounds{}) -> pos_integer().
width(Element, Bounds) when is_tuple(Element) ->
    Type = element(1, Element),
    case element_module(Type) of
        undefined -> 1;
        Mod -> Mod:width(Element, Bounds)
    end;
width(_, _) -> 1.

%% @doc Get fixed width by dispatching to its module
-spec fixed_width(tuple()) -> auto | pos_integer().
fixed_width(Element) when is_tuple(Element) ->
    Type = element(1, Element),
    case element_module(Type) of
        undefined -> auto;
        Mod -> Mod:fixed_width(Element)
    end;
fixed_width(_) -> auto.


%% @doc Get the direct children of a container element.
%% Returns the children list, or [] for leaf elements.
%% For tabs, returns only the active tab's content.
-spec children(term()) -> [term()].
children(#box{children = C}) -> C;
children(#vbox{children = C}) -> C;
children(#hbox{children = C}) -> C;
children(#panel{children = C}) -> C;
children(#scroll{children = C}) -> C;
children(#modal{children = C}) -> C;
children(#tabs{tabs = TabList, active_tab = ActiveTab0}) ->
    ActiveTab = case ActiveTab0 of
        undefined -> case TabList of [#tab{id = F} | _] -> F; [] -> undefined end;
        _ -> ActiveTab0
    end,
    case lists:keyfind(ActiveTab, #tab.id, TabList) of
        #tab{content = Content} -> Content;
        false -> []
    end;
children(_) -> [].