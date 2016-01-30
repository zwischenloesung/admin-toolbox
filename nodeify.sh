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
declare -A projectdirs
### you may copy the following variables into this file for having your own
### local config ...
conffile=~/.nodeify
### {{{

# whether to take action
dryrun=1
# whether we must run as root
needsroot=1

# rsync mode
rsync_options="-a -v -m --exclude=.keep"

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
            ["_basename"]="/usr/bin/basename"
            ["_cat"]="/bin/cat"
            ["_cp"]="/bin/cp"
            ["_dirname"]="/usr/bin/dirname"
            ["_find"]="/usr/bin/find"
            ["_grep"]="/bin/grep"
            ["_id"]="/usr/bin/id"
            ["_lsb_release"]="/usr/bin/lsb_release"
            ["_mkdir"]="/bin/mkdir"
            ["_mv"]="/bin/mv"
            ["_pwd"]="/bin/pwd"
            ["_rm"]="/bin/rm"
            ["_rmdir"]="/bin/rmdir"
            ["_reclass"]="/usr/bin/reclass"
            ["_rsync"]="/usr/bin/rsync"
            ["_sed"]="/bin/sed"
            ["_sed_forced"]="/bin/sed"
            ["_ssh"]="/usr/bin/ssh"
            ["_tr"]="/usr/bin/tr"
            ["_wc"]="/usr/bin/wc" )
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
#*                                        custom based on "re-merge-custom:"
#*                                        dir    nodename based dirs (default)
#*                                        in     nodename infixed files
#*                                        pre    nodename prefixed files
#*                                        post   nodename postfixed files
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
remergeexceptions=()
declare -A remergecustom
remergecustom=()

parse_node()
{
    awk_var_p_keys=";"
    awk_var_p_vals=";"
    for k in ${!projectdirs[@]} ; do
        awk_var_p_keys="$k;$awk_var_p_keys"
        awk_var_p_vals="${projectdirs[$k]};$awk_var_p_vals"
    done
    awk_vars="-v p_len=${#projectdirs[@]} -v p_keys=$awk_var_p_keys -v p_vals=$awk_var_p_vals"
    eval $(\
        $_reclass -b $inventorydir -n $1 |\
        $_awk $awk_vars \
            'BEGIN {
                hostname="'$hostname'"
                domainname="'$domainname'"
                fqdn="'$n'"
                split(p_keys, project_keys, ";")
                split(p_vals, project_vals, ";")
                for (i=1;i<=p_len;i++) {
                    projects[project_keys[i]]=project_vals[i]
                }
                mode="none"
                list=""
            }
            #sanitize input a little
            /<|>|\$|\|/ {
                next
            }
            /_{{ .* }}_/ {
                gsub("_{{ hostname }}_", hostname)
                gsub("_{{ domainname }}_", domainname)
                gsub("_{{ fqdn }}_", fqdn)
                for (var in projects) {
                    gsub("_{{ "var" }}_", projects[var])
                }
            }
            !/^ *- |^    / {
                if (mode!="none"){
                    print mode"=( "list" )"
                    mode="none"
                    list=""
                }
            }
            /^  node:/ {
                sub("/.*", "", $2)
                print "project="$2
                next
            }
            /^applications:$/ {
                mode="applications"
                next
            }
            /^classes:$/ {
                mode="classes"
                next
            }
            /^environment:/ {
                mode="none"
                print "environement="$2
                next
            }
            /^  storage-dirs:$/ {
                mode="storagedirs"
                next
            }
            /^  re-merge-exceptions:$/ {
                mode="remergeexceptions"
                next
            }
            /^  re-merge-custom:$/ {
                mode="remergecustom"
                next
            }
            /^ *- / {
                list=list " " $2
                next
            }
            /^    / {
                if (mode == "remergecustom") {
                    sub(":", "", $1)
                    list=list " [\""$1"\"]=\""$2"\""
                }
                next
            }
            {
                mode="none"
            }
            END {
            }'
    )
}

connect_node()
{
    list_node $n
    retval=0
    answer=$( $_ssh $1 $_lsb_release -d 2>&1) || retval=$?
    if [ $retval -gt 127 ] ; then
        printf " \e[1;31m$answer\n"
    elif [ $retval -gt 0 ] ; then
        printf " \e[1;33m$answer\n"
    else
        printf " \e[1;32m$answer\n"
    fi
}

process_nodes()
{
    command=$1
    shift
    for n in $@ ; do
        if [ -n "$nodefilter" ] && [ "$nodefilter" != "$n" ] &&
                [ "$nodefilter" != "${n%%.*}" ]  ; then
            continue
        fi
        hostname="${n%%.*}"
        domainname="${n#*.}"
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
    list_node_arrays ${storagedirs[@]}
}

list_node_re_merge_exceptions()
{
    list_node $n
    list_node_arrays ${remergeexceptions[@]}
}

list_node_re_merge_custom()
{
    list_node $n
    list_node_dict ${!remergecustom[@]}
}

list_node_dict()
{
    for m in $@ ; do
        printf "\e[0;36m   $m: \e[0;35m ${remergecustom[$m]}\n"
    done
}

list_node_arrays()
{
    for d in $@ ; do
        if [ -d "$d" ] ; then
            printf "\e[0;32m - $d\n"
        else
            printf "\e[0;33m ! $d \n"
        fi
    done
}

declare -A applications_dict
list_applications()
{
    for a in ${applications[@]} ; do
        applications_dict[$a]=$n:${applications_dict[$a]}
    done
}

declare -A classes_dict
list_classes()
{
    for c in ${classes[@]} ; do
        classes_dict[$c]=$n:${classes_dict[$c]}
    done
}

do_sync()
{
    if [ -d "$1" ] ; then
        $_mkdir -p $2
        $_rsync $rsync_options $1 $2
    fi
}

re_merge_custom()
{
    #better safe than sorry
    [ -n "$1" ] || error "ERROR: Source directory was empty!"
    [ "${1/*$n*/XXX}" == "XXX" ] || error "ERROR: Source directory was $1"
    for f in $($_find $1 -type f) ; do
        k="/${f/$1}"
        if [ -n "${remergecustom[$k]}" ] ; then
            echo $_mkdir -p $($_dirname $targetdir/${remergecustom[$k]})
            echo $_mv -i $f $targetdir/${remergecustom[$k]}
        fi
    done
}

re_merge_fix_in()
{
    #better safe than sorry
    [ -n "$1" ] || error "ERROR: Source directory was empty!"
    [ "${1/*$n*/XXX}" == "XXX" ] || error "ERROR: Source directory was $1"
# TODO maybe we want to ask for what to do with links..
    for f in $($_find $1 -type f) ; do
        basename=$($_basename $f)
        fullpath=${f%%$basename}
        targetpath=${fullpath/$1}
        suffix=$(echo $basename | $_grep '\w\.' | $_sed 's/.*\.//')
        prefix=${basename/.$suffix}
        [ -n "$suffix" ] && suffix=".$suffix"
        $_mv $f $targetdir/$targetpath/${prefix}_${n}$suffix
    done
}

re_merge_fix_pre()
{
    #better safe than sorry
    [ -n "$1" ] || error "ERROR: Source directory was empty!"
    [ "${1/*$n*/XXX}" == "XXX" ] || error "ERROR: Source directory was $1"
# TODO maybe we want to ask for what to do with links..
    for f in $($_find $1 -type f) ; do
        basename=$($_basename $f)
        fullpath=${f%%$basename}
        targetpath=${fullpath/$1}
        $_mv $f $targetdir/$targetpath/${basename}_$n
    done
}

re_merge_fix_post()
{
    #better safe than sorry
    [ -n "$1" ] || error "ERROR: Source directory was empty!"
    [ "${1/*$n*/XXX}" == "XXX" ] || error "ERROR: Source directory was $1"
# TODO maybe we want to ask for what to do with links..
    for f in $($_find $1 -type f) ; do
        basename=$($_basename $f)
        fullpath=${f%%$basename}
        targetpath=${fullpath/$1}
        $_mv $f $targetdir/$targetpath/${n}_$basename
    done
}

re_merge_exceptions_first()
{
    for f in ${remergeexceptions[@]} ; do
        $_mv $2/$1/$f $2/$f
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
        dir|in|post|pre|custom)
            for d in ${storagedirs[@]} ; do
                do_sync "$d/$src/" "$targetdir/$n/$trgt/"
            done
        ;;&
        dir)
        ;;
        in|post|pre)
            t="$targetdir/$n/"
            for d in $($_find $t -type d) ; do
                $_mkdir -p $targetdir/${d/$t/}
            done
            re_merge_exceptions_first $n $targetdir
            re_merge_fix_$default_merge_mode $t

            t="${t}*"
# TODO maybe we want to ask for what to do with links..
            for f in $($_find $t -type l) ; do
                $_rm $f
            done
            for d in $($_find $t -depth -type d) ; do
                $_rmdir ${d}
            done
        ;;
        custom)
            re_merge_custom $targetdir/$n/
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
#*      help                            print this help
    help)
        print_help
    ;;
#*      list (ls)                       list nodes
    ls|list*)
        process_nodes list_node ${nodes[@]}
    ;;
#*      list-applications (lsa)         show hosts sorted by application
    lsa|list-a*)
        process_nodes list_applications ${nodes[@]}
        for a in ${!applications_dict[@]} ; do
            printf "\e[1;39m[$a]\n"
            for h in ${applications_dict[$a]//:/ } ; do
                printf "\e[0;32m$h\n"
            done
        done
    ;;
#*      list-classes (lsc)              show hosts sorted by class
    lsc|list-c*)
        process_nodes list_classes ${nodes[@]}
        for a in ${!classes_dict[@]} ; do
            printf "\e[1;39m[$a]\n"
            for h in ${classes_dict[$a]//:/ } ; do
                printf "\e[0;32m$h\n"
            done
        done
    ;;
#*      list-re-merge-customs (lsrc)    show custom merge rules
    lsrc|list-rc*)
        process_nodes list_node_re_merge_custom ${nodes[@]}
    ;;
#*      list-re-merge-exceptions (lsre) show exceptions for merge modes
    lsre|list-re*)
        process_nodes list_node_re_merge_exceptions ${nodes[@]}
    ;;
#*      list-storage (lss)              show storage directories
    lss|list-storage)
        process_nodes list_node_stores ${nodes[@]}
    ;;
#*      merge-all                       just merge all storage directories
    merge*)
        process_nodes merge_all ${nodes[@]}
    ;;
##*      re-merge                        remerge as specified in '--merge mode'
#    rem|re-merge*)
#        process_nodes re-merge ${nodes[@]}
#    ;;
    status)
        process_nodes connect_node ${nodes[@]}
    ;;
    *)
        print_usage
    ;;
esac

