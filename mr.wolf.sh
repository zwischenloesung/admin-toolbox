#!/bin/bash -e
########################################################################
#** Version: 1.0
#* This script helps keeping a target directory clean. E.g. by cron:
#* `41 3 * * * [ -x /usr/local/bin/mr.wolf.sh ] && /usr/local/bin/mr.wolf.sh -a "last week" -f data.json -e /tmp"
#
# note: the frame for this script was auto-created with
# *https://github.com/inofix/admin-toolbox/blob/master/makebashscript.sh*
########################################################################
# author/copyright: <mic@inofix.ch>
# license: gladly sharing with the universe and any lifeform,
#          be it naturally born or constructed, alien or kin..
#          USE AT YOUR OWN RISK.
########################################################################
[ "$1" == "debug" ] && shift && set -x

## variables ##

### you may copy the following variables into this file for having your own
### local config ...
#conffile=.mr.wolf.sh

### {{{

dryrun=1
needsroot=1

target_dir=""
file_pattern=""
file_type=""
older_than=""
older_than_date=""
remove_empty=1
timestamp=".timestamp"

### }}}

# Unsetting this helper variable
_pre=""

# The system tools we gladly use. Thank you!
declare -A sys_tools
sys_tools=( ["_cat"]="/bin/cat"
            ["_date"]="/bin/date"
            ["_find"]="/usr/bin/find"
            ["_grep"]="/bin/grep"
            ["_id"]="/usr/bin/id"
            ["_touch"]="/usr/bin/touch" )
# this tools get disabled in dry-run and sudo-ed for needsroot
danger_tools=( "_cat" )
# special case sudo (not mandatory)
_sudo="/usr/bin/sudo"

## functions ##

print_usage()
{
    echo "usage: $0"
}

print_help()
{
    print_usage
    $_grep "^#\* " $0 | $_sed_forced 's;^#\*;;'
}

print_version()
{
    $_grep "^#\*\* " $0 | $_sed 's;^#\*\*;;'
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

## logic ##

## first set the system tools
for t in ${!sys_tools[@]} ; do
    if [ -x "${sys_tools[$t]##* }" ] ; then
        export ${t}="${sys_tools[$t]}"
    else
        error "Missing system tool: ${sys_tools[$t]##* } must be installed."
    fi
done

[ ! -f "/etc/$conffile" ] || . "/etc/$conffile"
[ ! -f "/usr/etc/$conffile" ] || . "/usr/etc/$conffile"
[ ! -f "/usr/local/etc/$conffile" ] || . "/usr/local/etc/$conffile"
[ ! -f ~/"$conffile" ] || . ~/"$conffile"
[ ! -f "$conffile" ] || . "$conffile"

#*  options:
while true ; do
    case "$1" in
#*      -c |--config conffile               alternative config file
        -c|--config)
            shift
            if [ -r "$1" ] ; then
                . $1
            else
                die " config file $1 does not exist."
            fi
        ;;
#*      -e |--toggle-remove-empty           remove/leave empty parent directories,
#*                                          do just the contrary of what the config
#*                                          sais (default w/o config: 'leave')
        -e|--toggle-remove-empty)
            if [ $remove_empty -eq 0 ] ; then
                remove_empty=1
            else
                remove_empty=0
            fi
        ;;
#*      -a |--find-file-age pattern         only consider files older than this
#*                                          (see `date -d ..`)
        -a|--find-file-age)
            shift
            if $_date -d "$1" 2>&1 > /dev/null ; then
                older_than_date="$1"
            else
                error "Could not create the timestamp $1"
            fi
        ;;
#*      -o |--find-older timestampfile      only consider files older than this
        -o|--find-older)
            shift
            if [ -f "$1" ] ; then
                older_than="! -newer $1 ! -name ${1##*/}"
            else
                error "Could not find regular timestamp file $1"
            fi
        ;;
#*      -f |--find-file-pattern pattern     only consider file names similar to
#*                                          (see `find <dir> -name ..`)
        -f|--find-file-pattern)
            shift
            file_pattern="-name $1"
        ;;
#*      -t |--find-file-type                only consider files of this type
#*                                          (see `find <dir> -type ..`)
        -t|--find-file-type)
            file_type=""
        ;;
#*      -h |--help                          print this help
        -h|--help)
            print_help
            exit 0
        ;;
#*      -n |--dry-run                       do not change anything
        -n|--dry-run)
            dryrun=0
        ;;
#*      -v |--version
        -v|--version)
            print_version
            exit
        ;;
#*      --                                  use target_dir from the config
        --)
            if [ -d "$target_dir" ] ; then
                break
            else
                error "Directory '$target_dir' not found."
            fi
        ;;
        -*|--*)
            error "option '$1' not supported"
        ;;
#*      targetdirectory                     the directory to clean up (mandatory)
        *)
            if [ -d "$1" ] ; then
                target_dir="$1"
                break
            else
                error "Directory '$1' not found.."
            fi
        ;;
    esac
    shift
done

if [ $dryrun -eq 0 ] ; then
    _pre="echo "
fi

if [ $needsroot -eq 0 ] ; then

    iam=$($_id -u)
    if [ $iam -ne 0 ] ; then
        if [ -x "$_sudo" ] ; then

            _pre="$_pre $_sudo"
        else
            error "Priviledges missing: use ${_sudo}."
        fi
    fi
fi

for t in ${danger_tools[@]} ; do
    export ${t}="$_pre ${sys_tools[$t]}"
done

[ ! -d "$target_dir" ] && error "No target directory provided.."

if [ -n "$older_than_date" ] ; then
    if [ -z "${timestamp%%*/}" ] ; then
        error "The temp file '$timestamp' must be at a valid location"
    fi
    if [ -n "${timestamp##/*}" ] ; then
        timestamp="$target_dir/$timestamp"
    fi
    if $_touch -d "$older_than_date" "$timestamp" ; then
        older_than="! -newer $timestamp ! -name ${timestamp##*/}"
    else
        error "Failed to create the temp file '$timestamp'"
    fi
fi

if [ $dryrun -eq 0 ] ; then
    echo "Not removing this files - try run"
    # always consider the pattern as find would
    set -f
    $_find $target_dir $file_type $older_than $file_pattern
    set +f
    if [ $remove_empty -eq 0 ] ; then
        echo "Not removing this directories - try run"
        $_find $target_dir -type d -empty $older_than
    fi
else
    # always consider the pattern as find would
    set -f
    $_find $target_dir $file_type $older_than $file_pattern -delete
    set +f
    if [ $remove_empty -eq 0 ] ; then
        $_find $target_dir -type d -empty $older_than -delete
    fi
fi

