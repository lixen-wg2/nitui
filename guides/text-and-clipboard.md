# Text and clipboard

## Static text

`#text{}` renders a string or binary. With `wrap = true` it wraps at the width
it is allocated, which in an `#hbox{}` is the width that child actually
receives, not the parent width.

```erlang
#text{content = "A long explanation...", wrap = true}
#text{content = "Heading", style = #{bold => true}}
```

`#text{}` is not focusable and not selectable. For text the user should be able
to read, scroll and copy, use `#text_view{}`.

## `#text_view{}`

A read-only viewer with cursor, selection, scrolling and an optional copy
toolbar.

```erlang
#text_view{
    id = log_view,
    focusable = true,
    height = fill,
    content = Log,
    show_scrollbar = true,
    show_toolbar = true
}
```

| Field | Default | Notes |
|-------|---------|-------|
| `content` | `<<>>` | Binary or string; invalid UTF-8 is refused, never partially copied |
| `cursor_pos` | `0` | Position in **source grapheme clusters** |
| `selection_anchor` | `undefined` | Other end of the selection, same units |
| `offset` | `0` | First visible wrapped line |
| `show_scrollbar` | `true` | Reserves the rightmost column |
| `show_toolbar` | `true` | Reserves the bottom row for copy actions and status |
| `selection_style` | `#{bg => blue, fg => white}` | |
| `copy_status` | `idle` | Result of the last copy attempt, rendered in the toolbar |

Positions count grapheme clusters in the source string — never terminal cells
and never visual line breaks — so they stay stable when the viewport resizes.

### Keys

| Key | Action |
|-----|--------|
| Arrows, Home/End, Page Up/Down | Move the cursor, scrolling to reveal it |
| Shift + the above | Extend the selection |
| Ctrl+A | Select all |
| `y` | Copy the selection |
| `Y` | Copy the whole content |

Mouse press, drag and release set and extend the selection; dragging past the
top or bottom edge scrolls. The wheel scrolls without moving the cursor.

A focused `#text_view{}` swallows other character keys so they cannot trigger
screen shortcuts by accident — `q` is the exception and still reaches the
application. Inside a modal, character keys are swallowed entirely.

### Toolbar

When `show_toolbar = true` the bottom row shows `[y Copy]` and `[Y Copy all]`,
clickable when they fit, then the status of the last copy attempt, then the
hint `Ctrl-A all, Shift-arrows select`. The row is truncated to the available
width. Statuses are:

| `copy_status` | Toolbar text |
|---------------|--------------|
| `{ok, sent}` | Sent to terminal (clipboard unverified) |
| `{error, disabled}` | Clipboard disabled |
| `{error, too_large}` | Too large; select less |
| `{error, invalid_text}` | Invalid UTF-8 text |
| `{error, unavailable}` | Clipboard unavailable |
| `{error, write_failed}` | Terminal write failed |
| `{error, no_selection}` | No selection |

### Rebuilds

`nit_el_text_view:merge/2` keeps cursor, selection, offset and copy status when
the rebuilt element has identical `content`. When the content changes, all four
are reset — a refreshed log view starts at the top with no selection.

## Copying from application code

`nitui:copy_to_clipboard/1` writes UTF-8 chardata to the terminal using
OSC 52, through the terminal NitUI owns — never stdio:

```erlang
handle_event({click, copy_btn, _}, #{report := Report} = State) ->
    _ = nitui:copy_to_clipboard(Report),
    {noreply, State}.
```

The result is `{ok, sent}` or `{error, Reason}` where `Reason` is one of
`disabled`, `too_large`, `invalid_text`, `unavailable` or `write_failed`.

> #### `sent` is not `copied` {: .warning}
>
> `{ok, sent}` means the escape sequence reached the terminal. Terminals and
> multiplexers may ignore or refuse OSC 52, and NitUI never queries or reads
> the clipboard to check. Report it to users as unverified.

Oversized text is refused, never truncated. Empty text is valid and clears the
clipboard.

`nit_clipboard:encode/2` is the pure encoder if you need the bytes without
writing them; it takes the same options as the application environment keys and
reads no configuration itself.

## Configuration

| Key | Default | Notes |
|-----|---------|-------|
| `clipboard_enabled` | `true` | Only `true` enables copying; anything else yields `{error, disabled}` |
| `clipboard_max_bytes` | `65536` | Raw UTF-8 bytes before base64; valid range `1..1048576` |
| `clipboard_transport` | `direct` | `tmux` wraps the sequence in DCS passthrough |

`tmux` passthrough must be enabled explicitly and supported by the multiplexer;
its presence is never detected or assumed. See
[Configuration](configuration.html).
