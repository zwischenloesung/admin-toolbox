#!/bin/bash
########################################################################
#** Version: 2.0
#* Very basic script to track todays debian package installations
#* and print it in a trac-wiki compatible form..
########################################################################
# author/copyright: <mic@inofix.ch>
# license: gladly sharing with the universe and any lifeform,
#          be it naturally born or constructed, alien or kin..
#          USE AT YOUR OWN RISK.
########################################################################

# default output is stdout
outfile=

# search all possible files per default
logfile=( "/var/log/dpkg.log" "/var/log/dpkg.log.1" )

# default search for everything
target_pattern=( "remove" "install" "update" )

# default title
title="Upgrades"

#--- auto ---
# default is today
day=`date +%Y-%m-%d`

# who to log for
me=`whoami`

# register the hostname to log for
host=`hostname`

up=`uptime -p`

print_usage()
{
    echo "usage: $0"
}

print_help()
{
    print_usage
    grep "^#\* " $0 | sed 's;^#\*;;'
}

print_version()
{
    grep "^#\*\* " $0 | sed 's;^#\*\*;;'
}

print_package_log()
{
    text="$1"
    pattern="$2"
    day="$3"
    echo "====== $text ======"
    grep $day ${logfile[@]} | \
        grep "$pattern " | \
        awk '{ print " * '"'''"'"$4"'"'''"': "$5" -> "$6"" }'
    echo ""
}

die()
{
    echo "$@"
    exit 1
}

error()
{
    print_usage
    echo ""
    die "Error: $@"
}

#*  options:
while true ; do
    case "$1" in
#*      -i |--infile logfilename    alternative log file
        -i|--infile)
            shift
            if [ -r "$1" ] ; then
                logfile=( "$1" )
            else
                die " log file $1 does not exist."
            fi
        ;;
#*      -h |--help                  print this help
        -h|--help)
            print_help
            exit 0
        ;;
#*      -s |--search pattern        search for 'remove', 'install' or 'update'
        -s|--search)
            shift
            case "$1" in
                remove|install|update)
                    target_pattern=( "$1" )
                ;;
                *)
                    error "search pattern is not supported"
                ;;
            esac
        ;;
#*      -o |--outfile filename      output file
        -o|--outfile)
            shift
            outfile=( "$1" )
        ;;
#*      -t |--title title           title for the report
        -t|--title)
            shift
            title="$1"
        ;;
#*      -v |--version               print the version and exit
        -v|--version)
            print_version
            exit
        ;;
#*      -y |--yesterday             search for the past day
        -y|--yesterday)
            day=`date -d yesterday +%Y-%m-%d`
        ;;
        -*|--*)
            error "option $1 is not supported"
        ;;
        *)
            break
        ;;
    esac
    shift
done

if [ -n "$outfile" ] ; then
    error "output to file is not implemented yet, use redirect"
fi

echo "=== $day ==="
echo "==== $title ($me) ===="
echo "===== $host ($up) ====="

for p in ${target_pattern[@]} ; do
    case "$p" in
        remove)
            print_package_log "removed" "$p" "$day"
        ;;
        install)
            print_package_log "installed" "$p" "$day"
        ;;
        update)
            print_package_log "updated" "$p" "$day"
        ;;
    esac
done
