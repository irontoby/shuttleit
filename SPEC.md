# ShuttleXpress Input Service — Build Spec

Documentation of the existing Perl daemon, written as a specification for
re-implementing it as a Go service. The service reads 5-byte packets from a
Contour ShuttleXpress USB device and turns them into media-key actions.

---

## 1. What the service does

1. Opens the device file (`/dev/sxp` for the new build; the Perl original used `/dev/shuttlexpress`).
2. Reads **exactly 5 bytes per packet** in a loop.
3. Decodes each packet into dial movement, ring position, and 5 button states.
4. Detects **edges** (button just pressed / just released) and **dial direction** by comparing against the previous packet.
5. Fires `xdotool` key commands for specific events.
6. If the device is missing or disappears, retries every 5 seconds, forever.

---

## 2. Packet format (5 bytes)

The device emits a packet only after the first interaction; it is silent until then.

| Byte | Name | Type | Meaning |
|------|--------|-------------|---------|
| 0 | `ring` | **signed** int8 | Outer shuttle ring. `0` = center; `+1..+7` = turned right; `-1..-7` = turned left. Spring-loaded — returns to `0` when released. |
| 1 | `dial` | uint8 | Inner jog dial. Free-spinning. Counts `0–255` then wraps back to `0`. |
| 2 | — | uint8 | Unused. Discarded. |
| 3 | `btn` | uint8 | Bitmask for buttons 1–4 (see below). |
| 4 | `pinky` | uint8 | Button 5. `1` = pressed, `0` = released. |

**Button 1–4 bitmask (byte 3):**

| Button | Bit | Hex | Decimal |
|--------|-----|------|---------|
| btn1 | b4 | `0x10` | 16 |
| btn2 | b5 | `0x20` | 32 |
| btn3 | b6 | `0x40` | 64 |
| btn4 | b7 | `0x80` | 128 |

A button is pressed if `(btn & mask) == mask`. Buttons can be held in any combination, so test each bit independently.

---

## 3. Dial direction detection

The dial reports an absolute position (`0–255`), not a delta. Direction is derived by comparing the current value to the previous one.

- `dial_change` is one of `-1` (left), `0` (none), `+1` (right).
- Base value: `sign(dial - old_dial)`.
- **Wrap correction:** if `abs(dial - old_dial) > 200`, the counter wrapped the `0↔255` boundary, so **invert** the sign.
  - Example: `254 → 2` is physically a small right turn (`+1`), but naive subtraction says `-1`; the wrap rule flips it back to `+1`.
- **First-reading guard:** the previous dial starts as a sentinel `999`. While it is `999`, `dial_change` is forced to `0`. This prevents a spurious volume event on the very first packet. After the first real reading, normal comparison applies.

**Note for the port:** `dial_change` only ever reports one step (`±1`), regardless of how far the dial jumped. Fast spins collapse to a single event. Decide whether you want to emit multiple events proportional to the delta instead.

---

## 4. State tracking and edges

Between packets, the service persists only: `dial`, `btn1`, `btn2`, `btn3`, `btn4`, `btn5`.
(`ring` and `dial_change` are recomputed fresh each packet and not stored.)

For each button, compare the new value to the stored previous value:

- **down** (just pressed): previous `0` → current `1`.
- **up** (just released): previous `1` → current `0`.

Actions fire on the **down edge**, not on the held state (except where noted).

---

## 5. Action mapping

All actions run `xdotool key <keysym>`.

| Trigger | Command |
|---------|---------|
| Dial turned right (`dial_change == +1`) | `XF86AudioRaiseVolume` |
| Dial turned left (`dial_change == -1`) | `XF86AudioLowerVolume` |
| Button 2 down | `XF86AudioPrev` |
| Button 3 down | `XF86AudioPlay` |
| Button 4 down | `XF86AudioNext` |
| Button 5 down | `alt+shift+w` |
| Button 1 **held** AND button 3 down | `XF86AudioStop` |

**Unbound inputs:**
- **Button 1** has no standalone action — it only acts as a modifier for the Stop combo (held while btn3 is pressed).
- **The shuttle ring** is decoded and logged but has no action bound to it. (Room to add one in the new build.)

---

## 6. Process / lifecycle behavior

The Perl original was launched by udev when the device is plugged in, and managed its own daemon lifecycle. Most of this can be replaced by your service manager (e.g. systemd) in the Go build.

- **udev trigger:** checks the `ACTION` environment variable and exits unless it is `add`. Only runs when the device is added.
- **Daemonize:** double-`fork` + `setsid`, `chdir /`, close stdio. Detaches from the terminal.
- **Single-instance ("highlander"):** on startup it sends `SIGUSR1` to every other process of the same name (`killall -USR1`), causing them to exit, so only the newest instance survives.
- **Signals:**
  - `SIGTERM` → clean exit (removes pidfile, exits 0).
  - `SIGUSR1` → exit, unless it is the instance that just sent the signal.
- **PID file:** writing is **disabled by default** (`WRITEPID = 0`). Path was `/var/run/shuttleit.pl.pid`.
- **Retry loop:** if the device can't be opened or vanishes mid-read, return and `sleep 5`, then retry — indefinitely.

**Config flags (top of script):**

| Flag | Default | Effect |
|------|---------|--------|
| `DEBUG` | 1 | Verbose logging of every packet and decoded state. |
| `DOIT` | 1 | Actually run `xdotool`. Set 0 to decode-only (dry run). |
| `DAEMONIZE` | 1 | Background the process. |
| `WRITEPID` | 0 | Write a pidfile. |

---

## 7. Notes for the Go implementation

- **Read framing:** use `io.ReadFull` on a 5-byte buffer so a short read doesn't desync the packet stream. Treat each full 5-byte read as one packet.
- **Signed first byte:** byte 0 is signed (`int8`), the rest unsigned (`uint8`). Cast byte 0 explicitly.
- **xdotool needs a display:** `xdotool` talks to X11 and requires `DISPLAY` and `XAUTHORITY` for the logged-in user's session. A system-level service has neither. The original author left a TODO to split this out and run as the logged-in user. Options:
  - Run as a **user** service (`systemd --user`) inside the graphical session, or
  - Set `DISPLAY`/`XAUTHORITY` explicitly to target the active session.
- **Consider `uinput` instead of xdotool:** injecting a virtual keyboard via `/dev/uinput` avoids per-keypress process spawns, cuts latency, and works under Wayland (where xdotool does not). Go binding: `github.com/bendahl/uinput`.
- **Single-instance:** let systemd enforce one instance; you can drop the killall/USR1 dance entirely.
- **First-reading guard:** replicate the `999` sentinel behavior so the service doesn't fire a stray volume key on the first packet after connect.
- **Dial magnitude:** decide whether to keep the one-event-per-packet behavior or emit events proportional to the dial delta.
- **Device retry:** keep the reopen-every-5s loop, or rely on udev/systemd to (re)start the service on device add.
