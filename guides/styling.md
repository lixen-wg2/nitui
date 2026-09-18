# Styling

Every element has a `style` map. Unknown keys are ignored, so a style map is
always safe to pass around.

```erlang
#text{content = "Critical", style = #{fg => red, bold => true}}
```

## Style keys

| Key | Values |
|-----|--------|
| `fg` | A colour name (below) |
| `bg` | A colour name (below) |
| `bold` | `true` |
| `dim` | `true` |
| `italic` | `true` |
| `underline` | `true` |
| `reverse` | `true` — swaps foreground and background |

Only `true` enables an attribute; `false` is the same as omitting the key.

## Colours

`black`, `red`, `green`, `yellow`, `blue`, `magenta`, `cyan`, `white`, and the
bright variants `bright_black`, `bright_red`, `bright_green`,
`bright_yellow`, `bright_blue`, `bright_magenta`, `bright_cyan`,
`bright_white`. `gray` is an alias for `bright_black`.

Unrecognised colour names fall back to `white` for `fg` and `black` for `bg`
rather than failing. Colours map to `io_ansi` named colours, so the terminal
theme decides the exact shade.

`NO_COLOR` in the environment is reported through
`nit_terminal:capabilities/0`.

## Macros

`nit_elements.hrl` defines shorthand macros for the common cases:

```erlang
#text{content = "Warning", style = ?FG_YELLOW}
#text{content = "Title",   style = ?BOLD}
```

`?FG_BLACK`..`?FG_WHITE`, `?BG_BLACK`..`?BG_WHITE`, `?BOLD`, `?DIM`,
`?ITALIC`, `?UNDERLINE`. They expand to plain maps, so merge them freely:

```erlang
style = maps:merge(?FG_CYAN, ?BOLD)
```

## Per-widget style fields

Widgets that render several visual states expose them as separate fields
instead of overloading `style`:

| Element | Fields |
|---------|--------|
| `#button{}` | `focused_style` (`#{bold => true, underline => true}`), `disabled_style` (`#{fg => bright_black, dim => true}`) |
| `#box{}` | `focused_border`, `focused_style` (`#{fg => yellow, bold => true}`) when `focus_within = true` |
| `#table{}` | `header_style`, `selected_style` (`#{bg => cyan, fg => black}`), `focused_selected_style` (`#{bg => white, fg => black, bold => true}`), `zebra` |
| `#list{}` | `item_style`, `selected_style` (`#{bg => blue, fg => white}`) |
| `#tree{}` | `selected_style`, `focused_selected_style`, `full_row_selection` |
| `#text_view{}` | `selection_style` (`#{bg => blue, fg => white}`) |
| `#stat_row{}` | `label_style`, `value_style` (`#{bold => true}`) |
| `#status_bar{}` | `key_style` (`#{bold => true, fg => cyan}`), `label_style` |
| `#header{}` | `bg_color` (`blue`), `fg_color` (`white`) |
| `#progress_bar{}` | `color`, `bar_char`, `empty_char`, `threshold_warn`, `threshold_crit` |
| `#sparkline{}` | `color`, `style_type` (`braille \| block \| ascii`) |

`#progress_bar.color = auto` (the default) picks green below
`threshold_warn` (0.70), yellow below `threshold_crit` (0.85) and red above it,
as fractions of `max`. Set an explicit colour name to disable the thresholds.

## Sharing styles

Styles are ordinary data, so factor them out in your own module:

```erlang
-define(HEADING, #{bold => true, fg => cyan}).

section(Title, Children) ->
    #vbox{children = [#text{content = Title, style = ?HEADING} | Children]}.
```

## Unicode and widths

Layout measures display width, not bytes or code points, so wide CJK
characters and emoji occupy two cells and do not shift columns. Use
`nit_unicode:display_width/1` when you compute widths yourself, and
`nit_unicode:truncate/2` to cut a string to a cell budget.

Box-drawing characters work as separators:

```erlang
#table{column_separator = <<"│"/utf8>>, ...}
```

## Formatting values

`nit_format` covers the recurring display conversions:

| Function | Example |
|----------|---------|
| `nit_format:commas/1` | `1234567` → `<<"1,234,567">>` |
| `nit_format:bytes/1` | `1536` → `<<"1.5 KB">>`; `undefined` → `<<"?">>` |
| `nit_format:duration/1` | `3661` → `<<"01:01:01">>`; `90061` → `<<"1d 01:01:01">>` |
