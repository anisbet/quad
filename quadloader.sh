#!/bin/bash
###############################################################################
#
# Loads quad data on into the quad.db. Run by cron.
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
## This does f-all in cron.
. ~/.bashrc
export QUAD_ENV=database
###############################################################################
VERSION=1.01.1
ILS=edpl.sirsidynix.net
## This file globbing stands for files of /tmp/quad.tmp.[yyyymmdd].[gz|sql]
QUAD_TMP_FILES='/tmp/quad.tmp*'
LOG=$HOME/Quad/load.log
## scp all the sql files from the ils's /tmp directory.
echo "["`date +'%Y-%m-%d %H:%M:%S'`"]=== starting $0 " >>$LOG
if scp sirsi@${ILS}:$QUAD_TMP_FILES /tmp >>$LOG 2>&1; then
    echo "["`date +'%Y-%m-%d %H:%M:%S'`"] scp'ed files from ${ILS}:${QUAD_TMP_FILES} " >>$LOG
    ## Loaded in order if the script needs to catch up after not running
    ## for a few days.
    file_list=$(ls -trc1 $QUAD_TMP_FILES)
    echo -e "["`date +'%Y-%m-%d %H:%M:%S'`"] files for loading:\n$file_list\n" >>$LOG
    ## run buildlocalhist.sh -L
    if $HOME/Quad/buildlocalhist.sh -L >>$LOG 2>&1; then
        ## Clean up the files on the ils
        echo "["`date +'%Y-%m-%d %H:%M:%S'`"] $HOME/Quad/buildlocalhist.sh -L ran successfully " >>$LOG
        if ssh sirsi@${ILS} "rm ${QUAD_TMP_FILES}" >>$LOG 2>&1; then
            echo "["`date +'%Y-%m-%d %H:%M:%S'`"] removed old files from ${ILS}:${QUAD_TMP_FILES}" >>$LOG
        else
            echo "["`date +'%Y-%m-%d %H:%M:%S'`"] failed to remove ${ILS}:${QUAD_TMP_FILES} files " >>$LOG
            exit 1
        fi
    else
        echo "["`date +'%Y-%m-%d %H:%M:%S'`"] failed to run $HOME/Quad/buildlocalhist.sh -L " >>$LOG
        exit 1
    fi
else
    echo "["`date +'%Y-%m-%d %H:%M:%S'`"] failed to copy ${ILS}:${QUAD_TMP_FILES} files " >>$LOG
    exit 1
fi 
echo "["`date +'%Y-%m-%d %H:%M:%S'`"]=== $0 finished successfully"  >>$LOG
exit 0
