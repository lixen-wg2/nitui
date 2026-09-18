# Focus and navigation

NitUI has a two-level focus model:

- **Tab / Shift+Tab** cycles between *containers*.
- **Arrow keys** move within the focused container — between its focusable
  children, or inside a widget that navigates itself.

Focus is always opt-in. An element with `focusable = false` (the default) is
invisible to both levels, and an element with `id = undefined` cannot be
focused because focus is tracked by id.

## What counts as a container

`nit_focus:collect_containers/1` walks the tree and collects the ids of these
records when `focusable = true`:

`#box{}`, `#tabs{}`, `#table{}`, `#tree{}`, `#list{}`, `#scroll{}`,
`#text_view{}`

`#vbox{}`, `#hbox{}`, `#panel{}` and `#modal{}` are always traversed for
containers inside them, but are never containers themselves. A `#scroll{}` is
traversed when it is not focusable, and is itself a container when it is.
A `#table{}`, `#list{}`, `#tree{}` or `#tabs{}` is a leaf: the traversal does
not descend into it, because it handles its own internal navigation.

## What counts as a child

Within a focused container, `nit_focus:collect_children/2` collects:

- `#button{}` with `focusable = true`, `enabled = true` and `visible = true`
- `#input{}` with `focusable = true`
- `#text_view{}` with `focusable = true` and `visible = true`
- `#table{}`, `#list{}` and `#scroll{}` with `focusable = true`

Layout records (`#vbox{}`, `#hbox{}`) are traversed for those children. A
nested `#box{}` or `#panel{}` contributes only its visible focusable
`#text_view{}` elements, so a bordered sub-box is reached by Tab rather than
by arrows.

For a `#tabs{}` container, the "children" are the tab ids themselves, so
Left/Right switches tabs and emits `{tab_change, TabsId, TabId}`.

So a typical layout is a focusable `#box{}` holding a row of focusable
buttons: Tab reaches the box, arrows move between the buttons.

## Widget-internal navigation

| Element | Arrow behaviour |
|---------|-----------------|
| `#table{}` | Up/Down move the selected row, scrolling as needed; emits `{table_select, ...}` |
| `#list{}` | Up/Down move `selected`; emits `{list_select, ...}` |
| `#tree{}` | Up/Down move between visible nodes; Left collapses, Right expands; emits `{tree_select, ...}` |
| `#scroll{}` | Up/Down move `offset` |
| `#input{}` | Left/Right move the cursor; Shift+Left/Right, Home/End and Shift+Home/End select |
| `#text_view{}` | Arrows, Home/End and Page keys move the cursor; Shift selects |

`Page Up` / `Page Down` page the focused table, list, tree or scroll container.
If nothing consumes them, they are forwarded to `handle_event/2` as
`{event, {key, page_up}}`.

`Enter` activates the focused element: a button emits `{click, Id, Handler}`,
an input emits `{submit, Id, Value, Handler}`, a table emits
`{table_activate, Id, RowIdx, RowData}`, a tree emits
`{tree_activate, Id, NodeId}`. `Space` also activates a focused enabled button.

## Visual focus feedback

- `#button.focused_style` defaults to `#{bold => true, underline => true}`.
- `#table.focused_selected_style` distinguishes the selected row of a focused
  table from a selected row in an unfocused one.
- `#box{focus_within = true}` restyles the border while any visible descendant
  holds focus, using `focused_border` and `focused_style`.

```erlang
#box{
    id = actions,
    border = single,
    title = "Actions",
    focusable = true,
    focus_within = true,
    focused_border = double,
    children = [
        #button{id = start, label = "Start", focusable = true},
        #button{id = stop,  label = "Stop",  focusable = true}
    ]
}
```

## Mouse focus

A left click focuses the element under the cursor and then performs its natural
action. `nit_hit:find_at/4` resolves the coordinate to one of `{button, Id}`,
`{input, Id}`, `{text_view, Id}`, `{list, Id}`, `{tab, TabsId, TabId}`,
`{table_row, Id, RowIdx}`, `{table_header, Id, ColumnId}` or
`{table_cell, Id, RowIdx, ColumnId}`.

Clicks on a non-focusable element do not move focus. Wheel scrolling acts on
the element under the pointer, focused or not.

## Focus across rebuilds

Focus is stored as a container id plus a child id, so it survives `view/1`
rebuilds as long as the ids are stable. Use deliberate, constant ids for
anything focusable; ids generated per render will drop focus on every tick.

When the focused element disappears from the tree, the framework resolves focus
to the nearest remaining container.

Pushing a view saves the current container/child pair and restores it on `pop`.
Modals and fullscreen keep their own focus scope — see
[Views and overlays](views-and-overlays.html).
