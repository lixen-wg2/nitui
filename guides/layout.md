# Layout and sizing

Layout runs top-down over the element tree. Each element reports a height and a
width for the bounds it is offered, and `nit_layout` resolves flexible children
against the space that is left.

## Width and height

`width` accepts `auto` or a positive integer. `height` accepts `auto`, `fill`
or a positive integer.

| Value | Meaning |
|-------|---------|
| `auto` | Fit the element's content |
| `fill` | Consume the space remaining in the parent |
| Integer | Exactly that many terminal cells |

Sizes are measured in terminal cells, using display width — a wide CJK
character or emoji counts as two cells. See `nit_unicode`.

## Vertical layout

`#vbox{}` asks each child for a height. A child that wants to flex reports
`{flex, Min}` instead of an integer; `nit_layout:calculate_vbox_heights/3,4`
divides the leftover space equally between all flexing children, never giving
any of them less than its `Min`.

```erlang
#vbox{children = [
    #header{title = "Fixed 1 row"},
    #table{id = t, height = fill, ...},   %% takes what is left
    #status_bar{items = [...]}            %% fixed 1 row, stays at the bottom
]}
```

`#spacer{}` is the dedicated flexible element: it reports `{flex, min_height}`
and renders blank. Use it to push a `#status_bar{}` to the bottom of a screen
that has no `fill` child:

```erlang
#vbox{children = [content(), #spacer{}, #status_bar{items = [...]}]}
```

> #### Do not sum heights yourself {: .warning}
>
> `nit_layout:element_height/2` returns `{flex, Min}` for flexible elements.
> Summing raw heights in application code will crash on the first flex child.
> Let the containers resolve sizes.

## Horizontal layout

`#hbox{}` asks each child for a *fixed* width via
`nit_layout:element_fixed_width/1`. Children that report `auto` share the space
that is left after the fixed children and the inter-child `spacing`, with any
remainder handed to the leftmost auto children one cell at a time. An auto
child never receives less than one cell.

```erlang
#hbox{spacing = 2, children = [
    #text{content = "Label:", width = 10},  %% fixed
    #input{id = name, focusable = true},    %% shares the rest
    #button{id = ok, label = "OK", focusable = true}
]}
```

Wrapped text is measured against the width each child actually receives, not
the parent width, so `#text{wrap = true}` inside an `#hbox{}` reports its true
wrapped line count.

## Borders and insets

`#box{border = none}` passes its bounds through to its children unchanged. Any
other border value renders a frame and insets the children — and the mouse hit
areas — by one cell on every side. Budget two rows and two columns when sizing
a bordered container's contents.

`#box.title` is drawn into the top border, so it requires a border to be
visible.

## Scrolling

`#scroll{}` gives its children the full height they ask for and shows a window
into the result, tracking `offset` in lines. Page keys move the offset when the
scroll container is focused; the mouse wheel moves whichever scrollable element
is under the pointer, falling back to the focused one. `show_scrollbar = true`
(the default) reserves the rightmost column for the indicator.

Long tables should use `#table{height = fill}` rather than a `#scroll{}`
wrapper: the table paginates internally and keeps its header row fixed. See
[Tables](tables.html).

## Resolving bounds after the fact

`nit_bounds:find_element_bounds/3` returns the resolved `#bounds{}` of an
element id within a tree, which is what the framework uses for hit testing.
`nit_hit:find_at/4` maps a terminal coordinate to the element (or table cell,
or tab, or toolbar action) under it.
