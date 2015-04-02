# shuttleit
Event handler for Contour Design ShuttleXpress

## Work In Progress

This is a perl script which reads the HID events from a Contour
ShuttleXpress, and translates them into keypresses.

This is scratching my own itch. I want to use mine as a media control
to send play/pause/next/prev track keys and raise/lower volume in Linux.

Hopefully I'll add some command-line options and a more convenient way of
changing what each control does without having to hack the main script.

## Installation / Use

1. Copy 90-shuttlexpress.rules to your udev rules directory. On Ubuntu,
   this is `/etc/udev/rules.d`:

        sudo cp 90-shuttlexpress.rules /etc/udev/rules.d

2. Plug your ShuttleXpress into a USB port and verify that the device
   `/dev/shuttlexpress` got created. Recent versions of Ubuntu use `inotify`
   so the rule should be picked up immediately; if not then try
   `sudo udevadm control --reload-rules`.

3. Either manually run `shuttleit.pl`, or set it to run automatically when
   you login. On Ubuntu, this is best accomplished using the "Startup
   Applications" tool.
4. Turn the knob on your ShuttleXpress; your system volume should adjust
   accordingly.

## Hacking

If it doesn't work correctly, try fiddling with these settings:

* `$DAEMONIZE`: Set to 1 to run in background; 0 to run in foreground.
* `$DOIT`: Set to 1 to send keypresses for ShuttleXpress events; 0 to
  prevent this.
* `$DEBUG`: Set to 1 to show events on STDERR as they're read; 0 for less
  verbose output.
* `process_state`: This is the Perl sub that actually acts on the state of the
  ShuttleXpress. Sorry, this is very particular to my needs at the moment.

Try setting `$DAEMONIZE` to 0, `$DOIT` to 0, and `$DEBUG` to 1 to see if the
script is at least reading your inputs.

When `/dev/shuttlexpress` is created according to the udev rule file, every
action on the ShuttleXpress will send 5 bytes to that device. These bytes
correspond to the various states of the controls (buttons up/down, outer
ring location, position of inner dial).

In addition, the script tracks the previous state and uses this to determine
whether the up/down state of each button has changed, and whether the dial has
moved to the left or the right since the previous read.
