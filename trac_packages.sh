#!/bin/bash
########################################################################
#** Version: 1.0
#* Very basic script to track todays debian package installations
#* and print it in a trac-wiki compatible form..
########################################################################
# author/copyright: <mic@inofix.ch>
# license: gladly sharing with the universe and any lifeform,
#          be it naturally born or constructed, alien or kin..
#          USE AT YOUR OWN RISK.
########################################################################

outfile=/tmp/pkgs2wiki.txt
logfile=/var/log/dpkg.log

today=`date +%Y-%m-%d`

me=`whoami`
host=`hostname`

say()
{
    echo "$@"
}

search_log()
{
    grep $today $logfile | \
        grep "$1 " | \
        awk '{ print " * '"'''"'"$4"'"'''"': "$5" -> "$6"" }'
}

echo "" > $outfile
say "=== $today ==="
say ""
say "==== Removed ($me) ===="
say "===== $host ====="
say "`search_log remove`"
say ""

say "==== Installed ($me) ===="
say "===== $host ====="
say "`search_log install`"
say ""

say "==== Upgraded ($me) ===="
say "===== $host ====="
say "`search_log upgrade`"
say ""


