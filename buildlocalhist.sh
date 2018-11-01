#!/bin/bash
###############################################################################
#
# Bash shell script for project buildlocalhist
#<one line to give the program's name and a brief idea of what it does.>
#    Copyright (C) 2018  Andrew Nisbet, Edmonton Public Library
# The Edmonton Public Library respectfully acknowledges that we sit on
# Treaty 6 territory, traditional lands of First Nations and Metis people.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
# MA 02110-1301, USA.
#
###############################################################################

# Environment setup required by cron to run script because its daemon runs
# without assuming any environment settings and we need to use sirsi's.
#######################################################################
# ***           Edit these to suit your environment               *** #
source /s/sirsi/Unicorn/EPLwork/cronjobscripts/setscriptenvironment.sh
###############################################################################
VERSION=0
TMP=$(getpathname tmp)
WORKING_DIR=$(pwd)
###############################################################################
# Display usage message.
# param:  none
# return: none
usage()
{
	printf "Usage: %s [-option]\n" "$0" >&2
	printf " Description of what the application does, and how to use it.\n" >&2
	printf "   Version: %s\n" $VERSION >&2
	exit 1
}

# Asks if user would like to do what the message says.
# param:  message string.
# return: 0 if the answer was yes and 1 otherwise.
confirm()
{
	if [ -z "$1" ]; then
		echo "** error, confirm_yes requires a message." >&2
		exit 1
	fi
	local message="$1"
	echo "$message? y/[n]: " >&2
	read answer
	case "$answer" in
		[yY])
			echo "yes selected." >&2
			echo 0
			;;
		*)
			echo "no selected." >&2
			echo 1
			;;
	esac
	echo 1
}

# Argument processing.
while getopts ":a:x" opt; do
  case $opt in
	a)	echo "-a triggered with '$OPTARG'\n" >&2
		;;
	x)	usage
		;;
	\?)	echo "Invalid option: -$OPTARG" >&2
		usage
		;;
	:)	echo "Option -$OPTARG requires an argument." >&2
		usage
		;;
  esac
done
exit 0
# EOF
