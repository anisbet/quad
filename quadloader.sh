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
. ~/.bashrc
###############################################################################
VERSION=0.01.2
LOG=$HOME/Quad/load.log
## scp all the sql files from the ils's /tmp directory.
echo "["`date +'%Y-%m-%d %H:%M:%S'`"]=== starting " >>$LOG
if scp sirsi@eplapp.library.ualberta.ca:/tmp/quad*.sql /tmp; then
    ## run buildlocalhist.sh -L
    file_list=$(ls -trc1 /tmp/*.sql)
    echo -e "["`date +'%Y-%m-%d %H:%M:%S'`"] scp'ed the following files from the ils:\n$file_list\n" >>$LOG
    if $HOME/Quad/buildlocalhist.sh -L ; then
        ## Clean up the files on the ils
        echo "["`date +'%Y-%m-%d %H:%M:%S'`"] successfully loaded data." >>$LOG
        if ssh sirsi@eplapp.library.ualberta.ca 'rm /tmp/*.sql'; then
            echo "["`date +'%Y-%m-%d %H:%M:%S'`"] removed old files from the ils" >>$LOG
        else
            echo "["`date +'%Y-%m-%d %H:%M:%S'`"] failed to remove *.sql files from ils /tmp." >>$LOG
            exit 1
        fi
    else
        echo "["`date +'%Y-%m-%d %H:%M:%S'`"] failed to run $HOME/Quad/buildlocalhist.sh -L " >>$LOG
        exit 1
    fi
else
    echo "["`date +'%Y-%m-%d %H:%M:%S'`"] failed to copy *.sql files from ils/tmp. " >>$LOG
    exit 1
fi 
echo "["`date +'%Y-%m-%d %H:%M:%S'`"]=== finished successfully."  >>$LOG
exit 0
