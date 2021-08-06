#!/bin/bash
###############################################################################
#
# Creates and maintains a quick and dirty dabase of commonly asked for hist data
#
#    Copyright (C) 2021  Andrew Nisbet, Edmonton Public Library
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
# There should be an entry in .bashrc
# ILS should have an entry: 'export QUAD_ENV=ils' 
# Database server should have an entry: 'export QUAD_ENV=database'
. ${HOME}/.bashrc
###############################################################################
VERSION=1.03.00
# This application has been ported to work on either the ILS or another server
# acting as the database host.
if [[ "$QUAD_ENV" == "database" ]]; then
    WORKING_DIR=$HOME/Quad
else
    WORKING_DIR=$HOME/Unicorn/EPLwork/cronjobscripts/Quad
fi
echo "Welcome to $0 my \$QUAD_ENV=$QUAD_ENV"
echo "testing for $WORKING_DIR: "
[ -d "$WORKING_DIR" ] || exit 1
# Make a timestamp so the sql files from today are uniquely named.
TSTAMP=$(date +'%Y%m%d')
TMP=/tmp
START_MILESTONE_MONTHS_AGO=18
DBASE=$WORKING_DIR/quad.db
# DBASE=$WORKING_DIR/test.db
CKOS_TABLE=ckos
ITEM_TABLE=item
USER_TABLE=user
CAT_TABLE=cat
TMP_FILE=$TMP/quad.tmp

TRUE=0
FALSE=1
QUIET_MODE=$FALSE
if [[ "$QUAD_ENV" == "ils" ]]; then
    # Only on ILS.
    ITEM_LST=$HOME/Unicorn/EPLwork/cronjobscripts/RptNewItemsAndTypes/new_items_types.tbl
    # If you need to catch up with more than just yesterday's just change the '1'
    # to the number of days back you need to go. transdate only on ILS.
    YESTERDAY=$(transdate -d-1)
    TODAY=$(transdate -d-0)
fi

## Set up logging.
LOG_FILE="$WORKING_DIR/buildlocalhist.log"
# Logs messages to STDOUT and $LOG_FILE file.
# param:  Message to put in the file.
# param:  (Optional) name of a operation that called this function.
logit()
{
    local message="$1"
    local time=$(date +"%Y-%m-%d %H:%M:%S")
    if [ -t 0 ]; then
        # If run from an interactive shell message STDOUT and LOG_FILE.
        echo -e "[$time] $message" | tee -a $LOG_FILE
    else
        # If run from cron do write to log.
        echo -e "[$time] $message" >>$LOG_FILE
    fi
}
######### schema ###########
# CREATE TABLE ckos (
    # Date INTEGER NOT NULL,
    # Branch TEXT,
    # ItemId INTEGER,
    # UserId INTEGER,
    # TransactionType TEXT NOT NULL default 'C',
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
    # Id TEXT NOT NULL,
    # Type TEXT,
    # PRIMARY KEY (CKey, Id)
# );
# CREATE INDEX idx_item_ckey_itemid ON item (CKey, Id);
# CREATE INDEX idx_item_itemid ON item (Id);
# CREATE INDEX idx_item_type ON item (Type);
# CREATE TABLE user (
    # Created INTEGER NOT NULL,
    # Key INTEGER PRIMARY KEY NOT NULL,
    # Id TEXT NOT NULL,
    # Profile TEXT
# );
# CREATE INDEX idx_user_userid ON user (Id);
# CREATE INDEX idx_user_key ON user (Key);
# CREATE INDEX idx_user_profile ON user (Profile);
# CREATE TABLE catalog (
    # Created INTEGER NOT NULL,
    # CKey INTEGER PRIMARY KEY NOT NULL,
    # Tcn TEXT NOT NULL,
    # Title TEXT NOT NULL,
# );
# CREATE INDEX idx_cat_ckey ON cat (CKey);
# CREATE INDEX idx_cat_tcn ON cat (Tcn);
######### schema ###########
cd $WORKING_DIR || exit 9
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
 *** NOTE: switches that start with '*' can only be run on the ILS. If you try to run
 *** them on the database host, the application will exit with status 1.

 -a * Updates all tables with data from \$YESTERDAY. See -L for loading data.
 -A * Rebuild the entire database by dropping all tables and creating all data.
    Takes about 1 hour. See -L for loading data.
 -B Build any tables that does not exist in the database.
    This function always checks if a table has data before
    attempting to create a table. It never drops tables so is safe
    to run. See -R to reset a named table.
 -c * Create $CKOS_TABLE table data from today's history file, but does not load it.
    To do that see the -L switch, which you can run any time.
 -C * Create $CKOS_TABLE table data starting $START_MILESTONE_MONTHS_AGO months ago.
    $START_MILESTONE_MONTHS_AGO is hard coded in the script and can be changed.
    A reset is automatically done before starting, and you will be asked to
    confirm before the old table is dropped. The load takes about 25 minutes for.
    a year's worth of data.
 -D{YYYYMMDD} Change the value of \$YESTERDAY. Normally it's set to transdate -d-0
    but allows you to set a catch-up date if the script hasn't run for a few days.
    It is safe to over estimate how far back to go since all inserts have a
    'or ignore' clause if they already exist.
    Used in conjunction with -a, -i, -g, -u, or -c. Ignored with all other flags.
 -g * Populate $CAT_TABLE table with items created today (since yesterday).
 -G * Create $CAT_TABLE table data from as far back as $START_MILESTONE_MONTHS_AGO
    The data read from catalog table in Symphony.
    Reset will drop the table in $DBASE and repopulate the table after confirmation.
 -i * Populate $ITEM_TABLE table with items created today (since yesterday).
 -I * Create $ITEM_TABLE table data from as far back as $ITEM_LST
    goes. The data read from that file is compiled nightly by rptnewitemsandtypes.sh.
    Reset will drop the table in $DBASE and repopulate the table after confirmation.
 -L Load any sql files in the current directory. Removes them as it goes.
 -p[yyyymmdd] Purge data from before the argument [ANSI] date.
 -u * Populate $USER_TABLE table with users created today via ILS API.
 -U * Populate $USER_TABLE table with data for all users in the ILS.
    The switch will first drop the existing table and reload data via ILS API.
 -s Show all the table names.
 -q Set quiet mode. Suppresses interactive confirmation of actions.
 -r Refresh indices for tables. Ensures all tables, drops and rebuilds the indices.
 -R{table} Drops and recreates a named table, including indices.
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
    Branch TEXT,
    ItemId TEXT NOT NULL,
    UserId TEXT NOT NULL,
    TransactionType TEXT NOT NULL default 'C',
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
    if [ ! -f "$DBASE" ]; then logit "Error: $DBASE does not exist."; exit 1; fi
    sqlite3 $DBASE <<END_SQL
CREATE INDEX idx_ckos_date ON ckos (Date);
CREATE INDEX idx_ckos_userid ON ckos (UserId);
CREATE INDEX idx_ckos_itemid ON ckos (ItemId);
CREATE INDEX idx_ckos_branch ON ckos (Branch);
CREATE INDEX idx_ckos_item_userid ON ckos (ItemId, UserId);
CREATE INDEX idx_ckos_date_transactiontype ON ckos (Date, TransactionType);
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
    Id TEXT NOT NULL,
    Profile TEXT
);
END_SQL
}

# Creates the indices for the user table.
# param:  none
create_user_indices()
{
    # The user table is quite dynamic so just keep most stable information. The rest can be looked up dynamically.
    # I don't want to spend a lot of time updating this table.
    if [ ! -f "$DBASE" ]; then logit "Error: $DBASE does not exist."; exit 1; fi
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
    Id TEXT NOT NULL,
    Type TEXT,
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
    if [ ! -f "$DBASE" ]; then logit "Error: $DBASE does not exist."; exit 1; fi
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
    #   Tcn TEXT NOT NULL,
    #   Title TEXT NOT NULL
    # );
    ######### schema ###########
    # All this information is available in the ILS, but gets deleted over time.
    # Think before you drop this table in production, historical data is difficult to retreive.
    sqlite3 $DBASE <<END_SQL
CREATE TABLE $CAT_TABLE (
    Created INTEGER NOT NULL,
    CKey INTEGER PRIMARY KEY NOT NULL,
    Tcn TEXT NOT NULL,
    Title TEXT NOT NULL
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
    #   Tcn TEXT NOT NULL,
    #   Title TEXT NOT NULL
    # );
    ######### schema ###########
    # All this information is available in the ILS, but gets deleted over time.
    # Think before you drop this table in production, historical data is difficult to retreive.
    if [ ! -f "$DBASE" ]; then logit "Error: $DBASE does not exist."; exit 1; fi
    sqlite3 $DBASE <<END_SQL
CREATE INDEX idx_cat_ckey ON cat (CKey);
CREATE INDEX idx_cat_tcn ON cat (Tcn);
END_SQL
}

# Removes indices from the cat table.
# param:  none
remove_cat_indices()
{
    if [ ! -f "$DBASE" ]; then logit "Error: $DBASE does not exist."; exit 1; fi
    sqlite3 $DBASE <<END_SQL
DROP INDEX IF EXISTS idx_cat_ckey;
DROP INDEX IF EXISTS idx_cat_tcn;
END_SQL
}

# Removes indices from the cat table.
# param:  none
remove_ckos_indices()
{
    if [ ! -f "$DBASE" ]; then logit "Error: $DBASE does not exist."; exit 1; fi
    sqlite3 $DBASE <<END_SQL
DROP INDEX IF EXISTS idx_ckos_date;
DROP INDEX IF EXISTS idx_ckos_userid;
DROP INDEX IF EXISTS idx_ckos_itemid;
DROP INDEX IF EXISTS idx_ckos_branch;
DROP INDEX IF EXISTS idx_ckos_item_userid;
DROP INDEX IF EXISTS idx_ckos_date_transactiontype;
END_SQL
}

# Removes indices from the cat table.
# param:  none
remove_user_indices()
{
    if [ ! -f "$DBASE" ]; then logit "Error: $DBASE does not exist."; exit 1; fi
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
    if [ ! -f "$DBASE" ]; then logit "Error: $DBASE does not exist."; exit 1; fi
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
# E202108061327182321R ^S01RVFFBIBLIOCOMM^FcNONE^FEEPLMCN^NQ31221317347792^IQMystery L PBK^UO21221026490349^Fv200000^dC5^^O00100
# E202108061327310006R ^S01RVFFBIBLIOCOMM^FcNONE^FEEPLMLW^NQ31221316962450^IQVideo game TEEN 793.93 FIR^UO21221025098739^Fv200000^dC5^^O00113
# E202108061327490008R ^S01RVFFBIBLIOCOMM^FcNONE^FEEPLMLW^NQ31221316980817^IQVideo game TEEN 793.93 XEN^UO21221025098739^Fv200000^dC5^^O00113
# E202108061327522284R ^S03RVFWSIPITIVA^FEEPLMNA^FFSIPCHK^FcNONE^FDSIPCHK^dC6^NQ31221110145534^UO21221018014230^^O
# E202108061328182267R ^S01RVFFBIBLIOCOMM^FcNONE^FEEPLLHL^NQ31221120642033^IQBAL^UO21221022968447^Fv200000^dC5^^O00090
# Discharges look like this:
# E202108061349120031R ^S42EVFWSMTCHTSTR1^FEEPLSTR^FFSMTCHT^FcNONE^FDSIPCHK^dC6^NQ31221118279475^CO8/6/2021,13:49^^O
# E202108061349242153R ^S13EVFWSMTCHTHVY001^FEEPLHVY^FFSMTCHT^FcNONE^FDSIPCHK^dC6^NQ31221118215982^CO8/6/2021,13:49^^O
# E202108061349250019R ^S64EVFWSORTLHL^FEEPLLHL^FFSORTATION^FcNONE^FDSIPCHK^dC6^NQ31221217368351^CO8/6/2021,13:49^^O
# E202108061349280019R ^S68EVFWSORTLHL^FEEPLLHL^FFSORTATION^FcNONE^FDSIPCHK^dC6^NQ31221118261150^CO8/6/2021,13:49^^O
# E202108061349312153R ^S17EVFWSMTCHTHVY001^FEEPLHVY^FFSMTCHT^FcNONE^FDSIPCHK^dC6^NQ31221121854132^CO8/6/2021,13:49^^O
get_cko_data()
{
    if [[ "$QUAD_ENV" == "database" ]]; then
        logit "get_cko_data operation only allowed on ILS."
        return
    fi
    ######### schema ###########
    # CREATE TABLE ckos (
        # Date INTEGER PRIMARY KEY NOT NULL,
        # Branch TEXT,
        # ItemId INTEGER,
        # UserId INTEGER
    # );
    ######### schema ###########
    local table=$CKOS_TABLE
    local start_date=$1
    local end_date=$TODAY
    ## Use hist reader for date ranges, it doesn't do single days just months.
    logit "reading history logs."
    if [ "$QUIET_MODE" == $FALSE ]; then
        ## Checkouts
        histreader.sh -D"E20|FEEPL|UO|NQ" -CCV -d"$start_date $end_date" >$TMP_FILE.$table.0
        ## Renewals
        histreader.sh -D"E20|FEEPL|UO|NQ" -CRV -d"$start_date $end_date" >$TMP_FILE.$table.1
        ## Discharges.
        histreader.sh -D"E20|FEEPL|UO|NQ" -CEV -d"$start_date $end_date" >$TMP_FILE.$table.2
    else
        histreader.sh -i -D"E20|FEEPL|UO|NQ" -CCV -d"$start_date $end_date" >$TMP_FILE.$table.0
        histreader.sh -i -D"E20|FEEPL|UO|NQ" -CRV -d"$start_date $end_date" >$TMP_FILE.$table.1
        histreader.sh -i -D"E20|FEEPL|UO|NQ" -CEV -d"$start_date $end_date" >$TMP_FILE.$table.2
    fi
    # E201811011434461485R |FEEPLLHL|NQ31221117944590|UOLHL-DISCARD4
    # E201811011434501844R |FEEPLWMC|UO21221000876505|NQ31221118938062
    # E201811011434571698R |FEEPLLHL|NQ31221101053390|UO21221025137388
    # E201811011435031698R |FEEPLLHL|NQ31221108379350|UO21221025137388
    # and the following if discharges since the user's ID is never included in the discharge.
    # E202108061349120031R |FEEPLSTR|NQ31221118279475
    # E202108061349242153R |FEEPLHVY|NQ31221118215982
    # E202108061349250019R |FEEPLLHL|NQ31221217368351
    # So I have added a bogus user '2122100000001' for the discharge event.
    logit "preparing sql statements data."
    # Re order the output so the Item id appears before the user id because it isn't consistently logged in order.
    cat $TMP_FILE.$table.0 | pipe.pl -gc2:UO -i -oc0,c1,c3,c2 -tany | pipe.pl -m"c0:INSERT OR IGNORE INTO $CKOS_TABLE (Date\,Branch\,ItemId\,UserId\,TransactionType) VALUES (_##############_,c1:\"__############\",c2:\"__####################\",c3:\"__####################\"\,\"C\");" -h',' -C"num_cols:width4-4" -TCHUNKED:"BEGIN=BEGIN TRANSACTION;,SKIP=10000.END TRANSACTION;BEGIN TRANSACTION;,END=END TRANSACTION;"  >$TMP_FILE.$table.$TSTAMP.sql
    cat $TMP_FILE.$table.1 | pipe.pl -gc2:UO -i -oc0,c1,c3,c2 -tany | pipe.pl -m"c0:INSERT OR IGNORE INTO $CKOS_TABLE (Date\,Branch\,ItemId\,UserId\,TransactionType) VALUES (_##############_,c1:\"__############\",c2:\"__####################\",c3:\"__####################\"\,\"R\");" -h',' -C"num_cols:width4-4" -TCHUNKED:"BEGIN=BEGIN TRANSACTION;,SKIP=10000.END TRANSACTION;BEGIN TRANSACTION;,END=END TRANSACTION;" >>$TMP_FILE.$table.$TSTAMP.sql
    cat $TMP_FILE.$table.2 | pipe.pl -gc2:UO -i -oc0,c1,c3,c2 -tany | pipe.pl -m"c0:INSERT OR IGNORE INTO $CKOS_TABLE (Date\,Branch\,ItemId\,UserId\,TransactionType) VALUES (_##############_,c1:\"__############\",c2:\"__####################\"\,\"21221000000001\"\,\"D\");" -h',' -C"num_cols:width3-3" -TCHUNKED:"BEGIN=BEGIN TRANSACTION;,SKIP=10000.END TRANSACTION;BEGIN TRANSACTION;,END=END TRANSACTION;"           >>$TMP_FILE.$table.$TSTAMP.sql
    logit "done."
    rm $TMP_FILE.$table.0
    rm $TMP_FILE.$table.1
    rm $TMP_FILE.$table.2
}

# Fills the checkout table with data from a given date.
# @TODO: add renews and discharges. Check history for format of each and determine how similar it is to ckos.
# @TODO: Alternatively extend the table to include a flag for C-checkout, R-renewal,D-discharge.
get_cko_data_today()
{
    if [[ "$QUAD_ENV" == "database" ]]; then
        logit "get_cko_data_today operation only allowed on ILS."
        return
    fi
    ######### schema ###########
    # CREATE TABLE ckos (
        # Date INTEGER PRIMARY KEY NOT NULL,
        # Branch TEXT,
        # ItemId INTEGER,
        # UserId INTEGER,
        # TransactionType TEXT NOT NULL default 'C'
    # );
    ######### schema ###########
    # @TODO extend for discharges and renewals.
    ## Use hist reader for date ranges, it doesn't do single days just months.
    local table=$CKOS_TABLE
    logit "reading history logs."
    # Checkouts
    grephist.pl -sCV -D"$YESTERDAY," | pipe.pl -W'\^' -gany:"E20|FEEPL|UO|NQ" -5 2>$TMP_FILE.$table.0 >/dev/null
    # Renews
    grephist.pl -sRV -D"$YESTERDAY," | pipe.pl -W'\^' -gany:"E20|FEEPL|UO|NQ" -5 2>$TMP_FILE.$table.1 >/dev/null
    # Discharges
    grephist.pl -sEV -D"$YESTERDAY," | pipe.pl -W'\^' -gany:"E20|FEEPL|UO|NQ" -5 2>$TMP_FILE.$table.2 >/dev/null
    # E201811011514461108R |FEEPLWMC|NQ31221115247780|UO21221026682705
    # E201811011514470805R |FEEPLMLW|NQ31221116084117|UOMLW-DISCARD-NOV
    # E201811011514511108R |FEEPLWMC|NQ31221115406774|UO21221026682705
    # E201811011514521863R |FEEPLWHP|UO21221026176872|NQ31221115633690
    # and the following if discharges since the user's ID is never included in the discharge.
    # E202108061349120031R |FEEPLSTR|NQ31221118279475
    # E202108061349242153R |FEEPLHVY|NQ31221118215982
    # E202108061349250019R |FEEPLLHL|NQ31221217368351
    logit "preparing sql statements data."
    # Re order the output so the Item id appears before the user id because it isn't consistently logged in order.
    cat $TMP_FILE.$table.0 | pipe.pl -gc2:UO -i -oc0,c1,c3,c2 -tany | pipe.pl -m"c0:INSERT OR IGNORE INTO $CKOS_TABLE (Date\,Branch\,ItemId\,UserId\,TransactionType) VALUES (_##############_,c1:\"__############\",c2:\"__####################\",c3:\"__####################\"\,\"C\");" -h',' -C"num_cols:width4-4" -TCHUNKED:"BEGIN=BEGIN TRANSACTION;,SKIP=10000.END TRANSACTION;BEGIN TRANSACTION;,END=END TRANSACTION;" >$TMP_FILE.$table.$TSTAMP.sql
    cat $TMP_FILE.$table.1 | pipe.pl -gc2:UO -i -oc0,c1,c3,c2 -tany | pipe.pl -m"c0:INSERT OR IGNORE INTO $CKOS_TABLE (Date\,Branch\,ItemId\,UserId\,TransactionType) VALUES (_##############_,c1:\"__############\",c2:\"__####################\",c3:\"__####################\"\,\"R\");" -h',' -C"num_cols:width4-4" -TCHUNKED:"BEGIN=BEGIN TRANSACTION;,SKIP=10000.END TRANSACTION;BEGIN TRANSACTION;,END=END TRANSACTION;" >>$TMP_FILE.$table.$TSTAMP.sql
    cat $TMP_FILE.$table.2 | pipe.pl -gc2:UO -i -oc0,c1,c3,c2 -tany | pipe.pl -m"c0:INSERT OR IGNORE INTO $CKOS_TABLE (Date\,Branch\,ItemId\,UserId\,TransactionType) VALUES (_##############_,c1:\"__############\",c2:\"__####################\"\,\"21221000000001\"\,\"D\");" -h',' -C"num_cols:width3-3" -TCHUNKED:"BEGIN=BEGIN TRANSACTION;,SKIP=10000.END TRANSACTION;BEGIN TRANSACTION;,END=END TRANSACTION;" >>$TMP_FILE.$table.$TSTAMP.sql
    logit "done."
    rm $TMP_FILE.$table.0
    rm $TMP_FILE.$table.1
    rm $TMP_FILE.$table.2
}

# Fills the user table with data from a given date.
get_user_data()
{
    if [[ "$QUAD_ENV" == "database" ]]; then
        logit "get_user_data operation only allowed on ILS."
        return
    fi
    ######### schema ###########
    # CREATE TABLE user (
        # Created INTEGER NOT NULL,
        # Key INTEGER PRIMARY KEY NOT NULL,
        # Id TEXT,
        # Profile TEXT
    # );
    ######### schema ###########
    local table=$USER_TABLE
    local start_date=$1
    ## Get this from API seluser.
    logit "reading all user data."
    seluser -ofUBp 2>/dev/null >$TMP_FILE.$table.0
    # 20180828|1544339|21221027463253|EPL_STAFF|
    # 20180906|1548400|21221027088076|EPL_STAFF|
    # 20180929|1558978|21221026819570|EPL_STAFF|
    logit "preparing sql statements data."
    # Re order the output so the Item id appears before the user id because it isn't consistently logged in order.
    # Pad the end of the time stamp with 000000.
    cat $TMP_FILE.$table.0 | pipe.pl -pc0:'-14.0' -oremaining -tany | pipe.pl -m"c0:INSERT OR IGNORE INTO $USER_TABLE (Created\,Key\,Id\,Profile) VALUES (#,c1:#,c2:\"<&>\",c3:\"<&>\");" -h',' -TCHUNKED:"BEGIN=BEGIN TRANSACTION;,SKIP=10000.END TRANSACTION;BEGIN TRANSACTION;,END=END TRANSACTION;" >$TMP_FILE.$table.$TSTAMP.sql
    logit "done."
    rm $TMP_FILE.$table.0
}

# Fills the user table with data from a given date.
get_user_data_today()
{
    if [[ "$QUAD_ENV" == "database" ]]; then
        logit "get_user_data_today operation only allowed on ILS."
        return
    fi
    ######### schema ###########
    # CREATE TABLE user (
        # Created INTEGER NOT NULL,
        # Key INTEGER PRIMARY KEY NOT NULL,
        # Id INTEGER NOT NULL,
        # Profile TEXT
    # );
    ######### schema ###########
    local table=$USER_TABLE
    ## Get this from API seluser.
    logit "reading user data."
    seluser -f">$YESTERDAY" -ofUBp 2>/dev/null >$TMP_FILE.$table.0
    # 20180828|1544339|21221027463253|EPL_STAFF|
    # 20180906|1548400|21221027088076|EPL_STAFF|
    # 20180929|1558978|21221026819570|EPL_STAFF|
    logit "preparing sql statements data."
    # Re order the output so the Item id appears before the user id because it isn't consistently logged in order.
    # Pad the end of the time stamp with 000000.
    cat $TMP_FILE.$table.0 | pipe.pl -pc0:'-14.0' -oremaining -tany | pipe.pl -m"c0:INSERT OR IGNORE INTO $USER_TABLE (Created\,Key\,Id\,Profile) VALUES (#,c1:#,c2:\"<&>\",c3:\"<&>\");" -h',' -TCHUNKED:"BEGIN=BEGIN TRANSACTION;,SKIP=10000.END TRANSACTION;BEGIN TRANSACTION;,END=END TRANSACTION;" >$TMP_FILE.$table.$TSTAMP.sql
    logit "done."
    rm $TMP_FILE.$table.0
}

# Fills the item table with data from a given date.
get_item_data()
{
    if [[ "$QUAD_ENV" == "database" ]]; then
        logit "get_item_data operation only allowed on ILS."
        return
    fi
    ######### schema ###########
    # CREATE TABLE item (
        # Created INTEGER NOT NULL,
        # CKey INTEGER NOT NULL,
        # Seq INTEGER NOT NULL,
        # Copy INTEGER NOT NULL,
        # Id INTEGER,
        # Type TEXT
    # );
    ######### schema ###########
    ## Get this from the file: $HOME/Unicorn/EPLwork/cronjobscripts/RptNewItemsAndTypes/new_items_types.tbl
    # 476|4|1|31221107445806|BOOK|20170104|
    # 514|122|1|31221114386118|PERIODICAL|20150407|
    # 514|156|1|31221214849072|PERIODICAL|20160426|
    # 514|169|1|31221215132478|PERIODICAL|20160901|
    # 514|173|1|31221215167086|PERIODICAL|20161019|
    # 567|25|1|31221214643954|PERIODICAL|20151118|
    local table=$ITEM_TABLE
    logit "reading item data from $ITEM_LST."
    if [ -s "$ITEM_LST" ]; then
        logit "preparing sql statements data."
        # Re order the output so the Item id appears before the user id because it isn't consistently logged in order.
        # Pad the end of the time stamp with 000000.
        selitem -oIBtf 2>/dev/null >$TMP_FILE.$table.0
        cat $ITEM_LST >>$TMP_FILE.$table.0
        cat $TMP_FILE.$table.0 | pipe.pl -pc5:'-14.0' -oc5,remaining -tany | pipe.pl -m"c0:INSERT OR IGNORE INTO $ITEM_TABLE (Created\,CKey\,Seq\,Copy\,Id\,Type) VALUES (#,c1:#,c2:#,c3:#,c4:\"<&>\",c5:\"<&>\");" -h',' -TCHUNKED:"BEGIN=BEGIN TRANSACTION;,SKIP=10000.END TRANSACTION;BEGIN TRANSACTION;,END=END TRANSACTION;" >$TMP_FILE.$table.$TSTAMP.sql
        logit "done."
        rm $TMP_FILE.$table.0
    else
        logit "**error: couldn't find file $ITEM_LST for historical item."
        exit 1
    fi
}

# Fills the item table with data from a given date.
get_item_data_today()
{
    if [[ "$QUAD_ENV" == "database" ]]; then
        logit "get_item_data_today operation only allowed on ILS."
        return
    fi
    ######### schema ###########
    # CREATE TABLE item (
        # Created INTEGER NOT NULL,
        # CKey INTEGER NOT NULL,
        # Seq INTEGER NOT NULL,
        # Copy INTEGER NOT NULL,
        # Id INTEGER,
        # Type TEXT
    # );
    ######### schema ###########
    ## Get this from selitem -f">`transdate -d-1`" -oIBtf | pipe.pl -tc3
    local table=$ITEM_TABLE
    local today=$YESTERDAY
    logit "reading item data since $YESTERDAY."
    selitem -f">$YESTERDAY" -oIBtf 2>/dev/null >$TMP_FILE.$table.0
    # 2117336|1|1|2117336-1001|BOOK|20181102|
    # 2117337|1|1|2117337-1001|BOOK|20181102|
    # 2117338|1|1|31000040426630|ILL-BOOK|20181102|
    # 2117340|1|1|39335027163505|ILL-BOOK|20181102|
    logit "preparing sql statements data."
    # Re order the output so the Item id appears before the user id because it isn't consistently logged in order.
    # Pad the end of the time stamp with 000000.
    cat $TMP_FILE.$table.0 | pipe.pl -pc5:'-14.0' -oc5,remaining -tany | pipe.pl -m"c0:INSERT OR IGNORE INTO $ITEM_TABLE (Created\,CKey\,Seq\,Copy\,Id\,Type) VALUES (#,c1:#,c2:#,c3:#,c4:\"<&>\",c5:\"<&>\");" -h',' -TCHUNKED:"BEGIN=BEGIN TRANSACTION;,SKIP=10000.END TRANSACTION;BEGIN TRANSACTION;,END=END TRANSACTION;" >$TMP_FILE.$table.$TSTAMP.sql
    logit "done."
    rm $TMP_FILE.$table.0
}

# Fills the cat table with data from a today.
get_catalog_data()
{
    if [[ "$QUAD_ENV" == "database" ]]; then
        logit "get_catalog_data operation only allowed on ILS."
        return
    fi
    ######### schema ###########
    # CREATE TABLE catalog (
    #   Created INTEGER NOT NULL,
    #   CKey INTEGER PRIMARY KEY NOT NULL,
    #   Tcn TEXT NOT NULL,
    #   Title TEXT NOT NULL,
    # );
    ######### schema ###########
    local table=$CAT_TABLE
    ## Get this from API selcatalog.
    logit "reading all catalog data."
    selcatalog -opCFT 2>/dev/null >$TMP_FILE.$table.0
    # 19920117|7803|AAB-7268      |FODORS JAPAN|
    # 19920117|7808|AAB-7280      |FARM JOURNAL|
    # 19920117|7819|AAB-7306      |FODORS LOS ANGELES|
    # 19920117|7821|AAB-7309      |FLARE|
    # 19920117|7825|AAB-7319      |FURROW LAID BARE NEERLANDIA DISTRICT HISTORY|
    logit "preparing sql statements data."
    # Pad the end of the time stamp with 000000.
    cat $TMP_FILE.$table.0 | pipe.pl -pc0:'-14.0' -oremaining -tany | pipe.pl -m"c0:INSERT OR IGNORE INTO $CAT_TABLE (Created\,CKey\,Tcn\,Title) VALUES (#,c1:#,c2:\"<&>\",c3:\"<&>\");" -h',' -TCHUNKED:"BEGIN=BEGIN TRANSACTION;,SKIP=10000.END TRANSACTION;BEGIN TRANSACTION;,END=END TRANSACTION;" >$TMP_FILE.$table.$TSTAMP.sql
    logit "done."
    rm $TMP_FILE.$table.0
}

# Fills the cat table with data added to the ILS toay.
get_catalog_data_today()
{
    if [[ "$QUAD_ENV" == "database" ]]; then
        logit "get_catalog_data_today operation only allowed on ILS."
        return
    fi
    ######### schema ###########
    # CREATE TABLE catalog (
    #   Created INTEGER NOT NULL,
    #   CKey INTEGER PRIMARY KEY NOT NULL,
    #   Tcn TEXT NOT NULL,
    #   Title TEXT NOT NULL,
    # );
    ######### schema ###########
    ## Get this from selcatalog
    local table=$CAT_TABLE
    local today=$YESTERDAY
    logit "reading catalog data from today."
    # selitem -f">$today" -oIBtf 2>/dev/null | pipe.pl -tc2 >$TMP_FILE.$table.0
    selcatalog -f">$today" -opCFT 2>/dev/null >$TMP_FILE.$table.0
    # 19920117|7803|AAB-7268      |FODORS JAPAN|
    # 19920117|7808|AAB-7280      |FARM JOURNAL|
    # 19920117|7819|AAB-7306      |FODORS LOS ANGELES|
    # 19920117|7821|AAB-7309      |FLARE|
    # 19920117|7825|AAB-7319      |FURROW LAID BARE NEERLANDIA DISTRICT HISTORY|
    logit "preparing sql statements data."
    # Pad the end of the time stamp with 000000.
    cat $TMP_FILE.$table.0 | pipe.pl -pc0:'-14.0' -oremaining -tany | pipe.pl -m"c0:INSERT OR IGNORE INTO $CAT_TABLE (Created\,CKey\,Tcn\,Title) VALUES (#,c1:#,c2:\"<&>\",c3:\"<&>\");" -h',' -TCHUNKED:"BEGIN=BEGIN TRANSACTION;,SKIP=10000.END TRANSACTION;BEGIN TRANSACTION;,END=END TRANSACTION;" >$TMP_FILE.$table.$TSTAMP.sql
    logit "done."
    rm $TMP_FILE.$table.0
}

# Loads all the SQL files that there are in the current directory.
# param:  none
load_any_SQL_data()
{
    for sql_file in $(ls -trc1 $TMP/*.sql); do
        logit "BEGIN: loading $sql_file..."
        if [ ! -f "$DBASE" ]; then logit "Error: $DBASE does not exist."; exit 1; fi
        cat $sql_file | sqlite3 $DBASE
        logit "END:   loading $sql_file..."
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
    logit "adding indices to all tables." >&2
    create_cat_indices
    create_ckos_indices
    create_user_indices
    create_item_indices
    logit "done."
}

# Drops all indices on all tables. Speeds insertion of large amounts of data
# to do this, then rebuild them.
# param: none
remove_indices()
{
    logit "removing indices to all tables."
    remove_cat_indices
    remove_ckos_indices
    remove_user_indices
    remove_item_indices
    logit "done."
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
	read -p "$message? y/[n]: " answer < /dev/tty
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

# Purge records from the ckos table belfore a given date.
# Only the ckos table is affected by this operation because it is the largest number of records,
# and because the other tables use 'Create' dates to store data, and many are much older than
# what you might expect. Some titles were created in 1992, we don't want to delete titles from 
# before 2016, say. Customer accounts are even older.
purge_old_data()
{
    if [[ "$QUAD_ENV" != "database" ]]; then
        logit "purge_old_data operation only works on database server."
        exit 1
    fi
    if [ ! -f "$DBASE" ]; then logit "Error: $DBASE does not exist."; exit 1; fi
    local earliestDate=$1
    if [ -z "$earliestDate" ]; then logit "**expected earliest year to keep, but got none"; return; fi
    # Tack on the hours minutes seconds as round values to ensure the integer values in the db match.
    earliestDate=$earliestDate"000000"
    local delRecordCount=$(echo "SELECT count(*) FROM ckos WHERE Date<$earliestDate;" | sqlite3 $DBASE)
    logit "preparing to purge $delRecordCount records."
    ANSWER=$(confirm "purge data ")
    if [ "$ANSWER" == "$FALSE" ]; then
        logit "purge cancelled"
    else
        echo "DELETE FROM ckos WHERE Date<$earliestDate;" | sqlite3 $DBASE
        logit "purge records from before $earliestDate complete"
    fi
}

# Argument processing.
while getopts ":aABcCD:gGiILp:qr:R:suUxX:" opt; do
  case $opt in
    a)	echo "-a triggered to add today's data to the database $DBASE." >&2
        logit "adding daily updates to all tables."
        logit "adding ckos created from $YESTERDAY."
        get_cko_data_today
        logit "adding titles created from $YESTERDAY."
        get_catalog_data_today
        logit "adding items created from $YESTERDAY."
        get_item_data_today
        logit "adding users created from $YESTERDAY."
        get_user_data_today
        logit "all data from $YESTERDAY."
        # Don't do this on the ils anymore. Just create the sql files.
        if [[ "$QUAD_ENV" == "database" ]]; then
            load_any_SQL_data
        fi
        ;;
    A)	echo "-A triggered to rebuild the entire database $DBASE. ILS only." >&2
        if [[ "$QUAD_ENV" == "database" ]]; then
            logit "-A operation only allowed on ILS."
            exit 1
        fi
        ### do checkouts.
        start_date=$(transdate -m-$START_MILESTONE_MONTHS_AGO)
        logit "rebuilding all tables from $start_date."
        logit "rebuilding $CKOS_TABLE table from data starting $start_date."
        get_cko_data $start_date
        ### do catalog
        logit "rebuilding $CAT_TABLE table."
        get_catalog_data
        ### do item table
        logit "rebuilding $ITEM_TABLE table with data on file."
        get_item_data
        ### do user table
        logit "rebuilding $USER_TABLE table from API starting $start_date."
        get_user_data $start_date
        logit "loading data."
        ANSWER=$FALSE
        if [ "$QUIET_MODE" == $FALSE ]; then
            ANSWER=$(confirm "rebuild database ")
        else
            ANSWER=$TRUE
        fi
        if [ "$ANSWER" == "$TRUE" ]; then
            logit "cleaning up old database"
            if [ -s "$DBASE" ]; then
                # logit "droping $CKOS_TABLE table."
                # reset_table $CKOS_TABLE
                # logit "droping $CAT_TABLE table."
                # reset_table $CAT_TABLE
                # logit "droping item table."
                # reset_table $ITEM_TABLE
                # logit "droping $USER_TABLE table."
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
                logit "loading data."
                load_any_SQL_data
                add_indices
            fi
        fi # No to rebuild database.
        ;;
    B)	echo "-B triggered building missing tables." >&2
        ensure_tables
        ;;
    c)	echo "-c triggered to add data from $YESTERDAY to checkouts table." >&2
        get_cko_data_today
        remove_ckos_indices
        logit "loading checkout data data."
        load_any_SQL_data
        logit "rebuilding indices on $CKOS_TABLE table."
        create_ckos_indices
        ;;
    C)	echo "-C triggered to reload historical checkout data." >&2
        if [[ "$QUAD_ENV" == "database" ]]; then
            logit "-C operation only allowed on ILS."
            exit 1
        fi
        start_date=$(transdate -m-$START_MILESTONE_MONTHS_AGO)
        logit "droping $CKOS_TABLE table."
        reset_table $CKOS_TABLE
        ensure_tables
        logit "rebuilding $CKOS_TABLE table from data starting $start_date."
        get_cko_data $start_date
        logit "loading data."
        load_any_SQL_data
        logit "rebuilding indices on $CKOS_TABLE table."
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
        logit "adding catalog data from today."
        get_catalog_data_today
        load_any_SQL_data
        ;;
    G)	echo "-G triggered to reload all catalog data from ILS." >&2
        if [[ "$QUAD_ENV" == "database" ]]; then
            logit "-G operation only allowed on ILS."
            exit 1
        fi
        start_date=$(transdate -m-$START_MILESTONE_MONTHS_AGO)
        logit "droping $CAT_TABLE table."
        reset_table $CAT_TABLE
        ensure_tables
        logit "rebuilding $CAT_TABLE table."
        get_catalog_data
        logit "loading $CAT_TABLE table."
        load_any_SQL_data
        logit "rebuilding indices on $CAT_TABLE table."
        create_cat_indices
        ;;
    i)	echo "-i triggered to add today's item data to the item table." >&2
        logit "adding item data from today."
        get_item_data_today
        logit "loading data."
        remove_item_indices
        load_any_SQL_data
        create_item_indices
        ;;
    I)	echo "-I triggered to reload historical item data loaded on ILS." >&2
        if [[ "$QUAD_ENV" == "database" ]]; then
            logit "-I operation only allowed on ILS."
            exit 1
        fi
        start_date=$(transdate -m-$START_MILESTONE_MONTHS_AGO)
        logit "droping item table."
        reset_table $ITEM_TABLE
        ensure_tables
        logit "rebuilding item table with data on file."
        get_item_data
        logit "loading data."
        load_any_SQL_data
        logit "rebuilding indices on $ITEM_TABLE table."
        create_item_indices
        ;;
    L)  echo "-L triggered to load any SQL files in this directory on an INSERT OR IGNORE basis." >&2
        remove_indices
        load_any_SQL_data
        add_indices
        ;;
    p)  echo "-p triggered to purge data older than $OPTARG" >&2
        purge_old_data $OPTARG
        exit 0
        ;;
    q)  echo "-q for quiet mode." >&2
        QUIET_MODE=$TRUE
        ;;
    r)  echo "-r triggered to refresh indices for tables." >&2
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
        logit "adding users created from today."
        get_user_data_today
        remove_user_indices
        logit "loading data."
        load_any_SQL_data
        create_user_indices
        ;;
    U)  echo "-U triggered to reload user table data." >&2
        if [[ "$QUAD_ENV" == "database" ]]; then
            logit "-U operation only allowed on ILS."
            exit 1
        fi
        start_date=$(transdate -m-$START_MILESTONE_MONTHS_AGO)
        logit "droping $USER_TABLE table."
        reset_table $USER_TABLE
        ensure_tables
        logit "rebuilding $USER_TABLE table from API starting $start_date."
        get_user_data $start_date
        logit "loading data."
        load_any_SQL_data
        logit "rebuilding indices on $USER_TABLE table."
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
