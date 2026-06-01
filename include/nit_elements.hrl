%%%-------------------------------------------------------------------
%%% @doc NitUI Element Definitions
%%%
%%% All UI elements are records with a common base set of fields.
%%% Elements are rendered by calling Module:render(Element, Bounds).
%%%
%%% Inspired by Nitrogen/Nitro's element system.
%%% @end
%%%-------------------------------------------------------------------

-ifndef(NIT_ELEMENTS_HRL).
-define(NIT_ELEMENTS_HRL, true).

%%====================================================================
%% Base Element Fields
%%====================================================================

%% Common fields for all elements - use this macro in element records
-define(ELEMENT_BASE,
    id = undefined :: term(),           %% Unique identifier
    x = 0 :: non_neg_integer(),         %% X position (column, 0-based)
    y = 0 :: non_neg_integer(),         %% Y position (row, 0-based)
    width = auto :: auto | pos_integer(),   %% Width (auto = fit content)
    height = auto :: auto | fill | pos_integer(),  %% Height (auto = fit content, fill = flex)
    style = #{} :: map(),               %% Style properties (fg, bg, bold, etc.)
    visible = true :: boolean(),        %% Whether to render
    focusable = false :: boolean(),     %% Can receive focus
    %% Lifecycle hooks
    on_mount = undefined :: undefined | fun((Element :: tuple()) -> ok),
    on_unmount = undefined :: undefined | fun((Element :: tuple()) -> ok)
).

%%====================================================================
%% Bounds Record
%%====================================================================

%% Bounds passed to render functions - defines available space
-record(bounds, {
    x = 0 :: non_neg_integer(),
    y = 0 :: non_neg_integer(),
    width = 80 :: pos_integer(),
    height = 24 :: pos_integer()
}).

%%====================================================================
%% Basic Elements
%%====================================================================

%% Text element - displays a string
-record(text, {
    ?ELEMENT_BASE,
    content = <<>> :: binary() | string(),
    wrap = false :: boolean()
}).

%% Box element - container with optional border
-record(box, {
    ?ELEMENT_BASE,
    border = none :: none | single | double | rounded,
    title = undefined :: undefined | binary() | string(),
    children = [] :: [tuple()]  %% Child elements
}).

%% Panel element - simple container without border
-record(panel, {
    ?ELEMENT_BASE,
    children = [] :: [tuple()]
}).

%% Horizontal box - lays out children horizontally
-record(hbox, {
    ?ELEMENT_BASE,
    spacing = 0 :: non_neg_integer(),
    children = [] :: [tuple()]
}).

%% Vertical box - lays out children vertically
-record(vbox, {
    ?ELEMENT_BASE,
    spacing = 0 :: non_neg_integer(),
    children = [] :: [tuple()]
}).

%%====================================================================
%% Interactive Elements
%%====================================================================

%% Button element - clickable, triggers event on Enter/Space
-record(button, {
    ?ELEMENT_BASE,
    label = <<>> :: binary() | string(),
    on_click = undefined :: undefined | {atom(), atom()} | fun()  %% {Module, Function} or fun()
}).

%% Input element - text input field
-record(input, {
    ?ELEMENT_BASE,
    value = <<>> :: binary() | string(),
    placeholder = <<>> :: binary() | string(),
    cursor_pos = 0 :: non_neg_integer(),
    selection_anchor = undefined :: undefined | non_neg_integer(),
    on_change = undefined :: undefined | {atom(), atom()} | fun(),
    on_submit = undefined :: undefined | {atom(), atom()} | fun()
}).

%% Modal element - overlay that appears on top of everything
-record(modal, {
    ?ELEMENT_BASE,
    title = <<>> :: binary() | string(),
    children = [] :: [tuple()],
    border = double :: none | single | double | rounded
}).

%%====================================================================
%% Widget Elements
%%====================================================================

%% Table column definition
-record(table_col, {
    id :: term(),                          %% Column identifier
    header = <<>> :: binary() | string(),  %% Column header text
    width = auto :: auto | pos_integer(),  %% Column width
    align = left :: left | center | right  %% Text alignment
}).

%% Table element - displays tabular data with optional selection
%% Supports two modes:
%% 1. Static mode: rows contains all data (default)
%% 2. Virtual scrolling mode: row_provider fetches rows on demand
-record(table, {
    ?ELEMENT_BASE,
    columns = [] :: [#table_col{}],        %% Column definitions
    rows = [] :: [[term()]],               %% Row data (list of lists) - used in static mode
    selected_row = 0 :: non_neg_integer(), %% Currently selected row (0 = none, 1-based)
    scroll_offset = 0 :: non_neg_integer(),%% Vertical scroll offset
    activate_on_reclick = false :: boolean(), %% Re-click selected row to activate it
    sortable = false :: boolean(),         %% Clickable headers auto-sort static rows
    sort_by = undefined :: undefined | term(), %% Currently sorted column ID
    sort_dir = asc :: asc | desc,          %% Current sort direction
    border = none :: none | single | double,  %% Default to no border
    show_header = true :: boolean(),       %% Show column headers
    zebra = true :: boolean(),             %% Alternate row colors (default on)
    on_select = undefined :: undefined | {atom(), atom()} | fun(),
    %% Virtual scrolling fields
    total_rows = undefined :: undefined | non_neg_integer(),  %% Total row count (for virtual scrolling)
    row_provider = undefined :: undefined | fun((StartIdx :: non_neg_integer(), Count :: pos_integer()) -> [[term()]])
    %% row_provider is called with 0-based start index and count, returns list of rows
}).

%% Tab definition for tabs widget
-record(tab, {
    id :: term(),                          %% Tab identifier
    label = <<>> :: binary() | string(),   %% Tab label text
    content = [] :: [tuple()]              %% Tab content (list of elements)
}).

%% Tabs element - tabbed container for switching between views
-record(tabs, {
    ?ELEMENT_BASE,
    tabs = [] :: [#tab{}],                 %% List of tab definitions
    active_tab = undefined :: term(),      %% ID of currently active tab
    tab_style = top :: top | bottom,       %% Tab bar position
    on_change = undefined :: undefined | {atom(), atom()} | fun()
}).

%%====================================================================
%% Observer-style Elements
%%====================================================================

%% Progress bar / gauge - shows value/max with visual bar
-record(progress_bar, {
    ?ELEMENT_BASE,
    value = 0 :: number(),                 %% Current value
    max = 100 :: number(),                 %% Maximum value
    show_percent = true :: boolean(),      %% Show percentage text
    show_value = false :: boolean(),       %% Show value/max text
    bar_char = $# :: char(),               %% Character for filled portion
    empty_char = $- :: char(),             %% Character for empty portion
    color = auto :: auto | atom(),         %% Bar color (auto = threshold-based)
    threshold_warn = 0.70 :: float(),      %% Yellow threshold (0.0-1.0)
    threshold_crit = 0.85 :: float()       %% Red threshold (0.0-1.0)
}).

%% Sparkline - mini chart showing trend over time
-record(sparkline, {
    ?ELEMENT_BASE,
    values = [] :: [number()],             %% List of values (newest last)
    min_val = auto :: auto | number(),     %% Minimum value for scaling
    max_val = auto :: auto | number(),     %% Maximum value for scaling
    style_type = braille :: braille | block | ascii,  %% Rendering style
    color = cyan :: atom()                 %% Line color
}).

%% Stat row - horizontal row of key-value pairs
-record(stat_row, {
    ?ELEMENT_BASE,
    items = [] :: [{Label :: binary(), Value :: binary()}],
    separator = <<" | ">> :: binary(),     %% Separator between items
    label_style = #{} :: map(),            %% Style for labels
    value_style = #{bold => true} :: map() %% Style for values
}).

%% Status bar - bottom bar with keyboard shortcuts
-record(status_bar, {
    ?ELEMENT_BASE,
    items = [] :: [{Key :: binary(), Label :: binary()}],
    separator = <<" ">> :: binary(),       %% Separator between items
    key_style = #{bold => true, fg => cyan} :: map(),
    label_style = #{} :: map()
}).

%% Spacer - fills remaining vertical space in a vbox
%% Use this to push elements (like status_bar) to the bottom
-record(spacer, {
    ?ELEMENT_BASE,
    min_height = 0 :: non_neg_integer()   %% Minimum height (0 = fully flexible)
}).

%% Header bar - top bar with title and info
-record(header, {
    ?ELEMENT_BASE,
    title = <<>> :: binary(),              %% Main title
    subtitle = <<>> :: binary(),           %% Subtitle (e.g., node name)
    items = [] :: [{Label :: binary(), Value :: binary()}],  %% Right-side items
    bg_color = blue :: atom(),             %% Background color
    fg_color = white :: atom()             %% Foreground color
}).

%% Tree node for tree view
-record(tree_node, {
    id :: term(),                          %% Node identifier
    label = <<>> :: binary() | string(),   %% Node label
    children = [] :: [#tree_node{}],       %% Child nodes
    expanded = true :: boolean(),          %% Whether children are visible
    icon = undefined :: undefined | binary() | string()  %% Optional icon/prefix
}).

%% Tree view - hierarchical tree display
-record(tree, {
    ?ELEMENT_BASE,
    nodes = [] :: [#tree_node{}],          %% Root nodes
    selected = undefined :: term(),        %% Selected node ID
    offset = 0 :: non_neg_integer(),       %% Scroll offset for clipped trees
    indent = 2 :: pos_integer(),           %% Indentation per level
    show_lines = true :: boolean(),        %% Show tree lines (├─, └─, │)
    on_select = undefined :: undefined | {atom(), atom()} | fun()
}).

%% Scroll container - scrollable viewport for content
-record(scroll, {
    ?ELEMENT_BASE,
    children = [] :: [tuple()],            %% Child elements to scroll
    offset = 0 :: non_neg_integer(),       %% Current scroll offset (lines from top)
    show_scrollbar = true :: boolean()     %% Show scrollbar indicator
}).

%% List - selectable list of items
-record(list, {
    ?ELEMENT_BASE,
    items = [] :: [binary() | {term(), binary()}],  %% Items: binary or {Id, Label}
    selected = 0 :: non_neg_integer(),     %% Selected index (0-based)
    offset = 0 :: non_neg_integer(),       %% Scroll offset for long lists
    item_style = #{} :: map(),             %% Style for normal items
    selected_style = #{bg => blue, fg => white} :: map(),  %% Style for selected item
    on_select = undefined :: undefined | {atom(), atom()} | fun()
}).

%%====================================================================
%% Style Helpers
%%====================================================================

%% Foreground colors
-define(FG_BLACK, #{fg => black}).
-define(FG_RED, #{fg => red}).
-define(FG_GREEN, #{fg => green}).
-define(FG_YELLOW, #{fg => yellow}).
-define(FG_BLUE, #{fg => blue}).
-define(FG_MAGENTA, #{fg => magenta}).
-define(FG_CYAN, #{fg => cyan}).
-define(FG_WHITE, #{fg => white}).

%% Background colors
-define(BG_BLACK, #{bg => black}).
-define(BG_RED, #{bg => red}).
-define(BG_GREEN, #{bg => green}).
-define(BG_YELLOW, #{bg => yellow}).
-define(BG_BLUE, #{bg => blue}).
-define(BG_MAGENTA, #{bg => magenta}).
-define(BG_CYAN, #{bg => cyan}).
-define(BG_WHITE, #{bg => white}).

%% Text styles
-define(BOLD, #{bold => true}).
-define(DIM, #{dim => true}).
-define(ITALIC, #{italic => true}).
-define(UNDERLINE, #{underline => true}).

-endif. %% NIT_ELEMENTS_HRL
