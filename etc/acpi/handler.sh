#!/bin/sh
# Default acpi script that takes an entry for all actions

# ----------------------------------------------------------------------
# Globals
# ----------------------------------------------------------------------
#btstatus=block
#btstatus=
SAFESLEEP=0 # slightly slower if on; restarts network

# ----------------------------------------------------------------------
# Set options
# ----------------------------------------------------------------------
set $*

# ----------------------------------------------------------------------
# Get current X user and environment
# ----------------------------------------------------------------------
PID=`pgrep startx`
if [[ -n $PID ]];
then
	# found startx
	USER=`ps -o user --no-headers $PID `
	USERHOME=`getent passwd $USER | cut -d: -f6`
	export XAUTHORITY="$USERHOME/.Xauthority"
	for x in /tmp/.X11-unix/*; do
	    displaynum=`echo $x | sed s#/tmp/.X11-unix/X##`
	    if [ x"$XAUTHORITY" != x"" ]; then
		export DISPLAY=":$displaynum"
	    fi
	done
else
	# TODO: detect correct console user
	USER=root
fi

# ----------------------------------------------------------------------
# Main ACPI event handler
# ----------------------------------------------------------------------

ACPI_Event ()
{

	local _options="$*"
	logger "ACPI EVENT RECEIVED: $_options";

	case $1 in
	power) shift; case $1 in

		button) _Poweroff; ;;

		lid) shift; case $1 in
			open) ;;
			close) _Sleep; ;;
			esac ;;

		hotkey) shift; case $1 in
			battery) _Powersave; ;;
			sleep) _Sleep; ;;
			hibernate) _Sleep; ;;
			esac ;;

		ac) shift; case $1 in
			connected) _Powersave max ;;
			disconnected) _Powersave min; ;;
			esac ;;

		battery) shift; case $1 in
			connected) ;;
			disconnected) ;;
			esac ;;

		esac ;;

	security) shift; case $1 in
		lock) _Lock_System ;;
		esac ;;

	display) shift; case $1 in

		video) shift; case $1 in
			on) ;;
			off) ;;
			esac ;;

		hotkey) shift; case $1 in
			switchmode) ;;
			brightness) shift; case $1 in
				up) ;;
				down) ;;
				esac ;;

			esac ;;

		autolight) _Autolight ;;
		
		esac ;;

	tablet) shift; case $1 in

		display) shift; case $1 in
		    tabletmode) ;;
		    laptopmode) ;;
		    esac ;;

		stylus) shift; case $1 in
		    eject) _Annotate start ;;
		    dock) _Annotate finish ;;
		    esac ;;

		esac ;;

	wireless) shift; case $1 in

		switch) _Switch_Radios ;;

		hotkey) shift; case $1 in
			wifi) _Toggle_Wifi ;;
			bluetooth) _Toggle_Bluetooth ;;
			esac ;;

		esac ;;

	volume) shift; case $1 in

		input) 	shift; case $1 in
			mute) ;;
			esac ;;

		output) shift; case $1 in
			up) amixer set Master 5%+ unmute -q ;;
			down) amixer set Master 5%- unmute -q ;;
			mute) amixer set Master toggle -q ;;
			esac ;;

		esac ;;

	*) logger "ACPI KNOWN BUT UNHANDLED EVENT: $_options"

	esac

}

# ----------------------------------------------------------------------
# Functions
# ----------------------------------------------------------------------

Log () { logger "ACPI EXECUTION: $* (${FUNCNAME[1]})"; }

Is_True ()
{
	shopt -s nocasematch;
	case $1 in
		1|yes|true) return 0 ;;
		*) return 1 ;;
	esac;
	shopt -u nocasematch;
}

Map_Event_Codes ()
{
# I don't parse out the various ACPI event strings since they seem to change not infrequently between kernel releases.
# They instead are line items and I use them to in turn call an easier to manage function (ACPI_Event)

	case "$*" in

		# POWER
		xyz) _Autolight 	;;
		button/power*)				ACPI_Event power button ;;
		button/battery*)			ACPI_Event power hotkey battery ;;
		button/sleep*)				ACPI_Event power hotkey sleep ;;
		button/suspend*) 			ACPI_Event power hotkey hibernate ;;
		ac_adapter*0)				ACPI_Event power ac disconnected ;;
		ac_adapter*1)				ACPI_Event power ac connected ;;
		ibm/hotkey\ LEN0068:00*4010)		ACPI_Event power battery connected aux ;;
		ibm/hotkey\ LEN0068:00*4011)		ACPI_Event power battery disconnected aux ;;
		battery*:00*0) 				ACPI_Event power battery disconnected main ;;
		battery*:00*1) 				ACPI_Event power battery connected main ;;
		button/lid\ LID\ close)			ACPI_Event power lid close ;;
		button/lid\ LID\ open)			ACPI_Event power lid open ;;

		# SECURITY
		button/screenlock*)			ACPI_Event security lock ;;

		# WIRELESS
		MISSING)				ACPI_Event wireless switch ;;
		button/wlan*) 				ACPI_Event wireless hotkey wifi ;;
		button/f24*)				ACPI_Event wireless hotkey bluetooth ;; # f9

		# AUDIO
		button/volumedown*) 			ACPI_Event volume output down ;;
		button/volumeup*) 			ACPI_Event volume output up ;;
		button/mute*) 				ACPI_Event volume output mute ;;
		MISSING)				ACPI_Event volume input mute ;; # button: microphone mute (led is)

		# VIDEO/DISPLAY
		video/switchmode*)			ACPI_Event display hotkey switchmode ;;
		video/brightnessup*)			ACPI_Event display hotkey brightness up ;; # two events per key stroke?
		video/brightnessdown*)			ACPI_Event display hotkey brightness down ;; # two events per key stroke?
		MISSING)				ACPI_Event display on ;; # event: display on
		MISSING)				ACPI_Event display off ;; # event: display off (to be confirmed)

		# TABLET MODE
                MISSING)				ACPI_Event tablet display tabletmode ;; # screen moved to tablet mode
                MISSING)				ACPI_Event tablet display laptopmode ;; # screen moved back to laptop mode
                ibm/hotkey\ LEN0068:00*500c)		ACPI_Event tablet stylus eject ;;
                ibm/hotkey\ LEN0068:00*500b)		ACPI_Event tablet stylus dock ;;

		# MISC BUTTONS
		button/prog1*)				ACPI_Event misc button thinkvantage ;;

		# MISC HOTKEYS
		button/fnf1*)				ACPI_Event display autolight ;; # fn-f1
		MISSING)				ACPI_Event misc hotkey f6 ;; # media switchmode
		MISSING)				ACPI_Event misc hotkey f7 ;; # input switchmode
		button/fnf11*)				ACPI_Event misc hotkey f11 ;;
		button/zoom*)				ACPI_Event misc hotkey zoom ;;

		# MEDIA HOTKEYS
		cd/stop\ CDSTOP*)			ACPI_Event media stop ;;
		cd/play\ CDPLAY*)			ACPI_Event media play ;;
		cd/prev\ CDPREV*)			ACPI_Event media prev ;;
		cd/next\ CDNEXT*)			ACPI_Event media next ;;

		*)					Log "UNKNOWN EVENT: $*" ;;
	esac
}

_Lock_System () { physlock -dsu $USER; }

_Poweroff ()
{
	_Powersave max
	poweroff
}

_Sleep ()
{
	Log "SUSPENDING"; Is_True $SAFESLEEP && local sm=true || local sm=;

	ip link show wlan0 | grep -q UP && wlanstate=up || wlanstate=down # check current state of network

	netcfg -a
	ip link set wlan0 down
	ip link set eth0 down

	_Lock_System
	echo -n mem >/sys/power/state

	ip link set wlan0 $wlanstate
	rc.d restart net-auto-wireless
	rc.d restart net-auto-wired

	[[ $(cat /sys/class/power_supply/AC/online) > 0 ]] && _Powersave max || _Powersave min # power state?

	Log "RESUMED";
}

_Sleep_for_wpa_auto ()
{
	Log "SUSPENDING"; Is_True $SAFESLEEP && local sm=true || local sm=;
	ip link show wlan0 | grep -q UP && wlanstate=up || wlanstate=down # check current state of network
	[[ -n $sm || $wlanstate == down ]] && (modprobe -r iwlagn && Log "wlan down or safe sleep mode on: unloading network module")
	echo -n mem >/sys/power/state # kernel sleep
	modprobe iwlagn && ip link set wlan0 $wlanstate # always reload module; network stutters briefly otherwise
	[[ -n $sm && $wlanstate == up ]] && rc.d restart wpa_auto && Log "safe sleep mode; restarting wpa_auto" # slower, only in safe mode
	[[ $(cat /sys/class/power_supply/AC/online) > 0 ]] && _Powersave max || _Powersave min # power state?
	Log "RESUMED";
}

_Toggle_Bluetooth ()
{
	if rfkill list bluetooth | grep -iq "soft blocked: yes"
	then
		Log "BLUETOOTH TOGGLE ON";
		local btstatus=unblock
	else
		Log "BLUETOOTH TOGGLE OFF";
		local btstatus=block
	fi
	echo -n $btstatus > /var/tmp/bt
	eval "rfkill $btstatus bluetooth"
}

_Toggle_Wifi ()
{
	if rfkill list wifi | grep -iq "soft blocked: yes"
	then
		Log "WIFI OFF"
		#netcfg all-suspend
		netcfg -a
		ip link set wlan0 down
		#modprobe -r iwlagn
	else
		Log "WIFI ON"
		#ip link set wlan0 up && rc.d restart wpa_auto && Log "WIFI ON"
		#netcfg all-resume
		#modprobe iwlagn
		ip link set wlan0 up
		rc.d restart net-auto-wireless
		:
	fi
}

_Switch_Radios ()
{
	if rfkill list wifi | grep -iq "hard blocked: yes";
	then
		Log "RADIOS HARD SWITCHED OFF";
	else
		Log "RADIOS HARD SWITCHED ON";
		eval "rfkill $(cat /var/tmp/bt) bluetooth";
		ip link set wlan0 up; rc.d restart wpa_auto;
	fi;
}

#action_cycle_powersave () { :; }

_Powersave ()
{
	# min max mov

	MIN_BACKLIGHT_PERCENT=75
	MAX_BACKLIGHT_PERCENT=100

	local powersave_state_file=/var/tmp/powersave
	[[ -e $powersave_state_file ]] && local current_powersave_state=$(cat $powersave_state_file) || current_powersave_state=max
	
	# change to new state
	case $current_powersave_state in
		min) new_powersave_state=max ;;
		#max) new_powersave_state=mov ;;
		*)   new_powersave_state=min ;;
	esac

	# use new state value or override with argument
	powersave_state=${1:-$new_powersave_state}

	# change powersave states
	case $powersave_state in
		min)
			target_cpu_governor=powersave
			target_brute_force=auto
			target_wlan_power_save=on
			dpms_seconds=60
			backlight_percent=75
			Log "POWER MODE: MIN (full powersave)"
		;;
		max)
			#target_cpu_governor=ondemand
			target_cpu_governor=performance
			target_brute_force=on
			target_wlan_power_save=off
			dpms_seconds=600
			backlight_percent=100
			Log "POWER MODE: MAX (no powersave)"
		;;
	esac

	# CPU
	#for cpupath in /sys/devices/systems/cpu/cpu?; do echo -n $target_cpu_governor >"$cpupath/cpufreq/scaling_governor"; done
	for cpu in 0 1 2 3; do cpufreq-set -c $cpu -g $target_cpu_governor; \
	Log "POWERSAVE-$powersave_state cpu $cpu set to $target_cpu_governor"; done

	# BRUTE FORCE SYS TREE
	for _control in /sys/bus/{pci,spi,i2c}/devices/*/power/control; do echo $target_brute_force > $_control && Log "POWERSAVE SET: $_control"|| true; done
	for _control in /sys/bus/usb/devices/*/power/control; do echo $target_brute_force > $_control && Log "POWERSAVE SET: $_control"|| true; done

	# NETWORK
	iw wlan0 set power_save $target_wlan_power_save && Log "POWERSAVE-$powersave_state wifi adapter powersave $target_wlan_power_save"

	# DISPLAY
	# graphics powersave taken care of in brute force above
	
	# DPMS
	xset dpms 0 0 $dpms_seconds 2>/dev/null && Log "POWERSAVE-$powersave_state DPMS timeout set to $dpms_seconds"

	# read current/max brightness values
	sys_current_brightness=$(cat /sys/class/backlight/acpi_video0/actual_brightness)
	sys_full_brightness=$(cat /sys/class/backlight/acpi_video0/max_brightness)

	# set target
	target_brightness=$((($backlight_percent*$sys_full_brightness)/100))

	if [[ $sys_current_brightness > $target_brightness ]]
	then
		# reduce
		Log "REDUCE BACKLIGHT from $sys_current_brightness to $target_brightness"
		for (( b=$sys_current_brightness; b>=$target_brightness; b--)); do echo -n $b > /sys/class/backlight/acpi_video0/brightness; sleep 0.015; done
	else
		# increase
		Log "INCREASE BACKLIGHT from $sys_current_brightness to $target_brightness"
		for (( b=$sys_current_brightness; b<=$target_brightness; b++)); do echo -n $b > /sys/class/backlight/acpi_video0/brightness; sleep 0.015; done
	fi

	# save state
	echo -n $powersave_state > $powersave_state_file
}

_Cycle_Display ()   { :; }
_Cycle_Input ()     { :; }
_Autolight ()
{ 
	return;
	Log;
	killall calise
	calise --no-gui --verbosity=0 --gap 0.1 --cam=/dev/video0 --steps=15 --delta=0.50 --offset=0.25 --bl-offset=6 --invert --profile=/etc/calise.conf &
	(sleep 3 && killall calise) &
}

_Annotate ()
{
	_scrot_cmd="xdotool key "Ctrl+F9" && \
		    chmod 644 \$f && \
		    chown $USER:users \$f && \
		    mv \$f /home/$USER/tmp/screenshots/ && \
		    su -c \"google picasa post 'Screenshots' /home/$USER/tmp/screenshots/\$f\" es"
	case $1 in
	    start)
		xdotool key "Shift+F9" "F9";
		;;
	    finish)
		[[ -d "/home/$USER/tmp/screenshots" ]] && mkdir -p "/home/$USER/tmp/screenshots"
		#scrot "$(hostname)_%Y-%m-%d-%T_\$wx\$h.png" -e "chmod 644 \$f && chown $USER:users \$f && mv \$f /home/$USER/tmp/screenshots/" &> /tmp/dump
		su $USER
		scrot "$(hostname)_%Y-%m-%d-%T_\$wx\$h.png" -e "$_scrot_cmd"
		exit
		;;
	esac
}

# TODO: this isn't working...
_Mic () { /usr/bin/amixer sset Capture toggle; Log "AUDIO: MIC MUTE"; }

_Boot_Events ()
{ 
	[[ $(cat /sys/class/power_supply/AC/online) > 0 ]] && _Powersave max || _Powersave min # power state?
	[[ -e "/var/tmp/bt" ]] && eval "rfkill $(cat /var/tmp/bt) bluetooth"
	exit
}

# START EXECUTION
[[ "$*" == "boot" ]] && _Boot_Events
Map_Event_Codes "$*"
