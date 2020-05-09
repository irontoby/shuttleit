# shuttleit
Event handler for Contour Design ShuttleXpress

## Work (Not?) In Progress

This is a perl script which reads the HID events from a Contour
ShuttleXpress, and translates them into keypresses.

This is scratching my own itch. I want to use mine as a media control
to send play/pause/next/prev track keys and raise/lower volume in Linux.
Thus, the actions performed by each button are hard-coded into the script.

I kinda wish I'd used this as an opportunity to learn Go, but Perl is what
I knew, so... here we are ¯\\\_(ツ)\_\/¯

The next logical steps would be to add command-line options for `--debug`,
`--daemon`, etc., as well as a better way for changing what each button does,
but since it already does what I need I'm not sure I'll get around to it.
Feel free to email me or add an Issue if you'd like to request something.
Of course patches are welcome too!

## Installation / Use

I've only tested this on Ubuntu 14.04+ (including 20.04), but it should work
on any system where a device file can be created to read inputs from.

1. Leave the ShuttleXpress unplugged.

1. Copy 90-shuttlexpress.rules to your udev rules directory. On Ubuntu,
   this is `/etc/udev/rules.d`:

        sudo cp 90-shuttlexpress.rules /etc/udev/rules.d

   The purpose of this entry is to tell the udev subsystem that it should
   create a world-readable device file entry at `/dev/shuttlexpress` any time
   the device is plugged in. That way, the script can be run by any user
   without root privileges.

1. Install `xdotool` if not already present (`sudo apt install xdotool`).
   This is used to send the keypresses which will be simulated by the script.

1. Plug your ShuttleXpress into a USB port and verify that the device
   `/dev/shuttlexpress` got created. Recent versions of Ubuntu use `inotify`
   so the rule should be picked up immediately; if not then try
   `sudo udevadm control --reload-rules`.

1. Either manually run `shuttleit.pl`, or set it to run automatically when
   you login. On Ubuntu, this is best accomplished using the "Startup
   Applications" tool. By default, it will stay running in the background.

1. Turn the knob on your ShuttleXpress; your system volume should adjust
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

I wrote my script in Perl because it's already installed on most \*nix distros.
There are no other external dependencies or build requirements; all of the
other options out there I could find (see below) didn't make it very easy to
get them running and in the end I couldn't get them to work.

## Others

There are a few other tools out there that basically do the same thing, but
I wasn't able to use them for various reasons. But one of them may work for you.

* The LinuxCNC project [has a ShuttleXpress](http://linuxcnc.org/docs/html/drivers/shuttlexpress.html)
  driver, but it's an entire embedded distro & extracting just that tool wasn't
  feasible. [GitHub source here](https://github.com/jepler/linuxcnc-mirror).
* The [ShuttlePro project](http://freecode.com/projects/shuttlepro) on FreeCode
  has what appears to be a standalone program but I couldn't get it to build.
  It seems to be an entire GUI-based tool to also allow mapping the translations.
  [GitHub source here](https://github.com/nanosyzygy/ShuttlePRO).
* Here's [another ShuttleXpress tool on GitHub](https://github.com/threedaymonk/shuttlexpress)
  written in Scheme. I could barely figure out what Chickens and Eggs were, much
  less build the thing.
