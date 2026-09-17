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
    AvailableWidth = Bounds#bounds.width - X,
    AvailableHeight = Bounds#bounds.height - Y,
    Width = max(0, min(nit_ansi:resolve_size(W, AvailableWidth), AvailableWidth)),
    Height = max(0, min(nit_ansi:resolve_size(H, AvailableHeight), AvailableHeight)),
    
    %% Render tab bar
    TabBar = render_tab_bar(TabList, ActiveTab, ActualX, ActualY, Width, Height, MergedStyle, Focused),
    
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
    ContentOutput = case Width > 0 andalso Height >= 3 of
        true -> [nit_element:render(C, ContentBounds, ChildOpts) || C <- ActiveContent];
        false -> []
    end,
    
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

render_tab_bar(_Tabs, _ActiveTab, _X, _Y, Width, Height, _Style, _Focused)
  when Width =< 0; Height =< 0 ->
    [];
render_tab_bar(Tabs, ActiveTab, X, Y, Width, Height, Style, Focused) ->
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
            PaddedLabel = iolist_to_binary([<<" ">>, LabelBin, <<" ">>]),
            VisibleLabel = nit_ansi:truncate_content(PaddedLabel, X + Width - CurrentX),
            TabOutput = case VisibleLabel of
                <<>> -> [];
                _ -> [nit_ansi:move_to(Y, CurrentX), nit_ansi:style_to_ansi(TabStyle),
                      VisibleLabel, nit_ansi:reset_style()]
            end,
            Separator = if
                CurrentX + LabelLen + 2 < X + Width - 1 ->
                    [nit_ansi:style_to_ansi(Style), <<"│"/utf8>>, nit_ansi:reset_style()];
                true -> []
            end,
            {[Acc, TabOutput, Separator], CurrentX + LabelLen + 3}
        end,
        {[], X}, Tabs),
    %% A one-row tab bar must not underline (or clear) the following row.
    Underline = case Height >= 2 of
        true -> [nit_ansi:move_to(Y + 1, X), nit_ansi:style_to_ansi(Style),
                 nit_ansi:repeat_bin(<<"─"/utf8>>, Width), nit_ansi:reset_style()];
        false -> []
    end,
    [TabLabels, Underline].
