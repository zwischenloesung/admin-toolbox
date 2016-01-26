#!/bin/bash -e
########################################################################
#** Version: 0.2
#* This script takes project based file hierarchy trees and
#* unifies them into one tree for a certain node. We use it to
#* build host based configs from role based hierarchies.
#*
#* But why do we do so? ;)
#* We started with cfengine to administrate our server landscape,
#* we even configured and administrated a mesh network based on
#* embedded boxes based on linux/ulibc-busybox and cfengine
#* at the time there was nothing else
#* out there. Later we managed to successfully refuse to work with
#* puppet, but nowadays there is debops (ansible), and salt that
#* we actually use and so we quickly started to read about reclass..
#*
#* For a project with the FU Berlin, the guys @MatheInfo kindly let us
#* use their salt-repository to administer our servers with them, but
#* we do not have access to their reclass inventory (for obvious reasons).
#* Furthermore we already have our configs organized for our own servers
#* and for other customers. This script serves now to translate our
#* storage solution (reclass inventory and config repository) into
#* the salt states for our hosts @MI.
#*
#* Maybe one day we rewrite this all in python..
#
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
conffile=~/.nodeify
### {{{

# whether to take action
dryrun=1
# whether we must run as root
needsroot=1

# rsync mode
rsync_options="-a -v -m --exclude='.keep'"

merge_only_this_subdir=""
default_merge_mode="dir"

# here you can store short hands for your project specific configs
inventorydir=""
targetdir=""

### }}}

# Unsetting this helper variables (sane defaults)
_pre=""
nodefilter=""
projectfilter=""

# The system tools we gladly use. Thank you!
declare -A sys_tools
sys_tools=( ["_awk"]="/usr/bin/awk"
            ["_cat"]="/bin/cat"
            ["_cp"]="/bin/cp"
            ["_find"]="/usr/bin/find"
            ["_grep"]="/bin/grep"
            ["_id"]="/usr/bin/id"
            ["_mkdir"]="/bin/mkdir"
            ["_pwd"]="/bin/pwd"
            ["_rm"]="/bin/rm"
            ["_rmdir"]="/bin/rmdir"
            ["_reclass"]="/usr/bin/reclass"
            ["_rsync"]="/usr/bin/rsync"
            ["_sed"]="/bin/sed"
            ["_sed_forced"]="/bin/sed"
            ["_tr"]="/usr/bin/tr" )
# this tools get disabled in dry-run and sudo-ed for needsroot
danger_tools=( "_cp" "_cat" "_dd" "_mkdir" "_sed" "_rm" "_rmdir" "_rsync" )
# special case sudo (not mandatory)
_sudo="/usr/bin/sudo"

## functions ##

print_usage()
{
    echo "usage: $0 [options] action"
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
# we need:
#  hostname(s)
#  targetdir
#  hosts roles file
#  target dir (might come from conffile)
#  (projectdirs from $conffile)
#  (roles from $conffile)
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

[ -r "$conffile" ] && . $conffile

#*  options:
while true ; do
    case "$1" in
#*      -c |--config conffile           alternative config file
        -c|--config)
            shift
            if [ -r "$1" ] ; then
                . $1
            else
                die " config file $1 does not exist."
            fi
        ;;
#*      -h |--help                      print this help
        -h|--help)
            print_help
            exit 0
        ;;
#*      -m |--merge mode                specify how to merge, available modes:
#*                                          dir     nodename based directories
#*                                          in      nodename infixed files
#*                                          pre     nodename prefixed files
#*                                          post    nodename postfixed files
        -m|--merge)
            shift
            default_merge_mode=$1
        ;;
#*      -n |--dry-run                   do not change anything
        -n|--dry-run)
            dryrun=0
        ;;
#*      -N |--node node                 only process a certain node
        -N|--node)
            shift
            nodefilter="$1"
        ;;
#*      -P |--project project           only process nodes from this project
        -P|--project)
            shift
            projectfilter="$1"
        ;;
#*      -r |--rsync-dry-run
        -r|--rsync-dry-run)
            rsync_options="$rsync_options -n"
        ;;
#*      -s |--subdir-only-merge         concentrate on this subdir only
        -s|--subdir-only-merge)
            shift
            merge_only_this_subdir=$1
        ;;
#*      -v |--version
        -v|--version)
            print_version
            exit
        ;;
        -*|--*)
            error "option $1 not supported"
        ;;
        *)
            break
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
            error "Missing system tool: $_sudo must be installed."
        fi
    fi
fi

for t in ${danger_tools[@]} ; do
    export ${t}="$_pre ${sys_tools[$t]}"
done

## define these in parse_node()
applications=()
classes=()
environement=""
project=""
storagedirs=()

parse_node()
{
    eval $(\
        $_reclass -b $inventorydir -n $1 |\
        $_awk 'BEGIN {mode="none"; list=""}; \
                !/- / { if (mode!="none"){ \
                    print mode"=( "list" )"; \
                    mode="none"; \
                    list=""}} \
                /^  node:/{sub("/.*", "", $2); print "project="$2}; \
                /^applications:$/{mode="applications"}; \
                /^classes:$/{mode="classes"}; \
                /^environment:/{mode="none"; \
                    print "environement="$2}; \
                /^  storage-dirs:$/{mode="storagedirs"}; \
                /- / {list=list " " $2}; \
                END {print applications}')
}

process_nodes()
{
    command=$1
    shift
    for n in $@ ; do

        if [ -n "$nodefilter" ] && [ "$nodefilter" != "$n" ] ; then
            continue
        fi
        parse_node $n
        $command $n
    done
}

list_node()
{
    output="\e[1;39m$n \e[1;36m($project)"
    if [ "$environement" == "development" ] ; then
         output="$output \e[1;32m$environement"
    elif [ "$environement" == "fallback" ] ; then
         output="$output \e[1;33m$environement"
    elif [ "$environement" == "productive" ] ; then
         output="$output \e[1;31m$environement"
    fi
    printf "$output\n"
}

list_node_stores()
{
    list_node $n
    for d in ${storagedirs[@]} ; do
        if [ -d "$d" ] ; then
            printf "\e[0;32m - $d\n"
        else
            printf "\e[0;33m - $d      MISSING!\n"
        fi
    done
}

merge_all()
{
    if [ ! -d "$targetdir" ] ; then
        die "Target directory '$targetdir' does not exist!"
    fi
    src_subdir=""
    trgt_subdir=""
    if [ -n "$merge_only_this_subdir" ] ; then
        src="$merge_only_this_subdir"
        trgt="$merge_only_this_subdir"
    fi
    case "$default_merge_mode" in
        dir|in|post|pre)
            for d in ${storagedirs[@]} ; do
                if [ -d "$d/$src" ] ; then
                    $_mkdir -p $targetdir/$n/$trgt/
                    $_rsync $rsync_options $d/$src/ $targetdir/$n/$trgt/
                fi
            done
        ;;&
        in)
            echo "do infix"
            for d in $($_find $targetdir/$n/ -type d) ; do
                echo "found dir $d"
            done
        ;;&
        post)
            echo "do postfix"
        ;;&
        pre)
            echo "do prefix"
        ;;&
        in|post|pre)
            echo "and this cleanup"
        ;;
        dir)
        ;;
        *)
            die "merge mode '$default_merge_mode' is not supported.."
        ;;
    esac
}

reclass_filter=""
if [ -n "$projectfilter" ] ; then
    if [ -d "$inventorydir/nodes/$projectfilter" ] ; then
        reclass_filter="-u nodes/$projectfilter"
    else
        die "This project does not exist in $inventorydir"
    fi
fi
nodes=( $($_reclass -b $inventorydir $reclass_filter -i |\
            $_awk 'BEGIN {node=1}; \
                   /^nodes:/ {node=0};\
                   /^  \w/ {if (node == 0) {print now $0}}' |\
            $_tr -d ":" ) )

#*  actions:
case $1 in
#*      list                            list nodes
    ls|list)
        process_nodes list_node ${nodes[@]}
    ;;
#*      storages                        show storage directories
    src|st*)
        process_nodes list_node_stores ${nodes[@]}
    ;;
#*      merge-all                       just merge all storage directories
    merge*)
        process_nodes merge_all ${nodes[@]}
    ;;
    *)
        print_usage
    ;;
esac

