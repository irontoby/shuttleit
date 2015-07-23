#!/usr/bin/perl

use warnings;
use strict;

our $DEBUG = 1;
our $DOIT = 1;
our $DAEMONIZE = 1;
our $WRITEPID = 0;

my $device = '/dev/shuttlexpress';
my $pidfile = '/var/run/shuttleit.pl.pid';

our $STAY_ALIVE = 0;

our $STATE = {};
&init_state();

use POSIX;
use File::Basename;

&daemonize() if $DAEMONIZE;

my $action = $ENV{ACTION} || 'add';

if($action ne 'add') {
	warn "run only on add\n";
	exit(0);
}

$SIG{TERM} = \&clean_exit;
$SIG{USR1} = \&tap_out;

our $self_name = basename($0);

warn "$self_name starting...\n";

&highlander();
&writepidval() if $WRITEPID;

my $pid = &getpidval();

warn "PID is $pid\n";

while(1) {
	&read_device();
	
	# If we came back here, device doesn't exist; check again in a while
	sleep 5;
}

sub init_state {
	our $STATE = { qw(dial 999 btn1 0 btn2 0 btn3 0 btn4 0 btn5 0) };
}

sub read_device {
	my $fh;
	open($fh, '<', $device) or return &no_device();
	
	my(@bytes, $in);
	
	while(read($fh, $in, 5)) {
		# First bit (ring) is signed, rest are unsigned
		@bytes = unpack('cC*', $in);
		&process_bytes(@bytes);
		
		unless(-e $device) {
			return &no_device();
		}
	}
}

sub no_device {
	return 0;
	
	# Eventually may want to exit here if device disappears?
	#&clean_exit("Couldn't read device $device");
}

sub process_bytes {
	my @bytes = @_;
	warn join(',', @bytes), "\n" if $DEBUG;
	
	# ring = outside ring: 0 = center, 1-7 = right, -1- -7 = left
	# dial = thumb dial, 0-255 then back to 0
	# btn = bitmask for buttons 1-4: 16, 32, 64, 128
	# pinky = 1 if button 5 pushed, 0 if not
	my($ring, $dial, undef, $btn, $pinky) = @bytes;
	
	# dial_change will be -1, 0, or 1 for left, none, right
	my $dial_change = 0;
	my $old_dial = $STATE->{'dial'};
	
	# device doesn't send value until first button-push
	if($old_dial < 999) {
		$dial_change = $dial <=> $old_dial;
		
		if($dial_change && (abs($dial - $old_dial) > 200)) {
			# wrapped around between 0 <-> 255
			$dial_change *= -1;
		}
	}
	
	my $state = {
		dial => $dial,
		ring => $ring,
		dial_change => $dial_change,
		btn1 => &bit_check(16, $btn),
		btn2 => &bit_check(32, $btn),
		btn3 => &bit_check(64, $btn),
		btn4 => &bit_check(128, $btn),
		btn5 => $pinky,
	};
	
	&set_buttons_up_down($state);
	
	&show_state($state) if $DEBUG;
	
	&process_state($state) if $DOIT;
	
	my @keep_state = qw(dial btn1 btn2 btn3 btn4 btn5);
	
	@$STATE{@keep_state} = @$state{@keep_state};
}

sub set_buttons_up_down {
	my($state) = @_;
	
	my $change;
	
	foreach my $num (1..5) {
		$change = exists $STATE->{"btn$num"} ?
			$state->{"btn$num"} <=> $STATE->{"btn$num"} :
			0;
		$state->{"down$num"} = (($change == 1) + 0);
		$state->{"up$num"} = (($change == -1) + 0);
	}
}

sub process_state {
	my($state) = @_;
	
	#TODO Need to split these into a separate script & run as logged in user

	# If dial changed to right or left, raise/lower volume
	system "/usr/bin/xdotool key XF86AudioRaiseVolume" if $state->{dial_change} == 1;
	system "/usr/bin/xdotool key XF86AudioLowerVolume" if $state->{dial_change} == -1;

	# ButtonDown 2, 3, 4 = Prev Track, Play/Pause, Next Track
	system "/usr/bin/xdotool key XF86AudioPrev" if $state->{down2};
	system "/usr/bin/xdotool key XF86AudioPlay" if $state->{down3};
	system "/usr/bin/xdotool key XF86AudioNext" if $state->{down4};
	system "/usr/bin/xdotool key alt+shift+w" if $state->{down5};
	
	# Stop if hold down button 1 + press button 3
	system "/usr/bin/xdotool key XF86AudioStop" if ($state->{btn1} && $state->{down3});
}

sub bit_check {
	my($bit, $check) = @_;
	return ((($bit & $check) == $bit) + 0);
}

sub show_state {
	my($state) = @_;
	foreach my $key(qw(dial ring dial_change)) {
		warn "  $key: $state->{$key}\n";
	}
	
	foreach my $num(1..5) {
		warn "button $num press/up/down: ",
			join('/', @$state{"btn$num", "up$num", "down$num"}), "\n";
	}
	
	warn "\n";
}

sub daemonize {
	fork and exit;
	POSIX::setsid();
	fork and exit;

	umask 0;
	chdir '/';
	close STDIN;
	close STDOUT;
	close STDERR;
}

sub highlander {
	our $STAY_ALIVE = 1;
	
	warn "Killing others...\n";
	system "/usr/bin/killall -USR1 $self_name";
	$STAY_ALIVE = 0;
}

sub getpidval {
	unless(-e $pidfile) {
		return -1;
	}
	
	my $pid = do {
		local $/ = undef;
		open(my $fh, '<', $pidfile) or return -1;
		<$fh>;
	};
	
	return $pid + 0;
}

sub writepidval {
	open(my $fh, '>', $pidfile) or return -1;
	
	print $fh "$$\n";
}

sub clean_exit {
	my($reason) = @_;
	
	warn "$reason\n" if $reason;
	
	warn "Cleaning up...\n";
	unlink $pidfile if -e $pidfile;
	exit(0);
}

sub tap_out {
	if($STAY_ALIVE) {
		warn "(not killing self...)\n";
		$STAY_ALIVE = 0;
		return 0;
	}
	warn "Passing the torch...\n";
	unlink $pidfile if -e $pidfile;
	exit(0);
}
