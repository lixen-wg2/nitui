%%%-------------------------------------------------------------------
%%% @doc NitUI TUI Framework - Main API module.
%%%
%%% NitUI is a Nitrogen-inspired terminal UI framework for Erlang.
%%% This module provides the public API for starting and interacting
%%% with TUI applications.
%%% @end
%%%-------------------------------------------------------------------
-module(nitui).

-include("iso_elements.hrl").

%% API
-export([start/0, stop/0]).
-export([selected_item/1, selected_item/2, selected_item/3]).

%%--------------------------------------------------------------------
%% @doc Start the NitUI TUI application.
%% @end
%%--------------------------------------------------------------------
-spec start() -> ok | {error, term()}.
start() ->
    case application:ensure_all_started(nitui) of
        {ok, _} -> ok;
        {error, _} = Error -> Error
    end.

%%--------------------------------------------------------------------
%% @doc Stop the NitUI TUI application.
%% @end
%%--------------------------------------------------------------------
-spec stop() -> ok | {error, term()}.
stop() ->
    application:stop(nitui).

%%--------------------------------------------------------------------
%% @doc Return the selected item for a list element in the current view
%% context. The id may point directly to a list or to a container that
%% contains a list.
%% @end
%%--------------------------------------------------------------------
-spec selected_item(term()) -> term() | undefined.
selected_item(ElementId) ->
    case erlang:get(nitui_view_tree) of
        undefined -> undefined;
        Tree -> selected_item_from_tree(Tree, ElementId)
    end.

%%--------------------------------------------------------------------
%% @doc Return the selected item from a zero-based list selection.
%% Falls back to the first item when the selection is out of range.
%% @end
%%--------------------------------------------------------------------
-spec selected_item([Item], non_neg_integer()) -> Item | undefined.
selected_item(Items, SelectedIdx) ->
    case iso_engine:list_selected_item(Items, SelectedIdx) of
        undefined ->
            case Items of
                [First | _] -> First;
                [] -> undefined
            end;
        Item ->
            Item
    end.

%%--------------------------------------------------------------------
%% @doc Return the selected item, the first item for an invalid selection,
%% or Default for an empty list.
%% @end
%%--------------------------------------------------------------------
-spec selected_item([Item], non_neg_integer(), Default) -> Item | Default.
selected_item(Items, SelectedIdx, Default) ->
    case selected_item(Items, SelectedIdx) of
        undefined -> Default;
        Item ->
            Item
    end.

selected_item_from_tree(Tree, ElementId) ->
    case iso_focus:find_element(Tree, ElementId) of
        undefined -> undefined;
        Element -> selected_item_from_element(Element)
    end.

selected_item_from_element(#list{items = Items, selected = SelectedIdx}) ->
    selected_item(Items, SelectedIdx);
selected_item_from_element(Element) ->
    selected_item_from_children(iso_element:children(Element)).

selected_item_from_children([]) ->
    undefined;
selected_item_from_children([Child | Rest]) ->
    case selected_item_from_element(Child) of
        undefined -> selected_item_from_children(Rest);
        Item -> Item
    end.
