# Tables

`#table{}` is the widget most TUI applications spend their time in, so it has
the largest set of options.

```erlang
#table{
    id = proc_table,
    height = fill,
    border = single,
    focusable = true,
    sortable = true,
    activate_on_reclick = true,
    columns = [
        #table_col{id = pid,  header = "PID",    width = 14},
        #table_col{id = name, header = "Name",   width = fill},
        #table_col{id = reds, header = "Reds",   width = 14, align = right}
    ],
    rows = [[Pid, Name, Reds] || ...],
    selected_row = 1
}
```

Rows are lists of terms in column order. Non-string terms are formatted for
display; keep raw values (pids, integers) in the row so the event handler gets
them back unparsed.

## Columns

`#table_col.width` accepts:

| Value | Behaviour |
|-------|-----------|
| `auto` | Fit the widest cell |
| `{fixed, N}` | Exactly `N` cells, never shrinks |
| `fill` | Share the space left after fixed and preferred columns |
| `N` | Legacy proportional sizing |

`align` is `left` (default), `center` or `right`. Column widths are measured in
display cells, so wide characters and emoji are accounted for.

## Selection and activation

`selected_row` is 1-based; `0` means no selection. Arrow keys move it and emit
`{table_select, Id, RowIndex, RowData}`. Enter emits
`{table_activate, Id, RowIndex, RowData}`.

| Field | Effect |
|-------|--------|
| `activate_on_click = true` | A click selects *and* activates the clicked row |
| `activate_on_reclick = true` | Clicking the already-selected row activates it |
| `on_select` | Handler value echoed back in events |

## Sorting

`sortable = true` makes the column headers clickable. A click toggles
`sort_by` / `sort_dir` and re-sorts `rows` in place, then emits
`{table_header_click, Id, ColumnId}`. Set `sort_by` and `sort_dir` yourself to
choose the initial order.

Sorting is applied to static rows by the framework. In virtual mode the
application owns ordering: handle `{table_header_click, ...}`, sort at the
source, and return new state.

## Styling

| Field | Default |
|-------|---------|
| `border` | `none` |
| `show_header` | `true` |
| `header_separator` | `true` — a rule below the header; `false` gives a one-line header |
| `header_style` | `#{}` — overrides the table style and the default bold on the header only |
| `column_separator` | `" "` — e.g. `<<"│"/utf8>>` for ruled columns |
| `zebra` | `true` — alternating row background |
| `selected_style` | `#{bg => cyan, fg => black}` |
| `focused_selected_style` | `#{bg => white, fg => black, bold => true}` |

## Virtual scrolling

For datasets too large to materialise, supply a row provider instead of `rows`:

```erlang
#table{
    id = big_table,
    height = fill,
    focusable = true,
    columns = Columns,
    total_rows = 1_000_000,
    row_provider = fun(Start, Count) -> fetch(Start, Count) end
}
```

`row_provider` is called with a **0-based** start index and a count, and must
return that many rows (or fewer at the end). Only the visible window is
fetched; navigation, paging and mouse hits all resolve through the provider.

Set `row_keys` to unique keys for the absolute rows so selection follows a row
by identity when the data refreshes or reorders.

## Preserving state across rebuilds

By default the framework merges the previous table's selection, scroll offset
and sort order into the rebuilt element, keyed by `id`. This is what makes
per-second `tick` refreshes usable.

`controlled = true` inverts that: the values in the freshly returned element
win, and the application owns selection, scroll and sort. Navigation still
emits `{table_select, ...}` and `{table_activate, ...}` events, so store the
row index in your state and feed it back through `view/1`.

`row_keys` is the middle ground — uncontrolled merging, but anchored to row
identity instead of row position.

## Clickable cells

`clickable_columns` is a list of `#table_col.id` values whose data cells become
individually clickable:

```erlang
#table{id = t, clickable_columns = [name], ...}
```

- A cell click selects the row, focuses the table, and calls `handle_event/2`
  with **only** `{table_cell_click, Id, RowIdx, ColumnId, RowData}` — no
  preceding `table_select` or `table_activate`, even with `activate_on_click`
  or `activate_on_reclick` enabled.
- `RowIdx` is the absolute 1-based index including the scroll offset. `RowData`
  is the complete row, fetched through `row_provider` in virtual mode.
- The rendered column width including alignment padding is clickable. Column
  separators, trailing padding and other columns keep their previous
  behaviour; hits are limited to rendered rows within the visible bounds.
- Headers still sort, and arrow keys plus Enter keep native selection and
  activation.
- With `controlled = true`, the next `view/1` still owns selection — store
  `RowIdx` if the click should stick.

Unknown ids in `clickable_columns` are ignored, and the option changes no
styles. `nit_hit:find_at/4` returns `{table_cell, Id, RowIdx, ColumnId}` for
these cells.
