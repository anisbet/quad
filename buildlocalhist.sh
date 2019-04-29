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
VERSION=0.90.1   # Add functions to remove indices and re-add where appropriate to work flow.
WORKING_DIR=/s/sirsi/Unicorn/EPLwork/cronjobscripts/Quad
TMP=$(getpathname tmp)
START_MILESTONE_MONTHS_AGO=16
# DBASE=$WORKING_DIR/quad.db
DBASE=$WORKING_DIR/test.db
CKOS_TABLE=ckos
ITEM_TABLE=item
USER_TABLE=user
CAT_TABLE=cat
TMP_FILE=$TMP/quad.tmp
ITEM_LST=/s/sirsi/Unicorn/EPLwork/cronjobscripts/RptNewItemsAndTypes/new_items_types.tbl
TRUE=0
FALSE=1
QUIET_MODE=$FALSE
# If you need to catch up with more than just yesterday's just change the '1'
# to the number of days back you need to go.
YESTERDAY=$(transdate -d-1)
TODAY=$(transdate -d-0)
######### schema ###########
# CREATE TABLE ckos (
    # Date INTEGER NOT NULL,
    # Branch CHAR(8),
    # ItemId INTEGER,
    # UserId INTEGER,
    # PRIMARY KEY (Date, ItemId)
# );
# CREATE INDEX idx_ckos_userid ON ckos (UserId);
# CREATE INDEX idx_ckos_itemid ON ckos (ItemId);
# CREATE INDEX idx_ckos_item_userid ON ckos (ItemId, UserId);
# CREATE TABLE item (
    # Created INTEGER NOT NULL,
    # CKey INTEGER NOT NULL,
    # Seq INTEGER NOT NULL,
    # Copy INTEGER NOT NULL,
    # Id CHAR(20) NOT NULL,
    # Type CHAR(20),
    # PRIMARY KEY (CKey, Id)
# );
# CREATE INDEX idx_item_ckey_itemid ON item (CKey, Id);
# CREATE INDEX idx_item_itemid ON item (Id);
# CREATE INDEX idx_item_type ON item (Type);
# CREATE TABLE user (
    # Created INTEGER NOT NULL,
    # Key INTEGER PRIMARY KEY NOT NULL,
    # Id CHAR(20) NOT NULL,
    # Profile CHAR(20)
# );
# CREATE INDEX idx_user_userid ON user (Id);
# CREATE INDEX idx_user_key ON user (Key);
# CREATE INDEX idx_user_profile ON user (Profile);
# CREATE TABLE catalog (
    # Created INTEGER NOT NULL,
    # CKey INTEGER PRIMARY KEY NOT NULL,
    # Tcn CHAR(20) NOT NULL,
    # Title CHAR(256) NOT NULL,
# );
# CREATE INDEX idx_cat_ckey ON cat (CKey);
# CREATE INDEX idx_cat_tcn ON cat (Tcn);
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
    cat << EOFU!
Usage: $0 [-option]
 Creates and maintains a quick and dirty database to speed up common lookups.

 Tables must exists before you can put data into them. Use -B to ensure tables
 when rebuilding the database, or after using -R to reset a table.
 
 Make sure you add command line settings before you request modification commands.
 That it, if you want to change the date for reloading ckos, the command line should
 read: buildlocalhist.sh -D20161201 -c

 It is safe to re-run a load on a loaded table since all sql statments are INSERT OR IGNORE.

 -a Updates all tables with data from $YESTERDAY. See -L for loading data.
 -A Rebuild the entire database by dropping all tables and creating all data.
    Takes about 1 hour. See -L for loading data.
 -B Build any tables that doesn't exist in the database.
    This function always checks if a table has data before
    attempting to create a table. It never drops tables so is safe
    to run. See -R to reset a nameed table.
 -c Create $CKOS_TABLE table data from today's history file, but does not load it.
    To do that see the -L switch, which you can run any time.
 -C Create $CKOS_TABLE table data starting $START_MILESTONE_MONTHS_AGO months ago.
    $START_MILESTONE_MONTHS_AGO is hard coded in the script and can be changed.
    A reset is automatically done before starting, and you will be asked to
    confirm before the old table is dropped. The load takes about 25 minutes for.
    a year's worth of data.
 -D{YYYYMMDD} Change the value of \$YESTERDAY. Normally it's set to transdate -d-0
    but allows you to set a catch-up date if the script hasn't run for a few days.
    It is safe to over estimate how far back to go since all inserts have a
    'or ignore' clause if they already exist.
    Used in conjunction with -a, -i, -g, -u, or -c. Ignored with all other flags.
 -g Populate $CAT_TABLE table with items created today (since yesterday).
 -G Create $CAT_TABLE table data from as far back as $START_MILESTONE_MONTHS_AGO
    The data read from catalog table in Symphony.
    Reset will drop the table in $DBASE and repopulate the table after confirmation.
 -i Populate $ITEM_TABLE table with items created today (since yesterday).
 -I Create $ITEM_TABLE table data from as far back as $ITEM_LST
    goes. The data read from that file is compiled nightly by rptnewitemsandtypes.sh.
    Reset will drop the table in $DBASE and repopulate the table after confirmation.
 -L Load any sql files in the current directory. Removes them as it goes.
 -u Populate $USER_TABLE table with users created today via ILS API.
 -U Populate $USER_TABLE table with data for all users in the ILS.
    The switch will first drop the existing table and reload data via ILS API.
 -s Show all the table names.
 -q Set quiet mode. Suppresses interactive confirmation of actions.
 -r .
 -R{table} Drops and recreates a named table, inclding indices.
 -x Prints help message and exits.
 -X{table} Adds the indices to the argument tables if it exists.

   Version: $VERSION
EOFU!
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
    Date INTEGER NOT NULL,
    Branch CHAR(8),
    ItemId CHAR(20) NOT NULL,
    UserId CHAR(20) NOT NULL,
    PRIMARY KEY (Date, ItemId)
);
END_SQL
}

# Creates the ckeckout table's indices.
# param:  none
create_ckos_indices()
{
    # The checkout table format.
    # E201811010812311867R ^S46CVFWSIPCHKMNA1^FEEPLMNA^FFSIPCHK^FcNONE^FDSIPCHK^dC6^UO21221024503945^NQ31221113297472^ObY^OeY^^O
    sqlite3 $DBASE <<END_SQL
CREATE INDEX idx_ckos_date ON ckos (Date);
CREATE INDEX idx_ckos_userid ON ckos (UserId);
CREATE INDEX idx_ckos_itemid ON ckos (ItemId);
CREATE INDEX idx_ckos_branch ON ckos (Branch);
CREATE INDEX idx_ckos_item_userid ON ckos (ItemId, UserId);
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
    Id CHAR(20) NOT NULL,
    Profile CHAR(20)
);
END_SQL
}

# Creates the indices for the user table.
# param:  none
create_user_indices()
{
    # The user table is quite dynamic so just keep most stable information. The rest can be looked up dynamically.
    # I don't want to spend a lot of time updating this table.
    sqlite3 $DBASE <<END_SQL
CREATE INDEX idx_user_userid ON $USER_TABLE (Id);
CREATE INDEX idx_user_key ON $USER_TABLE (Key);
CREATE INDEX idx_user_profile ON $USER_TABLE (Profile);
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
    Id CHAR(20) NOT NULL,
    Type CHAR(20),
    PRIMARY KEY (CKey, Id)
);
END_SQL
}

# Creates the item table indices.
# param:  none
create_item_indices()
{
    # Same with the item table. As time goes on this table will hold information that is not available anywhere else.
    # It's scooped in from new_items_types.tbl
    # 2117235|1|1|31000045107060|ILL-BOOK|20181101|
    # Convert to:
    # 20181101000000|2117235|1|1|31000045107060|ILL-BOOK|
    sqlite3 $DBASE <<END_SQL
CREATE INDEX idx_item_ckey_itemid ON item (CKey, Id);
CREATE INDEX idx_item_itemid ON item (Id);
CREATE INDEX idx_item_type ON item (Type);
END_SQL
}

# Creates the catalog table.
# param:  none
create_cat_table()
{
    ######### schema ###########
    # CREATE TABLE catalog (
    #   Created INTEGER NOT NULL,
    #   CKey INTEGER PRIMARY KEY NOT NULL,
    #   Tcn CHAR(20) NOT NULL,
    #   Title CHAR(256) NOT NULL
    # );
    ######### schema ###########
    # All this information is available in the ILS, but gets deleted over time.
    # Think before you drop this table in production, historical data is difficult to retreive.
    sqlite3 $DBASE <<END_SQL
CREATE TABLE $CAT_TABLE (
    Created INTEGER NOT NULL,
    CKey INTEGER PRIMARY KEY NOT NULL,
    Tcn CHAR(20) NOT NULL,
    Title CHAR(256) NOT NULL
);
END_SQL
}

# Creates the catalog table.
# param:  none
create_cat_indices()
{
    ######### schema ###########
    # CREATE TABLE catalog (
    #   Created INTEGER NOT NULL,
    #   CKey INTEGER PRIMARY KEY NOT NULL,
    #   Tcn CHAR(20) NOT NULL,
    #   Title CHAR(256) NOT NULL
    # );
    ######### schema ###########
    # All this information is available in the ILS, but gets deleted over time.
    # Think before you drop this table in production, historical data is difficult to retreive.
    sqlite3 $DBASE <<END_SQL
CREATE INDEX idx_cat_ckey ON cat (CKey);
CREATE INDEX idx_cat_tcn ON cat (Tcn);
END_SQL
}

# Removes indices from the cat table.
# param:  none
remove_cat_indices()
{
    sqlite3 $DBASE <<END_SQL
DROP INDEX IF EXISTS idx_cat_ckey;
DROP INDEX IF EXISTS idx_cat_tcn;
END_SQL
}

# Removes indices from the cat table.
# param:  none
remove_ckos_indices()
{
    sqlite3 $DBASE <<END_SQL
DROP INDEX IF EXISTS idx_ckos_date;
DROP INDEX IF EXISTS idx_ckos_userid;
DROP INDEX IF EXISTS idx_ckos_itemid;
DROP INDEX IF EXISTS idx_ckos_branch;
DROP INDEX IF EXISTS idx_ckos_item_userid;
END_SQL
}

# Removes indices from the cat table.
# param:  none
remove_user_indices()
{
    sqlite3 $DBASE <<END_SQL
DROP INDEX IF EXISTS idx_user_userid;
DROP INDEX IF EXISTS idx_user_key;
DROP INDEX IF EXISTS idx_user_profile;
END_SQL
}

# Removes indices from the cat table.
# param:  none
remove_item_indices()
{
    sqlite3 $DBASE <<END_SQL
DROP INDEX IF EXISTS idx_item_ckey_itemid;
DROP INDEX IF EXISTS idx_item_itemid;
DROP INDEX IF EXISTS idx_item_type;
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
        ## cat table
        if echo "SELECT COUNT(*) FROM $CAT_TABLE;" | sqlite3 $DBASE 2>/dev/null >/dev/null; then
            echo "confirmed $CAT_TABLE exists..." >&2
        else
            create_cat_table
        fi # End of creating user table.
    else
        create_ckos_table
        create_item_table
        create_user_table
        create_cat_table
    fi
}

# Drops all the standard tables.
# param:  name of the table to drop.
reset_table()
{
    local table=$1
    local answer=$FALSE
    if [ -s "$DBASE" ]; then   # If the database is not empty.
        if [ "$QUIET_MODE" == $FALSE ]; then
            answer=$(confirm "reset table $table ")
        else
            answer=$TRUE
        fi
        if [ "$answer" == "$FALSE" ]; then
            echo "table will be preserved. exiting" >&2
            exit $FALSE
        fi
        echo "DROP TABLE $table;" | sqlite3 $DBASE 2>/dev/null
        echo $TRUE
    else
        echo "$DBASE doesn't exist or is empty. Nothing to drop." >&2
        echo $FALSE
    fi
}

# Rebuilds the indices of the argument table. See -s for table names.
# param:  table name
add_table_indices()
{
    local table=$1
    if [ -s "$DBASE" ]; then   # If the database is not empty.
        # Test each table so we don't create tables that exist.
        ## CKOS table
        if [ "$table" == "$CKOS_TABLE" ]; then
            if echo "SELECT * FROM $CKOS_TABLE LIMIT 1;" | sqlite3 $DBASE 2>/dev/null >/dev/null; then
                echo "confirmed $CKOS_TABLE exists..." >&2
                create_ckos_indices
                return
            else
                echo "$CKOS_TABLE table doesn't exist. See -C." >&2
            fi # End of creating item table.
        ## Item table
        elif [ "$table" == "$ITEM_TABLE" ]; then
            if echo "SELECT * FROM $ITEM_TABLE LIMIT 1;" | sqlite3 $DBASE 2>/dev/null >/dev/null; then
                echo "confirmed $ITEM_TABLE exists..." >&2
                create_item_indices
                return
            else
                echo "$ITEM_TABLE table doesn't exist. See -I." >&2
            fi # End of creating item table.
        ## User table
        elif [ "$table" == "$USER_TABLE" ]; then
            if echo "SELECT * FROM $USER_TABLE LIMIT 1;" | sqlite3 $DBASE 2>/dev/null >/dev/null; then
                echo "confirmed $USER_TABLE exists..." >&2
                create_user_indices
                return
            else
                echo "$USER_TABLE table doesn't exist. See -U." >&2
            fi # End of creating user table.
        ## cat table
        elif [ "$table" == "$CAT_TABLE" ]; then
            if echo "SELECT * FROM $CAT_TABLE LIMIT 1;" | sqlite3 $DBASE 2>/dev/null >/dev/null; then
                echo "confirmed $CAT_TABLE exists..." >&2
                create_cat_indices
                return
            else
                echo "$CAT_TABLE table doesn't exist. See -G." >&2
            fi # End of creating user table.
        else
            echo "no such table '$table'. See -s for valid table names." >&2
        fi
    else
        echo "$DBASE doesn't exist or is empty. Use -B to created one." >&2
    fi
    echo 1
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
    local end_date=$TODAY
    ## Use hist reader for date ranges, it doesn't do single days just months.
    echo "["`date +'%Y-%m-%d %H:%M:%S'`"] reading history logs." >&2
    if [ "$QUIET_MODE" == $FALSE ]; then
        histreader.sh -D"E20|FEEPL|UO|NQ" -CCV -d"$start_date $end_date" >$TMP_FILE.$table.0
    else
        histreader.sh -i -D"E20|FEEPL|UO|NQ" -CCV -d"$start_date $end_date" >$TMP_FILE.$table.0
    fi
    # E201811011434461485R |FEEPLLHL|NQ31221117944590|UOLHL-DISCARD4
    # E201811011434501844R |FEEPLWMC|UO21221000876505|NQ31221118938062
    # E201811011434571698R |FEEPLLHL|NQ31221101053390|UO21221025137388
    # E201811011435031698R |FEEPLLHL|NQ31221108379350|UO21221025137388
    echo "["`date +'%Y-%m-%d %H:%M:%S'`"] preparing sql statements data." >&2
    # Re order the output so the Item id appears before the user id because it isn't consistently logged in order.
    cat $TMP_FILE.$table.0 | pipe.pl -gc2:UO -i -oc0,c1,c3,c2 -tany | pipe.pl -m"c0:INSERT OR IGNORE INTO $CKOS_TABLE (Date\,Branch\,ItemId\,UserId) VALUES (_##############_,c1:\"__############\",c2:\"__####################\",c3:\"__####################\");" -h',' -C"num_cols:width4-4" -TCHUNKED:"BEGIN=BEGIN TRANSACTION;,SKIP=10000.END TRANSACTION;BEGIN TRANSACTION;,END=END TRANSACTION;" >$TMP_FILE.$table.sql
    echo "["`date +'%Y-%m-%d %H:%M:%S'`"] done." >&2
    rm $TMP_FILE.$table.0
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
    grephist.pl -sCV -D"$YESTERDAY," | pipe.pl -W'\^' -gany:"E20|FEEPL|UO|NQ" -5 2>$TMP_FILE.$table.0 >/dev/null
    # E201811011514461108R |FEEPLWMC|NQ31221115247780|UO21221026682705
    # E201811011514470805R |FEEPLMLW|NQ31221116084117|UOMLW-DISCARD-NOV
    # E201811011514511108R |FEEPLWMC|NQ31221115406774|UO21221026682705
    # E201811011514521863R |FEEPLWHP|UO21221026176872|NQ31221115633690
    echo "["`date +'%Y-%m-%d %H:%M:%S'`"] preparing sql statements data." >&2
    # Re order the output so the Item id appears before the user id because it isn't consistently logged in order.
    cat $TMP_FILE.$table.0 | pipe.pl -gc2:UO -i -oc0,c1,c3,c2 -tany | pipe.pl -m"c0:INSERT OR IGNORE INTO $CKOS_TABLE (Date\,Branch\,ItemId\,UserId) VALUES (_##############_,c1:\"__############\",c2:\"__####################\",c3:\"__####################\");" -h',' -C"num_cols:width4-4" -TCHUNKED:"BEGIN=BEGIN TRANSACTION;,SKIP=10000.END TRANSACTION;BEGIN TRANSACTION;,END=END TRANSACTION;" >$TMP_FILE.$table.sql
    echo "["`date +'%Y-%m-%d %H:%M:%S'`"] done." >&2
    rm $TMP_FILE.$table.0
}

# Fills the user table with data from a given date.
get_user_data()
{
    ######### schema ###########
    # CREATE TABLE user (
        # Created INTEGER NOT NULL,
        # Key INTEGER PRIMARY KEY NOT NULL,
        # Id CHAR(20),
        # Profile CHAR(20)
    # );
    ######### schema ###########
    local table=$USER_TABLE
    local start_date=$1
    ## Get this from API seluser.
    echo "["`date +'%Y-%m-%d %H:%M:%S'`"] reading all user data." >&2
    seluser -ofUBp 2>/dev/null >$TMP_FILE.$table.0
    # 20180828|1544339|21221027463253|EPL_STAFF|
    # 20180906|1548400|21221027088076|EPL_STAFF|
    # 20180929|1558978|21221026819570|EPL_STAFF|
    echo "["`date +'%Y-%m-%d %H:%M:%S'`"] preparing sql statements data." >&2
    # Re order the output so the Item id appears before the user id because it isn't consistently logged in order.
    # Pad the end of the time stamp with 000000.
    cat $TMP_FILE.$table.0 | pipe.pl -pc0:'-14.0' -oremaining -tany | pipe.pl -m"c0:INSERT OR IGNORE INTO $USER_TABLE (Created\,Key\,Id\,Profile) VALUES (#,c1:#,c2:\"################\",c3:\"#################\");" -h',' -TCHUNKED:"BEGIN=BEGIN TRANSACTION;,SKIP=10000.END TRANSACTION;BEGIN TRANSACTION;,END=END TRANSACTION;" >$TMP_FILE.$table.sql
    echo "["`date +'%Y-%m-%d %H:%M:%S'`"] done." >&2
    rm $TMP_FILE.$table.0
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
    ## Get this from API seluser.
    echo "["`date +'%Y-%m-%d %H:%M:%S'`"] reading user data." >&2
    seluser -f">$YESTERDAY" -ofUBp 2>/dev/null >$TMP_FILE.$table.0
    # 20180828|1544339|21221027463253|EPL_STAFF|
    # 20180906|1548400|21221027088076|EPL_STAFF|
    # 20180929|1558978|21221026819570|EPL_STAFF|
    echo "["`date +'%Y-%m-%d %H:%M:%S'`"] preparing sql statements data." >&2
    # Re order the output so the Item id appears before the user id because it isn't consistently logged in order.
    # Pad the end of the time stamp with 000000.
    cat $TMP_FILE.$table.0 | pipe.pl -pc0:'-14.0' -oremaining -tany | pipe.pl -m"c0:INSERT OR IGNORE INTO $USER_TABLE (Created\,Key\,Id\,Profile) VALUES (#,c1:#,c2:\"################\",c3:\"#################\");" -h',' -TCHUNKED:"BEGIN=BEGIN TRANSACTION;,SKIP=10000.END TRANSACTION;BEGIN TRANSACTION;,END=END TRANSACTION;" >$TMP_FILE.$table.sql
    echo "["`date +'%Y-%m-%d %H:%M:%S'`"] done." >&2
    rm $TMP_FILE.$table.0
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
        selitem -oIBtf 2>/dev/null >$TMP_FILE.$table.0
        cat $ITEM_LST >>$TMP_FILE.$table.0
        cat $TMP_FILE.$table.0 | pipe.pl -pc5:'-14.0' -oc5,remaining -tany | pipe.pl -m"c0:INSERT OR IGNORE INTO $ITEM_TABLE (Created\,CKey\,Seq\,Copy\,Id\,Type) VALUES (#,c1:#,c2:#,c3:#,c4:\"################\",c5:\"####################\");" -h',' -TCHUNKED:"BEGIN=BEGIN TRANSACTION;,SKIP=10000.END TRANSACTION;BEGIN TRANSACTION;,END=END TRANSACTION;" >$TMP_FILE.$table.sql
        echo "["`date +'%Y-%m-%d %H:%M:%S'`"] done." >&2
        rm $TMP_FILE.$table.0
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
    local today=$YESTERDAY
    echo "["`date +'%Y-%m-%d %H:%M:%S'`"] reading item data since $YESTERDAY." >&2
    selitem -f">$YESTERDAY" -oIBtf 2>/dev/null >$TMP_FILE.$table.0
    # 2117336|1|1|2117336-1001|BOOK|20181102|
    # 2117337|1|1|2117337-1001|BOOK|20181102|
    # 2117338|1|1|31000040426630|ILL-BOOK|20181102|
    # 2117340|1|1|39335027163505|ILL-BOOK|20181102|
    echo "["`date +'%Y-%m-%d %H:%M:%S'`"] preparing sql statements data." >&2
    # Re order the output so the Item id appears before the user id because it isn't consistently logged in order.
    # Pad the end of the time stamp with 000000.
    cat $TMP_FILE.$table.0 | pipe.pl -pc5:'-14.0' -oc5,remaining -tany | pipe.pl -m"c0:INSERT OR IGNORE INTO $ITEM_TABLE (Created\,CKey\,Seq\,Copy\,Id\,Type) VALUES (#,c1:#,c2:#,c3:#,c4:\"################\",c5:\"####################\");" -h',' -TCHUNKED:"BEGIN=BEGIN TRANSACTION;,SKIP=10000.END TRANSACTION;BEGIN TRANSACTION;,END=END TRANSACTION;" >$TMP_FILE.$table.sql
    echo "["`date +'%Y-%m-%d %H:%M:%S'`"] done." >&2
    rm $TMP_FILE.$table.0
}

# Fills the cat table with data from a today.
get_catalog_data()
{
    ######### schema ###########
    # CREATE TABLE catalog (
    #   Created INTEGER NOT NULL,
    #   CKey INTEGER PRIMARY KEY NOT NULL,
    #   Tcn CHAR(20) NOT NULL,
    #   Title CHAR(256) NOT NULL,
    # );
    ######### schema ###########
    local table=$CAT_TABLE
    ## Get this from API selcatalog.
    echo "["`date +'%Y-%m-%d %H:%M:%S'`"] reading all catalog data." >&2
    selcatalog -opCFT 2>/dev/null >$TMP_FILE.$table.0
    # 19920117|7803|AAB-7268      |FODORS JAPAN|
    # 19920117|7808|AAB-7280      |FARM JOURNAL|
    # 19920117|7819|AAB-7306      |FODORS LOS ANGELES|
    # 19920117|7821|AAB-7309      |FLARE|
    # 19920117|7825|AAB-7319      |FURROW LAID BARE NEERLANDIA DISTRICT HISTORY|
    echo "["`date +'%Y-%m-%d %H:%M:%S'`"] preparing sql statements data." >&2
    # Pad the end of the time stamp with 000000.
    cat $TMP_FILE.$table.0 | pipe.pl -pc0:'-14.0' -oremaining -tany | pipe.pl -m"c0:INSERT OR IGNORE INTO $CAT_TABLE (Created\,CKey\,Tcn\,Title) VALUES (#,c1:#,c2:\"################\",c3:\"########################################################################################################################\");" -h',' -TCHUNKED:"BEGIN=BEGIN TRANSACTION;,SKIP=10000.END TRANSACTION;BEGIN TRANSACTION;,END=END TRANSACTION;" >$TMP_FILE.$table.sql
    echo "["`date +'%Y-%m-%d %H:%M:%S'`"] done." >&2
    rm $TMP_FILE.$table.0
}

# Fills the cat table with data added to the ILS toay.
get_catalog_data_today()
{
    ######### schema ###########
    # CREATE TABLE catalog (
    #   Created INTEGER NOT NULL,
    #   CKey INTEGER PRIMARY KEY NOT NULL,
    #   Tcn CHAR(20) NOT NULL,
    #   Title CHAR(256) NOT NULL,
    # );
    ######### schema ###########
    ## Get this from selcatalog
    local table=$CAT_TABLE
    local today=$YESTERDAY
    echo "["`date +'%Y-%m-%d %H:%M:%S'`"] reading catalog data from today." >&2
    # selitem -f">$today" -oIBtf 2>/dev/null | pipe.pl -tc2 >$TMP_FILE.$table.0
    selcatalog -f">$today" -opCFT 2>/dev/null >$TMP_FILE.$table.0
    # 19920117|7803|AAB-7268      |FODORS JAPAN|
    # 19920117|7808|AAB-7280      |FARM JOURNAL|
    # 19920117|7819|AAB-7306      |FODORS LOS ANGELES|
    # 19920117|7821|AAB-7309      |FLARE|
    # 19920117|7825|AAB-7319      |FURROW LAID BARE NEERLANDIA DISTRICT HISTORY|
    echo "["`date +'%Y-%m-%d %H:%M:%S'`"] preparing sql statements data." >&2
    # Pad the end of the time stamp with 000000.
    cat $TMP_FILE.$table.0 | pipe.pl -pc0:'-14.0' -oremaining -tany | pipe.pl -m"c0:INSERT OR IGNORE INTO $CAT_TABLE (Created\,CKey\,Tcn\,Title) VALUES (#,c1:#,c2:\"################\",c3:\"########################################################################################################################\");" -h',' -TCHUNKED:"BEGIN=BEGIN TRANSACTION;,SKIP=10000.END TRANSACTION;BEGIN TRANSACTION;,END=END TRANSACTION;" >$TMP_FILE.$table.sql
    echo "["`date +'%Y-%m-%d %H:%M:%S'`"] done." >&2
    rm $TMP_FILE.$table.0
}

# Loads all the SQL files that there are in the current directory.
# param:  none
load_any_SQL_data()
{
    for sql_file in $(ls $TMP/*.sql); do
        echo "BEGIN: loading $sql_file..." >&2
        cat $sql_file | sqlite3 $DBASE
        echo "END:   loading $sql_file..." >&2
        # Get rid of the pre-existing *.sql.gz, it was a previous load, and causes gzip to confirm
        # compression of a file over a pre-existing. It's old data anyway and we don't want
        # confusing backups, or command prompt confirmations to stop a cron job.
        if [ -f "$sql_file.gz" ]; then
            rm $sql_file.gz
        fi
        # Zip the file so we don't reload other tables.
        gzip $sql_file
    done
}

# Adds indices for all tables. This speeds up loading data on fresh tables.
add_indices()
{
    echo "["`date +'%Y-%m-%d %H:%M:%S'`"] adding indices to all tables." >&2
    create_cat_indices
    echo "["`date +'%Y-%m-%d %H:%M:%S'`"] ..." >&2
    create_ckos_indices
    echo "["`date +'%Y-%m-%d %H:%M:%S'`"] ..." >&2
    create_user_indices
    echo "["`date +'%Y-%m-%d %H:%M:%S'`"] ..." >&2
    create_item_indices
    echo "["`date +'%Y-%m-%d %H:%M:%S'`"] done." >&2
}

# Drops all indices on all tables. Speeds insertion of large amounts of data
# to do this, then rebuild them.
# param: none
remove_indices()
{
    echo "["`date +'%Y-%m-%d %H:%M:%S'`"] removing indices to all tables." >&2
    remove_cat_indices
    echo "["`date +'%Y-%m-%d %H:%M:%S'`"] ..." >&2
    remove_ckos_indices
    echo "["`date +'%Y-%m-%d %H:%M:%S'`"] ..." >&2
    remove_user_indices
    echo "["`date +'%Y-%m-%d %H:%M:%S'`"] ..." >&2
    remove_item_indices
    echo "["`date +'%Y-%m-%d %H:%M:%S'`"] done." >&2
}

# Asks if user would like to do what the message says.
# param:  message string.
# return: 0 if the answer was yes and 1 otherwise.
confirm()
{
	if [ -z "$1" ]; then
		echo "** error, confirm_yes requires a message." >&2
		exit $FALSE
	fi
	local message="$1"
	echo "$message? y/[n]: " >&2
	read answer
	case "$answer" in
		[yY])
			echo "yes selected." >&2
			echo $TRUE
			;;
		*)
			echo "no selected." >&2
			echo $FALSE
			;;
	esac
}

# Argument processing.
while getopts ":aABcCD:gGiILqr:R:suUxX:" opt; do
  case $opt in
    a)	echo "-a triggered to add today's data to the database $DBASE." >&2
        echo "["`date +'%Y-%m-%d %H:%M:%S'`"] adding daily updates to all tables." >&2
        echo "["`date +'%Y-%m-%d %H:%M:%S'`"] adding ckos created from $YESTERDAY." >&2
        get_cko_data_today
        echo "["`date +'%Y-%m-%d %H:%M:%S'`"] adding titles created from $YESTERDAY." >&2
        get_catalog_data_today
        echo "["`date +'%Y-%m-%d %H:%M:%S'`"] adding items created from $YESTERDAY." >&2
        get_item_data_today
        echo "["`date +'%Y-%m-%d %H:%M:%S'`"] adding users created from $YESTERDAY." >&2
        get_user_data_today
        echo "["`date +'%Y-%m-%d %H:%M:%S'`"] all data from $YESTERDAY." >&2
        load_any_SQL_data
        ;;
    A)	echo "-A triggered to rebuild the entire database $DBASE." >&2
        ### do checkouts.
        start_date=$(transdate -m-$START_MILESTONE_MONTHS_AGO)
        echo "["`date +'%Y-%m-%d %H:%M:%S'`"] rebuilding all tables from $start_date." >&2
        echo "["`date +'%Y-%m-%d %H:%M:%S'`"] rebuilding $CKOS_TABLE table from data starting $start_date." >&2
        get_cko_data $start_date
        ### do catalog
        echo "["`date +'%Y-%m-%d %H:%M:%S'`"] rebuilding $CAT_TABLE table." >&2
        get_catalog_data
        ### do item table
        echo "["`date +'%Y-%m-%d %H:%M:%S'`"] rebuilding $ITEM_TABLE table with data on file." >&2
        get_item_data
        ### do user table
        echo "["`date +'%Y-%m-%d %H:%M:%S'`"] rebuilding $USER_TABLE table from API starting $start_date." >&2
        get_user_data $start_date
        echo "["`date +'%Y-%m-%d %H:%M:%S'`"] loading data." >&2
        ANSWER=$FALSE
        if [ "$QUIET_MODE" == $FALSE ]; then
            ANSWER=$(confirm "rebuild database ")
        else
            ANSWER=$TRUE
        fi
        if [ "$ANSWER" == "$TRUE" ]; then
            echo "cleaning up old database" >&2
            if [ -s "$DBASE" ]; then
                # echo "["`date +'%Y-%m-%d %H:%M:%S'`"] droping $CKOS_TABLE table." >&2
                # reset_table $CKOS_TABLE
                # echo "["`date +'%Y-%m-%d %H:%M:%S'`"] droping $CAT_TABLE table." >&2
                # reset_table $CAT_TABLE
                # echo "["`date +'%Y-%m-%d %H:%M:%S'`"] droping item table." >&2
                # reset_table $ITEM_TABLE
                # echo "["`date +'%Y-%m-%d %H:%M:%S'`"] droping $USER_TABLE table." >&2
                # reset_table $USER_TABLE
                gzip $DBASE
            fi
            ## Recreate all the tables.
            ensure_tables
            ANSWER=$FALSE
            if [ "$QUIET_MODE" == $FALSE ]; then
                ANSWER=$(confirm "reload all data ")
            fi
            if [ "$ANSWER" == "$FALSE" ]; then
                echo "tables will not be loaded. Use -L to load them. exiting" >&2
            else
                echo "["`date +'%Y-%m-%d %H:%M:%S'`"] loading data." >&2
                load_any_SQL_data
                add_indices
            fi
        fi # No to rebuild database.
        ;;
    B)	echo "["`date +'%Y-%m-%d %H:%M:%S'`"] building missing tables." >&2
        ensure_tables
        ;;
    c)	echo "["`date +'%Y-%m-%d %H:%M:%S'`"] -c triggered to add data from $YESTERDAY to checkouts table." >&2
        get_cko_data_today
        remove_ckos_indices
        echo "["`date +'%Y-%m-%d %H:%M:%S'`"] loading checkout data data." >&2
        load_any_SQL_data
        echo "["`date +'%Y-%m-%d %H:%M:%S'`"] rebuilding indices on $CKOS_TABLE table." >&2
        create_ckos_indices
        ;;
    C)	echo "-C triggered to reload historical checkout data." >&2
        start_date=$(transdate -m-$START_MILESTONE_MONTHS_AGO)
        echo "["`date +'%Y-%m-%d %H:%M:%S'`"] droping $CKOS_TABLE table." >&2
        reset_table $CKOS_TABLE
        ensure_tables
        echo "["`date +'%Y-%m-%d %H:%M:%S'`"] rebuilding $CKOS_TABLE table from data starting $start_date." >&2
        get_cko_data $start_date
        echo "["`date +'%Y-%m-%d %H:%M:%S'`"] loading data." >&2
        load_any_SQL_data
        echo "["`date +'%Y-%m-%d %H:%M:%S'`"] rebuilding indices on $CKOS_TABLE table." >&2
        create_ckos_indices
        ;;
    D) echo "-D triggered to set to insert or ignore checkout data dated back from $OPTARG." >&2
        ANSWER=$FALSE
        if [ "$QUIET_MODE" == $FALSE ]; then
            ANSWER=$(confirm "collect data from $OPTARG ")
        else
            ANSWER=$TRUE
        fi
         if [ "$ANSWER" == "$FALSE" ]; then
             echo "exiting without making any changes." >&2
             exit $FALSE
        else
            YESTERDAY=$OPTARG
        fi
        ;;
    g)	echo "-g triggered to add today's catalog data to the $CAT_TABLE table." >&2
        echo "["`date +'%Y-%m-%d %H:%M:%S'`"] adding catalog data from today." >&2
        get_catalog_data_today
        load_any_SQL_data
        ;;
    G)	echo "-G triggered to reload all catalog data from ILS." >&2
        start_date=$(transdate -m-$START_MILESTONE_MONTHS_AGO)
        echo "["`date +'%Y-%m-%d %H:%M:%S'`"] droping $CAT_TABLE table." >&2
        reset_table $CAT_TABLE
        ensure_tables
        echo "["`date +'%Y-%m-%d %H:%M:%S'`"] rebuilding $CAT_TABLE table." >&2
        get_catalog_data
        echo "["`date +'%Y-%m-%d %H:%M:%S'`"] loading $CAT_TABLE table." >&2
        load_any_SQL_data
        echo "["`date +'%Y-%m-%d %H:%M:%S'`"] loading data." >&2
        load_any_SQL_data
        echo "["`date +'%Y-%m-%d %H:%M:%S'`"] rebuilding indices on $CAT_TABLE table." >&2
        create_cat_indices
        ;;
    i)	echo "-i triggered to add today's item data to the item table." >&2
        echo "["`date +'%Y-%m-%d %H:%M:%S'`"] adding item data from today." >&2
        get_item_data_today
        echo "["`date +'%Y-%m-%d %H:%M:%S'`"] loading data." >&2
        remove_item_indices
        load_any_SQL_data
        create_item_indices
        ;;
    I)	echo "-I triggered to reload historical item data loaded on ILS." >&2
        start_date=$(transdate -m-$START_MILESTONE_MONTHS_AGO)
        echo "["`date +'%Y-%m-%d %H:%M:%S'`"] droping item table." >&2
        reset_table $ITEM_TABLE
        ensure_tables
        echo "["`date +'%Y-%m-%d %H:%M:%S'`"] rebuilding item table with data on file." >&2
        get_item_data
        echo "["`date +'%Y-%m-%d %H:%M:%S'`"] loading data." >&2
        load_any_SQL_data
        echo "["`date +'%Y-%m-%d %H:%M:%S'`"] rebuilding indices on $ITEM_TABLE table." >&2
        create_item_indices
        ;;
    L)  echo "-L triggered to load any SQL files in this directory on an INSERT OR IGNORE basis." >&2
        remove_indices
        load_any_SQL_data
        add_indices
        ;;
    q)  echo "-q for quiet mode." >&2
        QUIET_MODE=$TRUE
        ;;
    r)  echo "-r triggered to refresh indices for table $OPTARG." >&2
        ensure_tables
        remove_indices
        add_indices
        ;;
    R)	echo "-R triggered to reset table $OPTARG. Creates table but doesn't add indices." >&2
        reset_table $OPTARG
        ensure_tables
        ;;
    s)	echo "-s triggered to show tables." >&2
        echo "$CKOS_TABLE" >&2
        echo "$ITEM_TABLE" >&2
        echo "$USER_TABLE" >&2
        echo "$CAT_TABLE" >&2
        ;;
    u)	echo "-u triggered to add users created today." >&2
        echo "["`date +'%Y-%m-%d %H:%M:%S'`"] adding users created from today." >&2
        get_user_data_today
        remove_user_indices
        echo "["`date +'%Y-%m-%d %H:%M:%S'`"] loading data." >&2
        load_any_SQL_data
        create_user_indices
        ;;
    U)  echo "-U triggered to reload user table data." >&2
        start_date=$(transdate -m-$START_MILESTONE_MONTHS_AGO)
        echo "["`date +'%Y-%m-%d %H:%M:%S'`"] droping $USER_TABLE table." >&2
        reset_table $USER_TABLE
        ensure_tables
        echo "["`date +'%Y-%m-%d %H:%M:%S'`"] rebuilding $USER_TABLE table from API starting $start_date." >&2
        get_user_data $start_date
        echo "["`date +'%Y-%m-%d %H:%M:%S'`"] loading data." >&2
        load_any_SQL_data
        echo "["`date +'%Y-%m-%d %H:%M:%S'`"] rebuilding indices on $USER_TABLE table." >&2
        create_user_indices
        ;;
    x)	usage
        ;;
    X)  echo "-X triggered to rebuild the index on table $OPTARG." >&2
        add_table_indices $OPTARG
        ;;
    \?)	echo "Invalid option: -$OPTARG" >&2
        usage
        ;;
  esac
done
exit 0
# EOF
