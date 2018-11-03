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
VERSION=0.09
# WORKING_DIR=$(getpathname hist)
WORKING_DIR=/s/sirsi/Unicorn/EPLwork/anisbet/Dev/HistLogsDB
# TMP=$(getpathname tmp)
TMP=/s/sirsi/Unicorn/EPLwork/anisbet/Dev/HistLogsDB
START_MILESTONE=13
DBASE=$WORKING_DIR/quad.db
CKOS_TABLE=ckos
ITEM_TABLE=item
USER_TABLE=user
TMP_FILE=$TMP/quad.tmp
ITEM_LST=/s/sirsi/Unicorn/EPLwork/cronjobscripts/RptNewItemsAndTypes/new_items_types.tbl
######### schema ###########
# CREATE TABLE ckos (
    # Date INTEGER PRIMARY KEY NOT NULL,
    # Branch CHAR(8),
    # ItemId INTEGER,
    # UserId INTEGER
# );
# CREATE TABLE item (
    # Created INTEGER NOT NULL,
    # CKey INTEGER NOT NULL,
    # Seq INTEGER NOT NULL,
    # Copy INTEGER NOT NULL,
    # Id INTEGER,
    # Type CHAR(20)
# );
# CREATE TABLE user (
    # Created INTEGER NOT NULL,
    # Key INTEGER PRIMARY KEY NOT NULL,
    # Id INTEGER NOT NULL,
    # Profile CHAR(20)
# );
######### schema ###########
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
    printf " Creates and maintains a quick and dirty database to speed up common lookups.\n" >&2
    printf " \n" >&2
    printf " Tables must exists before you can put data into them. Use -B to ensure tables\n" >&2
    printf " when rebuilding the database, or after using -R to reset a table.\n" >&2
    printf " \n" >&2
    printf " It is safe to re-run a load on a loaded table since all sql statments are INSERT OR IGNORE.\n" >&2
    printf " \n" >&2
    printf " -B Build any tables that doesn't exist in the database.\n" >&2
    printf "    This function always checks if a table has data before\n" >&2
    printf "    attempting to create a table. It never drops tables so is safe\n" >&2
    printf "    to run. See -R to reset a nameed table.\n" >&2
    printf " -c Populate $CKOS_TABLE table with data from today's history file.\n" >&2
    printf " -C Populate $CKOS_TABLE table with data starting $START_MILESTONE months ago.\n" >&2
    printf "    $START_MILESTONE is hard coded in the script and can be changed but a -R\n" >&2
    printf "    reset will be required to drop the table then the appropriate switch to\n" >&2
    printf "    repopulate it.\n" >&2
    printf " -i Populate $ITEM_TABLE table with items created today (since yesterday).\n" >&2
    printf " -I Populate $ITEM_TABLE table with data from as far back as $ITEM_LST \n" >&2
    printf "    goes. The data read from that file is compiled nightly by rptnewitemsandtypes.sh.\n" >&2
    printf "    Reset will drop the table in $DBASE and leave the original data untouched.\n" >&2
    printf " -u Populate $USER_TABLE table with users created today via ILS API.\n" >&2
    printf " -U Populate $USER_TABLE table with data for all users in the ILS.\n" >&2
    printf "    The switch will first drop the existing table and reload data via ILS API.\n" >&2
    printf " -s Show all the table names.\n" >&2
    printf " -R{table} Drops a named table.\n" >&2
    printf " -x Prints help message and exits.\n" >&2
    printf " \n" >&2
    printf "   Version: %s\n" $VERSION >&2
    exit 1
}

# Creates the checkouts table.
# param:  none
create_ckos_table()
{
    # The checkout table format.
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

# Creates the user table.
# param:  none
create_user_table()
{
    # The user table is quite dynamic so just keep most stable information. The rest can be looked up dynamically.
    # I don't want to spend a lot of time updating this table.
    sqlite3 $DBASE <<END_SQL
CREATE TABLE $USER_TABLE (
    Created INTEGER NOT NULL,
    Key INTEGER PRIMARY KEY NOT NULL,
    Id INTEGER NOT NULL,
    Profile CHAR(20)
);
END_SQL
}

# Creates the item table.
# param:  none
create_item_table()
{
    # Same with the item table. As time goes on this table will hold information that is not available anywhere else.
    # It's scooped in from new_items_types.tbl
    # 2117235|1|1|31000045107060|ILL-BOOK|20181101|
    # Convert to:
    # 20181101000000|2117235|1|1|31000045107060|ILL-BOOK|
    sqlite3 $DBASE <<END_SQL
CREATE TABLE $ITEM_TABLE (
    Created INTEGER NOT NULL,
    CKey INTEGER NOT NULL,
    Seq INTEGER NOT NULL,
    Copy INTEGER NOT NULL,
    Id INTEGER,
    Type CHAR(20)
);
END_SQL
}

# This function builds the standard tables used for lookups. Since the underlying 
# database is a simple sqlite3 database, and there is no true date type we will be
# storing all date values as ANSI dates (YYYYMMDDHHMMSS).
# You must exend this function for each new table you wish to add.
ensure_tables()
{
    if [ -s "$DBASE" ]; then   # If the database doesn't exists and isn't empty.
        # Test each table so we don't create tables that exist.
        ## CKOS table
        if echo "SELECT COUNT(*) FROM $CKOS_TABLE;" | sqlite3 $DBASE 2>/dev/null >/dev/null; then
            echo "confirmed $CKOS_TABLE exists..." >&2
        else
            create_ckos_table
        fi # End of creating item table.
        ## Item table
        if echo "SELECT COUNT(*) FROM $ITEM_TABLE;" | sqlite3 $DBASE 2>/dev/null >/dev/null; then
            echo "confirmed $ITEM_TABLE exists..." >&2
        else
            create_item_table
        fi # End of creating item table.
        ## User table
        if echo "SELECT COUNT(*) FROM $USER_TABLE;" | sqlite3 $DBASE 2>/dev/null >/dev/null; then
            echo "confirmed $USER_TABLE exists..." >&2
        else
            create_user_table
        fi # End of creating user table.
    else
        create_ckos_table
        create_item_table
        create_user_table
    fi
}

# Drops all the standard tables.
# param:  name of the table to drop.
reset_table()
{
    local table=$1
    if [ -s "$DBASE" ]; then   # If the database is not empty.
        echo "DROP TABLE $table;" | sqlite3 $DBASE
        echo 0
    else
        echo "$DBASE doesn't exist or is empty. Nothing to drop." >&2
        echo 1
    fi
}

# Fills the checkout table with data from a given date.
get_cko_data()
{
    ######### schema ###########
    # CREATE TABLE ckos (
        # Date INTEGER PRIMARY KEY NOT NULL,
        # Branch CHAR(8),
        # ItemId INTEGER,
        # UserId INTEGER
    # );
    ######### schema ###########
    local table=$CKOS_TABLE
    local start_date=$1
    local end_date=$(transdate -d-0)
    ## Use hist reader for date ranges, it doesn't do single days just months.
    echo "["`date +'%Y-%m-%d %H:%M:%S'`"] reading history logs." >&2
    histreader.sh -D"E20|FEEPL|UO|NQ" -CCVF -d"$start_date $end_date" >$TMP_FILE.$table.0
    # E201811011434461485R |FEEPLLHL|NQ31221117944590|UOLHL-DISCARD4
    # E201811011434501844R |FEEPLWMC|UO21221000876505|NQ31221118938062
    # E201811011434571698R |FEEPLLHL|NQ31221101053390|UO21221025137388
    # E201811011435031698R |FEEPLLHL|NQ31221108379350|UO21221025137388
    echo "["`date +'%Y-%m-%d %H:%M:%S'`"] preparing sql statements data." >&2
    # Re order the output so the Item id appears before the user id because it isn't consistently logged in order.
    cat $TMP_FILE.$table.0 | pipe.pl -gc2:UO -i -oc0,c1,c3,c2 | pipe.pl -m"c0:INSERT OR IGNORE INTO $CKOS_TABLE (Date\,Branch\,ItemId\,UserId) VALUES (_##############_,c1:\"__############\",c2:\"__####################\",c3:\"__####################\");" -h',' -C"num_cols:width4-4" -tany -TCHUNKED:"BEGIN=BEGIN TRANSACTION;,SKIP=10000.COMMIT;BEGIN TRANSACTION;,END=COMMIT;" >$TMP_FILE.$table.sql
    echo "["`date +'%Y-%m-%d %H:%M:%S'`"] loading data." >&2
    cat $TMP_FILE.$table.sql | sqlite3 $DBASE
    rm $TMP_FILE.$table.0
    rm $TMP_FILE.$table.sql
}

# Fills the checkout table with data from a given date.
get_cko_data_today()
{
    ######### schema ###########
    # CREATE TABLE ckos (
        # Date INTEGER PRIMARY KEY NOT NULL,
        # Branch CHAR(8),
        # ItemId INTEGER,
        # UserId INTEGER
    # );
    ######### schema ###########
    ## Use hist reader for date ranges, it doesn't do single days just months.
    local table=$CKOS_TABLE
    echo "["`date +'%Y-%m-%d %H:%M:%S'`"] reading history logs." >&2
    egrep -e "CVF" `getpathname hist`/`transdate -d-0`.hist | pipe.pl -W'\^' -gany:"E20|FEEPL|UO|NQ" -5 2>$TMP_FILE.$table.0 >/dev/null
    # E201811011514461108R |FEEPLWMC|NQ31221115247780|UO21221026682705
    # E201811011514470805R |FEEPLMLW|NQ31221116084117|UOMLW-DISCARD-NOV
    # E201811011514511108R |FEEPLWMC|NQ31221115406774|UO21221026682705
    # E201811011514521863R |FEEPLWHP|UO21221026176872|NQ31221115633690
    echo "["`date +'%Y-%m-%d %H:%M:%S'`"] preparing sql statements data." >&2
    # Re order the output so the Item id appears before the user id because it isn't consistently logged in order.
    cat $TMP_FILE.$table.0 | pipe.pl -gc2:UO -i -oc0,c1,c3,c2 | pipe.pl -m"c0:INSERT OR IGNORE INTO $CKOS_TABLE (Date\,Branch\,ItemId\,UserId) VALUES (_##############_,c1:\"__############\",c2:\"__####################\",c3:\"__####################\");" -h',' -C"num_cols:width4-4" -tany -TCHUNKED:"BEGIN=BEGIN TRANSACTION;,SKIP=10000.COMMIT;BEGIN TRANSACTION;,END=COMMIT;" >$TMP_FILE.$table.sql
    echo "["`date +'%Y-%m-%d %H:%M:%S'`"] loading data." >&2
    cat $TMP_FILE.$table.sql | sqlite3 $DBASE
    rm $TMP_FILE.$table.0
    rm $TMP_FILE.$table.sql
}

# Fills the user table with data from a given date.
get_user_data()
{
    ######### schema ###########
    # CREATE TABLE user (
        # Created INTEGER NOT NULL,
        # Key INTEGER PRIMARY KEY NOT NULL,
        # Id INTEGER NOT NULL,
        # Profile CHAR(20)
    # );
    ######### schema ###########
    local table=$USER_TABLE
    local start_date=$1
    ## Get this from API seluser.
    echo "["`date +'%Y-%m-%d %H:%M:%S'`"] reading user data." >&2
    seluser -ofUBp 2>/dev/null >$TMP_FILE.$table.0
    # 20180828|1544339|21221027463253|EPL_STAFF|
    # 20180906|1548400|21221027088076|EPL_STAFF|
    # 20180929|1558978|21221026819570|EPL_STAFF|
    echo "["`date +'%Y-%m-%d %H:%M:%S'`"] preparing sql statements data." >&2
    # Re order the output so the Item id appears before the user id because it isn't consistently logged in order.
    # Pad the end of the time stamp with 000000.
    cat $TMP_FILE.$table.0 | pipe.pl -pc0:'-14.0' -oremaining | pipe.pl -m"c0:INSERT OR IGNORE INTO $USER_TABLE (Date\,Key\,Id\,Profile) VALUES (#,c1:#,c2:#,c3:\"####################\");" -h',' -tany -TCHUNKED:"BEGIN=BEGIN TRANSACTION;,SKIP=10000.COMMIT;BEGIN TRANSACTION;,END=COMMIT;" >$TMP_FILE.$table.sql
    echo "["`date +'%Y-%m-%d %H:%M:%S'`"] loading data." >&2
    cat $TMP_FILE.$table.sql | sqlite3 $DBASE
    # rm $TMP_FILE.$table.0
    # rm $TMP_FILE.$table.sql
}

# Fills the user table with data from a given date.
get_user_data_today()
{
    ######### schema ###########
    # CREATE TABLE user (
        # Created INTEGER NOT NULL,
        # Key INTEGER PRIMARY KEY NOT NULL,
        # Id INTEGER NOT NULL,
        # Profile CHAR(20)
    # );
    ######### schema ###########
    local table=$USER_TABLE
    local start_date=$(transdate -d-1) # Created after yesterday.
    ## Get this from API seluser.
    echo "["`date +'%Y-%m-%d %H:%M:%S'`"] reading user data." >&2
    seluser -f">$start_date" -ofUBp 2>/dev/null >$TMP_FILE.$table.0
    # 20180828|1544339|21221027463253|EPL_STAFF|
    # 20180906|1548400|21221027088076|EPL_STAFF|
    # 20180929|1558978|21221026819570|EPL_STAFF|
    echo "["`date +'%Y-%m-%d %H:%M:%S'`"] preparing sql statements data." >&2
    # Re order the output so the Item id appears before the user id because it isn't consistently logged in order.
    # Pad the end of the time stamp with 000000.
    cat $TMP_FILE.$table.0 | pipe.pl -pc0:'-14.0' -oremaining | pipe.pl -m"c0:INSERT OR IGNORE INTO $USER_TABLE (Date\,Key\,Id\,Profile) VALUES (#,c1:#,c2:#,c3:\"####################\");" -h',' -tany -TCHUNKED:"BEGIN=BEGIN TRANSACTION;,SKIP=10000.COMMIT;BEGIN TRANSACTION;,END=COMMIT;" >$TMP_FILE.$table.sql
    echo "["`date +'%Y-%m-%d %H:%M:%S'`"] loading data." >&2
    cat $TMP_FILE.$table.sql | sqlite3 $DBASE
    # rm $TMP_FILE.$table.0
    # rm $TMP_FILE.$table.sql
}

# Fills the item table with data from a given date.
get_item_data()
{
    ######### schema ###########
    # CREATE TABLE item (
        # Created INTEGER NOT NULL,
        # CKey INTEGER NOT NULL,
        # Seq INTEGER NOT NULL,
        # Copy INTEGER NOT NULL,
        # Id INTEGER,
        # Type CHAR(20)
    # );
    ######### schema ###########
    ## Get this from the file: /s/sirsi/Unicorn/EPLwork/cronjobscripts/RptNewItemsAndTypes/new_items_types.tbl
    # 476|4|1|31221107445806|BOOK|20170104|
    # 514|122|1|31221114386118|PERIODICAL|20150407|
    # 514|156|1|31221214849072|PERIODICAL|20160426|
    # 514|169|1|31221215132478|PERIODICAL|20160901|
    # 514|173|1|31221215167086|PERIODICAL|20161019|
    # 567|25|1|31221214643954|PERIODICAL|20151118|
    local table=$ITEM_TABLE
    echo "["`date +'%Y-%m-%d %H:%M:%S'`"] reading item data from $ITEM_LST." >&2
    if [ -s "$ITEM_LST" ]; then
        echo "["`date +'%Y-%m-%d %H:%M:%S'`"] preparing sql statements data." >&2
        # Re order the output so the Item id appears before the user id because it isn't consistently logged in order.
        # Pad the end of the time stamp with 000000.
        cat $ITEM_LST | pipe.pl -pc5:'-14.0' -oc5,remaining | pipe.pl -m"c0:INSERT OR IGNORE INTO $ITEM_TABLE (Created\,CKey\,Seq\,Copy\,Id\,Type) VALUES (#,c1:#,c2:#,c3:#,c4:#,c5:\"####################\");" -h',' -tany -TCHUNKED:"BEGIN=BEGIN TRANSACTION;,SKIP=10000.COMMIT;BEGIN TRANSACTION;,END=COMMIT;" >$TMP_FILE.$table.sql
        echo "["`date +'%Y-%m-%d %H:%M:%S'`"] loading data." >&2
        cat $TMP_FILE.$table.sql | sqlite3 $DBASE
        # rm $TMP_FILE.$table.sql
    else
        echo "**error: couldn't find file $ITEM_LST for historical item."
        exit 1
    fi
}

# Fills the item table with data from a given date.
get_item_data_today()
{
    ######### schema ###########
    # CREATE TABLE item (
        # Created INTEGER NOT NULL,
        # CKey INTEGER NOT NULL,
        # Seq INTEGER NOT NULL,
        # Copy INTEGER NOT NULL,
        # Id INTEGER,
        # Type CHAR(20)
    # );
    ######### schema ###########
    ## Get this from selitem -f">`transdate -d-1`" -oIBtf | pipe.pl -tc3
    local table=$ITEM_TABLE
    local today=$(transdate -d-1)
    echo "["`date +'%Y-%m-%d %H:%M:%S'`"] reading item data from today." >&2
    selitem -f">$today" -oIBtf 2>/dev/null | pipe.pl -tc3 >$TMP_FILE.$table.0
    # 2117336|1|1|2117336-1001|BOOK|20181102|
    # 2117337|1|1|2117337-1001|BOOK|20181102|
    # 2117338|1|1|31000040426630|ILL-BOOK|20181102|
    # 2117340|1|1|39335027163505|ILL-BOOK|20181102|
    echo "["`date +'%Y-%m-%d %H:%M:%S'`"] preparing sql statements data." >&2
    # Re order the output so the Item id appears before the user id because it isn't consistently logged in order.
    # Pad the end of the time stamp with 000000.
    cat $TMP_FILE.$table.0 | pipe.pl -pc5:'-14.0' -oc5,remaining | pipe.pl -m"c0:INSERT OR IGNORE INTO $ITEM_TABLE (Created\,CKey\,Seq\,Copy\,Id\,Type) VALUES (#,c1:#,c2:#,c3:#,c4:#,c5:\"####################\");" -h',' -tany -TCHUNKED:"BEGIN=BEGIN TRANSACTION;,SKIP=10000.COMMIT;BEGIN TRANSACTION;,END=COMMIT;" >$TMP_FILE.$table.sql
    echo "["`date +'%Y-%m-%d %H:%M:%S'`"] loading data." >&2
    cat $TMP_FILE.$table.sql | sqlite3 $DBASE
    # rm $TMP_FILE.$table.0
    # rm $TMP_FILE.$table.sql
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
while getopts ":BcCiIR:suUx" opt; do
  case $opt in
    B)	echo "["`date +'%Y-%m-%d %H:%M:%S'`"] building missing tables." >&2
        ensure_tables
        ;;
    c)	echo "-c triggered to add today's data to checkouts table." >&2
        echo "["`date +'%Y-%m-%d %H:%M:%S'`"] adding checkout table from today." >&2
        get_cko_data_today
        ;;
    C)	echo "-C triggered to reload historical checkout data." >&2
        start_date=$(transdate -m-$START_MILESTONE)
        echo "["`date +'%Y-%m-%d %H:%M:%S'`"] droping checkout table." >&2
        reset_table $CKOS_TABLE
        ensure_tables
        echo "["`date +'%Y-%m-%d %H:%M:%S'`"] rebuilding checkout table from data starting $start_date." >&2
        get_cko_data $start_date
        ;;
    i)	echo "-i triggered to add today's item data to the item table." >&2
        echo "["`date +'%Y-%m-%d %H:%M:%S'`"] adding item data from today." >&2
        get_item_data_today
        ;;
    I)	echo "-I triggered to reload historical item data loaded on ILS." >&2
        start_date=$(transdate -m-$START_MILESTONE)
        echo "["`date +'%Y-%m-%d %H:%M:%S'`"] droping item table." >&2
        reset_table $ITEM_TABLE
        ensure_tables
        echo "["`date +'%Y-%m-%d %H:%M:%S'`"] rebuilding item table with data on file." >&2
        get_item_data
        ;;
    R)	echo "-R triggered to reset table $OPTARG." >&2
        ANSWER=$(confirm "Drop table $OPTARG ")
        if [ "$ANSWER" == "1" ]; then
            exit 1
        fi
        reset_table $OPTARG
        ensure_tables
        ;;
    s)	echo "-s triggered to show tables." >&2
        echo "$CKOS_TABLE" >&2
        echo "$ITEM_TABLE" >&2
        echo "$USER_TABLE" >&2
        ;;
    u)	echo "-u triggered to add users created today." >&2
        echo "["`date +'%Y-%m-%d %H:%M:%S'`"] adding users created from today." >&2
        get_user_data_today
        ;;
    U)  echo "-U triggered to reload user table data." >&2
        start_date=$(transdate -m-$START_MILESTONE)
        echo "["`date +'%Y-%m-%d %H:%M:%S'`"] droping user table." >&2
        reset_table $USER_TABLE
        ensure_tables
        echo "["`date +'%Y-%m-%d %H:%M:%S'`"] rebuilding user table from API starting $start_date." >&2
        get_user_data $start_date
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
