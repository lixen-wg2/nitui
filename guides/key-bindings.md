# Key bindings

The framework consumes a small fixed set of keys. Everything else reaches
`handle_event/2` as `{event, RawEvent}`, so applications are free to bind it.

## Always consumed

| Key | Effect |
|-----|--------|
| `Tab` | Focus the next container |
| `Shift+Tab` | Focus the previous container |
| `Enter` | Activate the focused element |
| `Ctrl+C` | Call `handle_event(quit, State)`; the UI stops only if you return `{stop, Reason, State}` |
| `Escape` | Close an active modal, or leave fullscreen — otherwise forwarded |

Note that `Escape` is only consumed when a modal or fullscreen element is
active. On a plain screen it is forwarded, which is why demo screens can bind
it to `pop` or "back".

## Consumed when a widget can use them

These are offered to the focused element first and forwarded only if nothing
uses them.

| Key | Focused element | Effect |
|-----|-----------------|--------|
| `Up` / `Down` | table, list, tree, scroll, text view | Move selection or scroll |
| `Left` / `Right` | input, text view | Move the cursor |
| `Left` / `Right` | tree | Collapse / expand the node |
| `Left` / `Right` | tabs container | Switch tab |
| `Page Up` / `Page Down` | table, list, tree, scroll, text view | Page; swallowed while a modal is open |
| `Home` / `End` | input, text view | Start / end of line |
| `Shift+Left/Right/Home/End` | input, text view | Extend the selection |
| `Ctrl+A` | input, text view | Select all |
| `Space` | enabled focusable button | Activate it |
| `Backspace` / `Delete` | input | Edit the value |
| Printable characters | input | Insert into the value |
| `y` / `Y` | text view | Copy selection / copy all |

A focused `#text_view{}` swallows other printable characters so screen
shortcuts cannot fire while reading text; `q` is exempt. Inside a modal,
printable characters never reach the view underneath.

## Mouse

SGR extended mouse reporting (1006) with motion (1002) is enabled while the UI
runs.

| Action | Effect |
|--------|--------|
| Left click | Focus and act on the element under the cursor |
| Left drag | Extend a text-view selection |
| Wheel up / down | Scroll the element under the pointer by one line |

Clicks resolve through `nit_hit:find_at/4` to buttons, inputs, text views,
lists, tabs, table rows, table headers and clickable table cells.
Unrecognised mouse events are dropped rather than forwarded.

## Forwarded to the application

Everything not listed above, including:

- `{char, Char}` for printable characters with no input focused
- `{ctrl, Char}` for every combination except `Ctrl+C` and a consumed `Ctrl+A`
- `{key, f1}`..`{key, f12}`
- `{key, {shift, up | down | page_up | page_down}}`
- `escape` on a plain screen
- `{paste, start | 'end'}` bracketed paste markers
- unconsumed arrow, Home/End and Page keys

They arrive wrapped as `{event, RawEvent}`.

## Conventional application bindings

The framework does not define a quit key. The bundled demo, and most
applications, use these — declare them with `nit_shortcuts:handle/3` and
advertise them in a `#status_bar{}`:

```erlang
handle_event(Event, State) ->
    case nit_shortcuts:handle(Event, State, [
        {"h",           fun(_) -> {switch, home_view, #{}} end},
        {"r",           fun(S) -> {noreply, refresh(S)} end},
        {["q", escape], {stop, normal}}
    ]) of
        nomatch -> {unhandled, State};
        Result -> Result
    end.
```

```erlang
#status_bar{items = [{"H", "Home"}, {"R", "Refresh"}, {"Q", "Quit"}]}
```

Character specs match case-insensitively, so `"q"` also matches `Q`.

## Terminal caveats

- `Ctrl+C` never reaches the shell: the terminal is in raw mode, so the
  framework receives `{ctrl, $c}` and asks the application. Applications should
  honour `quit` with `{stop, normal, State}` unless they have a good reason not
  to.
- A bare `Escape` is indistinguishable from the start of an escape sequence for
  one read. `nit_input` resolves this by emitting `escape` when no `[` follows.
- Shifted arrow and Page variants depend on the emulator sending the standard
  `\e[1;2X` and `\e[5;2~` forms.
