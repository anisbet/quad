#!/bin/bash
###############################################################################
#
# Creates and maintains a quick and dirty dabase of commonly asked for hist data
#
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
VERSION=0.01
# WORKING_DIR=$(getpathname hist)
WORKING_DIR=/s/sirsi/Unicorn/EPLwork/anisbet/Dev/HistLogsDB
# TMP=$(getpathname tmp)
TMP=/s/sirsi/Unicorn/EPLwork/anisbet/Dev/HistLogsDB
MONTHS_AGO=12
DBASE=$WORKING_DIR/qad.db
CKOS_TABLE=ckos
TMP_FILE=$TMP/qad.tmp

if ! which sqlite3 2>/dev/null >/dev/null; then
    echo "**error sqlite3 not available on this machine!" >&2
    exit 1
fi
cd $WORKING_DIR
###############################################################################
# Display usage message.
# param:  none
# return: none
usage()
{
	printf "Usage: %s [-option]\n" "$0" >&2
	printf " Creates and maintains a Hist database for quick lookups.\n" >&2
	printf "   Version: %s\n" $VERSION >&2
	exit 1
}

# This function builds the standard tables used for lookups. Since the underlying 
# database is a simple sqlite3 database, and there is no true date type we will be
# storing all date values as ANSI dates (YYYYMMDDHHMMSS).
# The standard tables are currently ckos.
build_tables()
{
    if [ -s "$DBASE" ]; then   # If the database exists and isn't empty.
        echo "DROP TABLE $CKOS_TABLE;" | sqlite3 $DBASE
        return
    fi
    # E201811010812311867R ^S46CVFWSIPCHKMNA1^FEEPLMNA^FFSIPCHK^FcNONE^FDSIPCHK^dC6^UO21221024503945^NQ31221113297472^ObY^OeY^^O
    sqlite3 $DBASE <<END_SQL
CREATE TABLE $CKOS_TABLE (
    Date INTEGER PRIMARY KEY NOT NULL,
    Branch CHAR(8),
    ItemId INTEGER,
    UserId INTEGER
);
END_SQL
}

# Drops all the standard tables.
# param:  name of the table to drop.
reset_table()
{
    local table=$1
    if which sqlite3 2>/dev/null >/dev/null; then
        if [ -s "$DBASE" ]; then   # If the database is not empty.
            echo "DROP TABLE $table;" | sqlite3 $DBASE
            echo 0
        else
            echo "$DBASE doesn't exist or is empty. Nothing to drop." >&2
            echo 1
        fi
    else
        echo "**error sqlite3 not available on this machine!" >&2
        echo 1
    fi
}

# Fills the checkout table with data from a given date.
get_cko_data()
{
    local start_date=$1
    local end_date=$(transdate -d-0)
    ## Use hist reader for date ranges, it doesn't do single days just months.
    echo "["`date +'%Y-%m-%d %H:%M:%S'`"] reading history logs." >&2
    histreader.sh -D"E20|FEEPL|UO|NQ" -CCVF -d"$start_date $end_date" >$TMP_FILE.0
    # E201811011434461485R |FEEPLLHL|NQ31221117944590|UOLHL-DISCARD4
    # E201811011434501844R |FEEPLWMC|UO21221000876505|NQ31221118938062
    # E201811011434571698R |FEEPLLHL|NQ31221101053390|UO21221025137388
    # E201811011435031698R |FEEPLLHL|NQ31221108379350|UO21221025137388
    echo "["`date +'%Y-%m-%d %H:%M:%S'`"] preparing sql statements data." >&2
    # Add the start of the command to bulk add transactions to sqlite3.
    echo "BEGIN TRANSACTION;" >$TMP_FILE.sql
    # Re order the output so the Item id appears before the user id because it isn't consistently logged in order.
    cat $TMP_FILE.0 | pipe.pl -gc2:UO -i -oc0,c1,c3,c2 | pipe.pl -m"c0:INSERT OR IGNORE INTO $CKOS_TABLE (Date\,Branch\,ItemId\,UserId) VALUES (_##############_,c1:\"__############\",c2:\"__####################\",c3:\"__####################\");" -h',' -C"num_cols:width4-4" >>$TMP_FILE.sql
    echo "COMMIT;" -tany >>$TMP_FILE.sql
    echo "["`date +'%Y-%m-%d %H:%M:%S'`"] loading data." >&2
    cat $TMP_FILE.sql | sqlite3 $DBASE
    rm $TMP_FILE.0
    rm $TMP_FILE.sql
}

# Fills the checkout table with data from a given date.
get_cko_data_today()
{
    ## Use hist reader for date ranges, it doesn't do single days just months.
    echo "["`date +'%Y-%m-%d %H:%M:%S'`"] reading history logs." >&2
    egrep -e "CVF" `getpathname hist`/`transdate -d-0`.hist | pipe.pl -W'\^' -gany:"E20|FEEPL|UO|NQ" -5 2>$TMP_FILE.0 >/dev/null
    # E201811011514461108R |FEEPLWMC|NQ31221115247780|UO21221026682705
    # E201811011514470805R |FEEPLMLW|NQ31221116084117|UOMLW-DISCARD-NOV
    # E201811011514511108R |FEEPLWMC|NQ31221115406774|UO21221026682705
    # E201811011514521863R |FEEPLWHP|UO21221026176872|NQ31221115633690
    echo "["`date +'%Y-%m-%d %H:%M:%S'`"] preparing sql statements data." >&2
    # Add the start of the command to bulk add transactions to sqlite3.
    echo "BEGIN TRANSACTION;" >$TMP_FILE.sql
    # Re order the output so the Item id appears before the user id because it isn't consistently logged in order.
    cat $TMP_FILE.0 | pipe.pl -gc2:UO -i -oc0,c1,c3,c2 | pipe.pl -m"c0:INSERT OR IGNORE INTO $CKOS_TABLE (Date\,Branch\,ItemId\,UserId) VALUES (_##############_,c1:\"__############\",c2:\"__####################\",c3:\"__####################\");" -h',' -C"num_cols:width4-4" -tany >>$TMP_FILE.sql
    echo "COMMIT;" >>$TMP_FILE.sql
    echo "["`date +'%Y-%m-%d %H:%M:%S'`"] loading data." >&2
    cat $TMP_FILE.sql | sqlite3 $DBASE
    rm $TMP_FILE.0
    rm $TMP_FILE.sql
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
while getopts ":BcCx" opt; do
  case $opt in
    B)	echo "["`date +'%Y-%m-%d %H:%M:%S'`"] building tables." >&2
        build_tables
        ;;
	c)	echo "-c triggered to add today's data to checkouts table.\n" >&2
        echo "["`date +'%Y-%m-%d %H:%M:%S'`"] adding checkout table from today." >&2
        get_cko_data_today
		;;
    C)	echo "-C triggered to reload historical checkout data.\n" >&2
        start_date=$(transdate -m-$MONTHS_AGO)
        echo "["`date +'%Y-%m-%d %H:%M:%S'`"] droping checkout table." >&2
        reset_table $CKOS_TABLE
        echo "["`date +'%Y-%m-%d %H:%M:%S'`"] rebuilding checkout table from data starting $start_date." >&2
        get_cko_data $start_date
		;;
	x)	usage
		;;
	\?)	echo "Invalid option: -$OPTARG" >&2
		usage
		;;
  esac
done
exit 0
# EOF
