###############################################################################
# Makefile for project buildlocalhist
# Created: 2018-11-01
# Copyright (c) Edmonton Public Library 2018
# The Edmonton Public Library respectfully acknowledges that we sit on
# Treaty 6 territory, traditional lands of First Nations and Metis people.
#
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
#      1.1 - Use epl-el1.epl.ca as the database server.
###############################################################################
# Change comment below for appropriate server.
PRODUCTION_SERVER=edpl.sirsidynix.net
DB_SERVER=epl-el1.epl.ca
USER=sirsi
DB_USER=its
# REMOTE=~/Unicorn/Logs/Hist/
REMOTE=~/Unicorn/EPLwork/cronjobscripts/Quad/
DB_REMOTE=~/Quad
LOCAL=~/projects/quad/
APP=buildlocalhist.sh
DB_LOADER=quadloader.sh

.phony: test production

test:
	scp ${LOCAL}${APP} ${DB_USER}@${DB_SERVER}:${DB_REMOTE}
	scp ${LOCAL}${DB_LOADER} ${DB_USER}@${DB_SERVER}:${DB_REMOTE}
production: test
	scp ${LOCAL}${APP} ${USER}@${PRODUCTION_SERVER}:${REMOTE}

