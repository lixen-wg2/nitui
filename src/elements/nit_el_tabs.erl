%%%-------------------------------------------------------------------
%%% @doc NitUI Tabs Element
%%%
%%% Renders a tabbed container with tab bar and content area.
%%% @end
%%%-------------------------------------------------------------------
-module(nit_el_tabs).

-behaviour(nit_element).

-include("nit_elements.hrl").

-export([render/3, height/2, width/2, fixed_width/1]).

%%====================================================================
%% nit_element callbacks
%%====================================================================

-spec render(#tabs{}, #bounds{}, map()) -> iolist().
render(#tabs{visible = false}, _Bounds, _Opts) ->
    [];
render(#tabs{tabs = TabList, active_tab = ActiveTab0, style = Style,
             x = X, y = Y, width = W, height = H}, Bounds, Opts) ->
    Focused = maps:get(focused, Opts, false),
    FocusedChild = maps:get(focused_child, Opts, undefined),
    BaseStyle = maps:get(base_style, Opts, #{}),
    MergedStyle = maps:merge(Style, BaseStyle),
    
    %% Default to first tab if undefined
    ActiveTab = case ActiveTab0 of
        undefined -> 
            case TabList of 
                [#tab{id = FirstId} | _] -> FirstId; 
                [] -> undefined 
            end;
        _ -> ActiveTab0
    end,
    
    ActualX = Bounds#bounds.x + X,
    ActualY = Bounds#bounds.y + Y,
    Width = case W of
        auto -> Bounds#bounds.width - X;
        fill -> Bounds#bounds.width - X;
        _ -> W
    end,
    Height = case H of
        auto -> Bounds#bounds.height - Y;
        fill -> Bounds#bounds.height - Y;
        _ -> H
    end,
    
    %% Render tab bar
    TabBar = render_tab_bar(TabList, ActiveTab, ActualX, ActualY, Width, MergedStyle, Focused),
    
    %% Find active tab content
    ActiveContent = case lists:keyfind(ActiveTab, #tab.id, TabList) of
        #tab{content = Content} -> Content;
        false -> []
    end,
    
    %% Render content area (below tab bar)
    ContentBounds = #bounds{
        x = ActualX,
        y = ActualY + 1,
        width = Width,
        height = max(1, Height - 1)
    },
    
    %% Pass focused_child to children
    ChildOpts = Opts#{focused_child => FocusedChild},
    ContentOutput = [nit_element:render(C, ContentBounds, ChildOpts) || C <- ActiveContent],
    
    [TabBar, ContentOutput].

-spec height(#tabs{}, #bounds{}) -> pos_integer() | {flex, non_neg_integer()}.
height(#tabs{height = H}, Bounds) ->
    case H of
        auto -> Bounds#bounds.height;
        fill -> {flex, 2};
        _ -> H
    end.

-spec width(#tabs{}, #bounds{}) -> pos_integer().
width(#tabs{width = W}, Bounds) ->
    case W of
        auto -> Bounds#bounds.width;
        fill -> Bounds#bounds.width;
        _ -> W
    end.

-spec fixed_width(#tabs{}) -> auto | pos_integer().
fixed_width(#tabs{width = auto}) -> auto;
fixed_width(#tabs{width = fill}) -> auto;
fixed_width(#tabs{width = W}) -> W.

%%====================================================================
%% Internal
%%====================================================================

render_tab_bar(Tabs, ActiveTab, X, Y, Width, Style, Focused) ->
    {TabLabels, _} = lists:foldl(
        fun(#tab{id = Id, label = Label}, {Acc, CurrentX}) ->
            LabelBin = iolist_to_binary([Label]),
            LabelLen = string:length(unicode:characters_to_list(LabelBin)),
            IsActive = Id =:= ActiveTab,
            TabStyle = if
                IsActive andalso Focused ->
                    maps:merge(Style, #{bg => white, fg => black, bold => true});
                IsActive ->
                    maps:merge(Style, #{bg => cyan, fg => black});
                true ->
                    maps:merge(Style, #{dim => true})
            end,
            TabOutput = [
                nit_ansi:move_to(Y + 1, CurrentX + 1),
                nit_ansi:style_to_ansi(TabStyle),
                <<" ">>, LabelBin, <<" ">>,
                nit_ansi:reset_style()
            ],
            Separator = if
                CurrentX + LabelLen + 2 < X + Width - 1 ->
                    [nit_ansi:style_to_ansi(Style), <<"│"/utf8>>, nit_ansi:reset_style()];
                true -> []
            end,
            {[Acc, TabOutput, Separator], CurrentX + LabelLen + 3}
        end,
        {[], X}, Tabs),
    Underline = [
        nit_ansi:move_to(Y + 2, X + 1),
        nit_ansi:style_to_ansi(Style),
        nit_ansi:repeat_bin(<<"─"/utf8>>, Width),
        nit_ansi:reset_style()
    ],
    [TabLabels, Underline].
