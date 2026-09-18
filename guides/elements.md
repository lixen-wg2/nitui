# Elements

Every element is a record defined in `include/nit_elements.hrl`:

```erlang
-include_lib("nitui/include/nit_elements.hrl").
```

## Shared fields

All element records start with the same base fields.

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| `id` | `term()` | `undefined` | Required for focus, events and state merging |
| `x`, `y` | `non_neg_integer()` | `0` | Set by layout; rarely useful to write |
| `width` | `auto \| pos_integer()` | `auto` | `auto` fits content |
| `height` | `auto \| fill \| pos_integer()` | `auto` | `fill` consumes remaining space |
| `style` | `map()` | `#{}` | See [Styling](styling.html) |
| `visible` | `boolean()` | `true` | Hidden elements are skipped by layout and focus |
| `focusable` | `boolean()` | `false` | Opt-in; nothing is focusable by default |
| `on_mount` | `fun((tuple()) -> ok)` | `undefined` | Called when the element enters the tree |
| `on_unmount` | `fun((tuple()) -> ok)` | `undefined` | Called when it leaves the tree |

`#bounds{x, y, width, height}` is the rectangle an element is rendered into. It
appears in element callbacks and in `nit_bounds` results, not in views.

## Containers

| Record | Purpose |
|--------|---------|
| `#vbox{spacing, children}` | Stack children vertically |
| `#hbox{spacing, children}` | Stack children horizontally |
| `#panel{children}` | Grouping container, no border |
| `#box{border, title, children, focus_within, focused_border, focused_style}` | Container with optional border and title |
| `#scroll{children, offset, show_scrollbar}` | Scrollable viewport |
| `#tabs{tabs, active_tab, tab_style, on_change}` | Tab bar plus active tab content |
| `#modal{title, children, border}` | Overlay dialog, see [Views and overlays](views-and-overlays.html) |
| `#spacer{min_height}` | Flexible vertical gap; pushes later children down |

`border` accepts `none` (default for `#box{}`), `single`, `double` or
`rounded`. `#box{focus_within = true}` highlights the border while any visible
descendant holds focus, using `focused_border` and `focused_style`.

`#tabs.tabs` is a list of `#tab{id, label, content}` records where `content` is
a list of elements.

## Content

| Record | Purpose |
|--------|---------|
| `#text{content, wrap}` | Static text; `wrap = true` wraps at the allocated width |
| `#text_view{...}` | Read-only, selectable, scrollable text. See [Text and clipboard](text-and-clipboard.html) |
| `#header{title, subtitle, items, bg_color, fg_color}` | Top bar with right-aligned label/value pairs |
| `#status_bar{items, separator, key_style, label_style}` | Bottom key hint bar |
| `#stat_row{items, separator, label_style, value_style}` | One-line row of label/value pairs |
| `#progress_bar{value, max, ...}` | Gauge with optional percentage or value text |
| `#sparkline{values, min_val, max_val, style_type, color}` | Trend chart; `style_type` is `braille`, `block` or `ascii` |

`#header.items`, `#status_bar.items` and `#stat_row.items` all take
`[{Label, Value}]` pairs. `nit_format:commas/1`, `nit_format:bytes/1` and
`nit_format:duration/1` produce the usual display strings.

`#progress_bar.color = auto` picks green, yellow or red using
`threshold_warn` (0.70) and `threshold_crit` (0.85) as fractions of `max`.

## Interactive

### `#button{}`

| Field | Default | Notes |
|-------|---------|-------|
| `label` | `<<>>` | Button text |
| `on_click` | `undefined` | `{Module, Function}` or `fun()`, passed back in the event |
| `enabled` | `true` | Disabled buttons neither focus nor activate |
| `focused_style` | `#{bold => true, underline => true}` | |
| `disabled_style` | `#{fg => bright_black, dim => true}` | |

Enter or Space on a focused button, or a mouse click, emits
`{click, Id, Handler}`.

### `#input{}`

| Field | Default | Notes |
|-------|---------|-------|
| `value` | `<<>>` | Current text |
| `placeholder` | `<<>>` | Shown while empty |
| `cursor_pos` | `0` | Grapheme position |
| `selection_anchor` | `undefined` | Set by Shift+arrow selection |
| `on_change` / `on_submit` | `undefined` | Passed back in the event |

Typing emits `{input, Id, Value}`; Enter emits `{submit, Id, Value, Handler}`.

### `#list{}`

`items` is a list of binaries or `{Id, Label}` tuples; `selected` is a
**0-based** index. Arrow keys move the selection and emit
`{list_select, Id, Index, Item}`. `nitui:selected_item/1,2,3` resolves the
selected item during `view/1`.

### `#table{}`

Columns are `#table_col{id, header, width, align}`, rows are lists of terms.
See [Tables](tables.html) for sorting, virtual scrolling, clickable cells and
controlled mode.

### `#tree{}`

`nodes` is a list of `#tree_node{id, label, children, expanded, icon}`.
`selected` holds a node id. Left/right collapse and expand, up/down move,
Enter emits `{tree_activate, Id, NodeId}` and movement emits
`{tree_select, Id, NodeId}`. `selection_request = {Token, NodeId}` is a
one-shot request to select and reveal a node; change the token to repeat it.

## Element modules

Each record has a backing module in `src/elements/` (`nit_el_table`,
`nit_el_tree`, ...) implementing the `nit_element` callbacks: `render/3`,
`height/2`, `width/2` and `fixed_width/1`. Some modules export extra helpers
used by the runtime — `nit_el_table:toggle_sort/2`, `nit_el_text_view:key/3`
and `nit_el_text_view:merge/2`, for example. They are the reference for exact
rendering behaviour; applications do not call them directly.
