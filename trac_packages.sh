#!/bin/bash
########################################################################
#** Version: 2.1
#* Very basic script to track todays debian package installations
#* and print it in a trac-wiki compatible form (or markdown)..
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

tmpfile=""

autofilename=""
autosuffix=".txt"

# title format
t="="
b="'''"

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

found_something=0
print_package_log()
{
    text="$1"
    pattern="$2"
    day="$3"
    echo "$t$t$t$t$t$t $text $t$t$t$t$t$t" | tee -a $tmpfile
    if [ "$autosuffix" == ".md" ] ; then
        grep $day ${logfile[@]} | grep "$pattern " | \
            awk '{ print " * '"$b"'"$4"'"$b"': "$5" -> "$6"" }' | \
            sed -e 's|<|\&lt;|g' -e 's|>|\&gt;|g' | tee -a $tmpfile | grep ".*"
        retval=$?
    else
        grep $day ${logfile[@]} | grep "$pattern " | \
            awk '{ print " * '"$b"'"$4"'"$b"': "$5" -> "$6"" }' | \
            tee -a $tmpfile | grep ".*"
        retval=$?
    fi
    if [ $retval -eq 0 ] ; then
        let found_something+=1
    fi
    echo "" | tee -a $tmpfile
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
#*      -M |--markdown              search for 'remove', 'install' or 'update'
        -M|--markdown)
            autosuffix=".md"
            t="#"
            b="**"
        ;;
#*      -o |--outfile filename      output file name
        -o|--outfile)
            shift
            tmpfile=`mktemp`
            if [ -d "$1" ] ; then
                error "this is a direcory, did you mean --outdir instead?"
            else
                outfile="$1"
            fi
        ;;
#*      -O |--outdir dirname        directory to put automatic file names
        -O|--outdir)
            shift
            tmpfile=`mktemp`
            if [ -d "$1" ] ; then
                outfile="${1}/packages_by_date_${day}_${host}"
            else
                error "this is not a direcory, did you mean --outdir instead?"
            fi
            autofilename="yes"
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

if [ -n "$autofilename" ] ; then
    #TODO add .md..
    outfile+="$autosuffix"
fi

echo "$t Package Log $t" | tee -a $tmpfile
echo "$t$t Date Based View $t$t" | tee -a $tmpfile
echo "$t$t$t $day $t$t$t" | tee -a $tmpfile
echo "$t$t$t$t $title ($me) $t$t$t$t" | tee -a $tmpfile
echo "$t$t$t$t$t $host ($up) $t$t$t$t$t" | tee -a $tmpfile

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

if [ -n "$outfile" ] ; then
    if [ $found_something -gt 0 ] ; then
        cp $tmpfile $outfile
    else
        echo "no package changes found"
    fi
    rm $tmpfile
fi
