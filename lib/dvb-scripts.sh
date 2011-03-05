#!/bin/sh

 ##############################################################################
 #                                                                            #
 # dvb-scripts                                                                #
 # Copyright (C) 2011 by Michal Hrusecky <Michal@Hrusecky.net>                #
 #                                                                            #
 # This program is free software: you can redistribute it and/or modify       #
 # it under the terms of the GNU General Public License as published by       #
 # the Free Software Foundation, either version 3 of the License, or          #
 # (at your option) any later version.                                        #
 #                                                                            #
 # This program is distributed in the hope that it will be useful,            #
 # but WITHOUT ANY WARRANTY; without even the implied warranty of             #
 # MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the              #
 # GNU General Public License for more details.                               #
 #                                                                            #
 # You should have received a copy of the GNU General Public License          #
 # along with this program.  If not, see <http://www.gnu.org/licenses/>.      #
 #                                                                            #
 ##############################################################################

# Some defaults

# Default configuration file
CONFIG_FILE=~/.dvb_scripts.conf
STATIONS_FILE=~/.tv_channels.conf

# Default user and password for remote interface
USER=dvb
PASS=dvb
ADAPTER=0

# IP to listen on (default localhost)
IP=127.0.0.1

# Load thing from configuration file
[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"

# Die
die() {
	echo "$*"
#	exit 1
}

# Get number of adapters
get_adapters() {
	ls -1 /dev/dvb | sed 's|^adapter||'
}

# Runs command on dvbstreamer
dvb_ctrl() {
	ADAPTER="$1"
	shift
	echo "$*" | dvbctrl -a "$ADAPTER" -u "$USER" -p "$PASS" -f -
}

# Checks whether dvbstreamer runs for every adapter
check_streamers() {
	for i in `get_adapters`; do
		if [ -z "`dvbctrl -a "$i" -u "$USER" -p "$PASS" help 2> /dev/null`" ]; then
			dvbstreamer -a "$i" -d -D -u "$USER" -p "$PASS" -n "Adapter $i - `cat /sys/class/dvb/dvb${i}.frontend0/device/manufacturer`" -i "$IP"
		fi
	done
}

# Returns list of channels
get_channels() {
	if [ \! -r "$STATIONS_FILE" ]; then
		TEMPFILE="`mktemp`"
		for i in `get_adapters`; do
			dvb_ctrl "$i" lsservices -id >> "$TEMPFILE"
		done
		sort -u "$TEMPFILE" > "$STATIONS_FILE"
		rm -f "$TEMPFILE"
	fi
	sed 's|.*"[[:blank:]]*\([^"]\+\)[[:blank:]]*|\1|' "$STATIONS_FILE"
}

# Returns id for channel
get_channel_id() {
	[ -z "$1" -o -z "`get_channels | grep "$1"`" ] && die "Invalid channel"
	grep "$1" "$STATIONS_FILE" | sed 's|^\([^[:blank:]]\+\)[[:blank:]].*|\1|' | head -n 1
}

# Finds suitable adapter
get_adapter_by_chan() {
	for i in `get_adapters`; do
		if [ -z "`dvb_ctrl $i current`" ]; then
			echo $i
			return
		fi
		if [ "`dvb_ctrl $i current | sed 's|[0-9a-f]\+\ :\ .*$||'`" = "`echo $1 | sed 's|[0-9a-f]\+$||'`" ]; then
			echo $i
			return
		fi
		if [ -z "`dvb_ctrl $i lssfs | grep -v '<Primary>'`" ]; then
			echo $i
			return
		fi
	done
	die "No free adapter!"
}

# Show streams and where do they go
list_streams() {
	for i in `get_adapters`; do
		for j in `dvb_ctrl $i lssfs`; do
			MRL="`dvb_ctrl $i getsfmrl $j | grep '^udp'`"
			[ "$MRL" ] && echo $j $MRL
		done
	done
}

# Find free port
get_port() {
	PORT=8000
	NEW_PORT="`list_streams | sed 's|.*:\([0-9]\+\)$|\1|' | sort -nr | head -n 1`"
	[ "$NEW_PORT" ] && PORT="$NEW_PORT"
	PORT="`expr $PORT + 1`"
	echo $PORT
}

# Stream one channel and returns the port
stream_channel() {
	CHAN_ID="`get_channel_id "$1"`"
	[ "$CHAN_ID" ] || return
	ADAPTER="`get_adapter_by_chan $CHAN_ID`"
	[ "$ADAPTER" ] || return
	PORT="`get_port`"
	ID_NAME="`echo "$1" | sed s'|[[:blank:]]||g'`"
	ID_NAME="$ID_NAME-`dvb_ctrl $ADAPTER lssfs | grep $ID_NAME | wc -l`"
	[ "$ID_NAME" ] || return
	[ "`dvb_ctrl $ADAPTER current`" ] || dvb_ctrl $ADAPTER select $CHAN_ID
	[ "`dvb_ctrl $ADAPTER current | sed 's|[0-9a-f]\+\ :\ .*$||'`" = "`echo $CHAN_ID | sed 's|[0-9a-f]\+$||'`" ] || dvb_ctrl $ADAPTER select $CHAN_ID
	dvb_ctrl $ADAPTER addsf $ID_NAME udp://$IP:$PORT
	dvb_ctrl $ADAPTER setsf $ID_NAME $CHAN_ID
}

# Stop streaming channel
stop_stream() {
	for i in `get_adapters`; do
		dvb_ctrl $i rmsf "$1"
	done
}

check_streamers

