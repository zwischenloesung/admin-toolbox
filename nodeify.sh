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
declare -A localdirs
### you may copy the following variables into this file for having your own
### local config ...
conffile=~/.nodeify
### {{{

# for status mode concentrate on this ip protocol
ipprot="-4"

# whether to take action
dryrun=1
# whether we must run as root
needsroot=1

# rsync mode
rsync_options="-a -v -m --exclude=.keep"

merge_only_this_subdir=""
merge_mode="dir"

# here you can store short hands for your project specific configs
inventorydir=""
targetdir=""

localdirs=()
### }}}

# Unsetting this helper variables (sane defaults)
_pre=""
classfilter=""
nodefilter=""
projectfilter=""

ansible_root=""
force=1

# The system tools we gladly use. Thank you!
declare -A sys_tools
sys_tools=( ["_awk"]="/usr/bin/gawk"
            ["_basename"]="/usr/bin/basename"
            ["_cat"]="/bin/cat"
            ["_cp"]="/bin/cp"
            ["_dirname"]="/usr/bin/dirname"
            ["_find"]="/usr/bin/find"
            ["_grep"]="/bin/grep"
            ["_id"]="/usr/bin/id"
            ["_ip"]="/bin/ip"
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
            ["_sort"]="/usr/bin/sort"
            ["_ssh"]="/usr/bin/ssh"
            ["_tr"]="/usr/bin/tr"
            ["_wc"]="/usr/bin/wc" )
# this tools get disabled in dry-run and sudo-ed for needsroot
danger_tools=( "_cp" "_cat" "_dd" "_mkdir" "_sed" "_rm" "_rmdir" "_rsync" )
# special case sudo (not mandatory)
_sudo="/usr/bin/sudo"

declare -A opt_sys_tools
opt_sys_tools=( ["_ansible"]="/usr/bin/ansible" )
opt_danger_tools=( "_ansible" )

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

for t in ${!opt_sys_tools[@]} ; do
    if [ -x "${opt_sys_tools[$t]##* }" ] ; then
        export ${t}="${opt_sys_tools[$t]}"
    else
        echo "Warning! Missing system tool: ${opt_sys_tools[$t]##* }."
    fi
done

[ -r "$conffile" ] && . $conffile

#* options:
while true ; do
    case "$1" in
#*  -c |--config conffile           alternative config file
        -c|--config)
            shift
            if [ -r "$1" ] ; then
                . $1
            else
                die " config file $1 does not exist."
            fi
        ;;
#*  -C |--class class               only process member nodes of this class
#*                                  (see reclass classes)
    -C|--class)
        shift
        classfilter="$1"
    ;;
#*  -f |--force                     do not ask before changing anything
    -f|--force)
        force=0
    ;;
#*  -h |--help                      print this help
        -h|--help)
            print_help
            exit 0
        ;;
#*  -m |--merge mode                specify how to merge, available modes:
#*                                    custom based on "re-merge-custom:"
#*                                    dir    nodename based dirs (default)
#*                                    in     nodename infixed files
#*                                    pre    nodename prefixed files
#*                                    post   nodename postfixed files
        -m|--merge)
            shift
            merge_mode=$1
        ;;
#*  -n |--dry-run                   do not change anything
        -n|--dry-run)
            dryrun=0
        ;;
#*  -N |--node node                 only process a certain node
        -N|--node)
            shift
            nodefilter="$1"
        ;;
#*  -P |--project project           only process nodes from this project,
#*                                  which practically is the node namespace
#*                                  from reclass (directory hierarchy)
        -P|--project)
            shift
            projectfilter="$1"
        ;;
#*  -r |--rsync-dry-run
        -r|--rsync-dry-run)
            rsync_options="$rsync_options -n"
        ;;
#*  -s |--subdir-only-merge         concentrate on this subdir only
        -s|--subdir-only-merge)
            shift
            merge_only_this_subdir=$1
        ;;
#*  -S |--ansible-become-root       Ansible: Use --become-user root -K
        -S|--ansible-bec*)
            ansible_root="--become-user root -K"
        ;;
#*  -v |--version
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

for t in ${opt_danger_tools[@]} ; do
    [ -z "${!t}" ] || export ${t}="$_pre ${opt_sys_tools[$t]}"
done

## define these in parse_node()
applications=()
classes=()
environement=""
hostinfrastructure=""
hostlocation=""
hosttype=""
project=""
storagedirs=()
remergedirect=()
declare -A remergecustomsrc
remergecustomsrc=()
declare -A remergecustomdest
remergecustomdest=()

parse_node()
{
    # make sure they are empty
    applications=()
    classes=()
    environement=""
    hostinfrastructure=""
    hostlocation=""
    hosttype=""
    os_name=""
    os_codename=""
    os_distro=""
    os_release=""
    project=""
    storagedirs=()
    remergedirect=()
    remergecustomsrc=()
    remergecustomdest=()

    awk_var_p_keys=";"
    awk_var_p_vals=";"
    for k in ${!localdirs[@]} ; do
        awk_var_p_keys="$k;$awk_var_p_keys"
        awk_var_p_vals="${localdirs[$k]};$awk_var_p_vals"
    done
    OLDIFS=$IFS
    IFS="
"
    eval $(\
        $_reclass -b $inventorydir -n $1 |\
        $_awk -v p_len=${#localdirs[@]} -v p_keys=$awk_var_p_keys \
              -v p_vals=$awk_var_p_vals \
            'BEGIN {
                hostname="'$hostname'"
                domainname="'$domainname'"
                fqdn="'$n'"
                split(p_keys, project_keys, ";")
                split(p_vals, project_vals, ";")
                for (i=1;i<=p_len;i++) {
                    projects[project_keys[i]]=project_vals[i]
                }
                metamode="reclass"
                mode="none"
                rckey=""
                list=""
            }
            #sanitize input a little
            /<|>|\$|\|`/ {
                next
            }
            /{{ .* }}/ {
                gsub("{{ hostname }}", hostname)
                gsub("{{ domainname }}", domainname)
                gsub("{{ fqdn }}", fqdn)
                for (var in projects) {
                    gsub("{{ "var" }}", projects[var])
                }
            }
            !/^ *- / || /:$/ {
                tmp=$0
                sub("\\S.*", "", tmp)
                numspaces=length(tmp)
                tmp=metamode
                numcolons=gsub(":", "", tmp)
                while ( numcolons >= numspaces/2 ) {
                    sub(":\\w*$", "", metamode)
                    numcolons--
                }
                if (( mode != "none" ) && ( list != "" )) {
                    print mode"=( "list" )"
                    mode="none"
                    list=""
                }
            }
            /^  node:/ {
                if ( metamode == "reclass" ) {
                  sub("/.*", "", $2)
                  print "project="$2
                  next
                }
            }
            /^applications:$/ {
                metamode="none"
                mode="applications"
                next
            }
            /^classes:$/ {
                metamode="none"
                mode="classes"
                next
            }
            /^environment:/ {
                metamode="none"
                mode="none"
                print "environement="$2
                next
            }
            /^parameters:/ {
                metamode="parameters"
                mode="none"
            }
            /^  os:/ {
                if ( metamode == "parameters" ) {
                  mode="none"
                  print "os_name="$2
                }
                next
            }
            /^  os.distro:/ {
                if ( metamode == "parameters" ) {
                  mode="none"
                  print "os_distro="$2
                }
                next
            }
            /^  os.codename:/ {
                if ( metamode == "parameters" ) {
                  mode="none"
                  print "os_codename="$2
                }
                next
            }
            /^  os.release:/ {
                if ( metamode == "parameters" ) {
                  mode="none"
                  print "os_release="$2
                }
                next
            }
            /^  host.infrastructure:/ {
                if ( metamode == "parameters" ) {
                  mode="none"
                  l=length($1)
                  print "hostinfrastructure=\""substr($0, l+4)"\""
                }
                next
            }
            /^  location:/ {
                if ( metamode == "parameters" ) {
                  mode="none"
                  l=length($1)
                  print "hostlocation=\""substr($0, l+4)"\""
                }
                next
            }
            /^  host.type:/ {
                if ( metamode == "parameters" ) {
                  mode="none"
                  l=length($1)
                  print "hosttype=\""substr($0, l+4)"\""
                }
                next
            }
            /^  role:/ {
                if ( metamode == "parameters" ) {
                  mode="none"
                  print "role="$2
                }
                next
            }
            /^  debian_.*_packages:$/ {
                if ( metamode == "parameters" ) {
                  mode=substr($1, 0, length($1)-1)
                }
                next
            }
            /^  storage-dirs:$/ {
                if ( metamode == "parameters" ) {
                  mode="storagedirs"
                }
                next
            }
            /^  re-merge:$/ {
                if ( metamode == "parameters" ) {
                    metamode=metamode":remerge"
                }
            }
            /^    direct:$/ {
                if ( metamode == "parameters:remerge" ) {
                  mode="remergedirect"
                }
                next
            }
            /^    custom:$/ {
                if ( metamode == "parameters:remerge" ) {
                    metamode=metamode":custom"
                    mode="remergecustom"
                }
                next
            }
            /^      .*:$/ {
                if ( mode == "remergecustom" ) {
                    rckey=$1
                    sub(":", "", rckey)
                }
                next
            }
            /^        file: .*$/ {
                if (( mode == "remergecustom" ) && ( rckey != "" )) {
                    gsub("\047", "");
                    print "remergecustomsrc[\""rckey"\"]=\""$2"\""
                }
                next
            }
            /^        dest: .*$/ {
                if (( mode == "remergecustom" ) && ( rckey != "" )) {
                    gsub("\047", "");
                    print "remergecustomdest[\""rckey"\"]=\""$2"\""
                }
                next
            }
            /^ *- / {
                list=list " " $2
                next
            }
            {
                mode="none"
            }
            END {
            }'
    )
    IFS=$OLDIFS
}

connect_node()
{
    list_node $n
    retval=0
    remote_os=( $( $_ssh $1 $_lsb_release -d 2>/dev/null) ) || retval=$?
    remote_os_distro=${remote_os[1]}
    remote_os_name=${remote_os[2]}
    remote_os_release=${remote_os[3]}
    remote_os_codename=${remote_os[4]}
    answer0="${remote_os[1]} ${remote_os[2]} ${remote_os[3]} ${remote_os[4]}"
    if [ $retval -gt 127 ] ; then
        printf " \e[1;31m${answer0}\n"
    elif [ $retval -gt 0 ] ; then
        printf " \e[1;33m${answer0}\n"
    else
        distro_color="\e[0;32m"
        os_color="\e[0;32m"
        release_color="\e[0;32m"
        codename_color="\e[0;32m"
        if [ -n "$os_distro" ] ; then
            comp0=$( echo $remote_os_distro | $_sed 's;.*;\L&;' )
            comp1=$( echo $os_distro | $_sed 's;.*;\L&;' )
            if [ "$comp0" == "$comp1" ] ; then
                distro_color="\e[1;32m"
            else
                distro_color="\e[1;31m"
            fi
        fi
        if [ -n "$os_release" ] ; then
            comp0=$( echo $remote_os_release | $_sed 's;.*;\L&;' )
            comp1=$( echo $os_release | $_sed 's;.*;\L&;' )
            if [ "$comp0" == "$comp1" ] ; then
                release_color="\e[1;32m"
            else
                release_color="\e[1;31m"
            fi
        fi
        if [ -n "$os_codename" ] ; then
            comp0=$( echo $remote_os_codename | $_sed 's;.*;\L&;' )
            comp1=$( echo $os_codename | $_sed 's;.*;\L&;' )
            if [ "$comp0" == "($comp1)" ] ; then
                codename_color="\e[1;32m"
            else
                codename_color="\e[1;31m"
            fi
        fi
        printf "  $distro_color$remote_os_distro\e[0;39m"
        printf " $os_color$remote_os_name\e[0;39m"
        printf " $release_color$remote_os_release\e[0;39m"
        printf " $codename_color$remote_os_codename\n\e[0;39m"
        answer1=$( $_ssh $1 $_ip $ipprot address show eth0 | $_grep inet)
        printf "\e[0;32m$answer1\n\e[0;39m"
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

list_node_short()
{
    printf "$n\n"
}

list_node()
{
    output="\e[1;39m$n \e[1;36m($environement:$project)"
    if [ "$role" == "development" ] ; then
         output="$output \e[1;32m$role"
    elif [ "$role" == "fallback" ] ; then
         output="$output \e[1;33m$role"
    elif [ "$role" == "productive" ] ; then
         output="$output \e[1;31m$role"
    else
         output="$output \e[1;39m$role"
    fi
    if [ -n "$os_distro" ] && [ -n "$os_codename" ] &&
            [ -n "$os_release" ] ; then
        os_output="\e[1;34m($os_distro-$os_codename $os_release)"
    elif [ -n "$os_distro" ] && [ -n "$os_codename" ] ; then
        os_output="\e[1;34m($os_distro-$os_codename)"
    elif [ -n "$os_distro" ] && [ -n "$os_release" ] ; then
        os_output="\e[1;34m($os_distro $os_release)"
    fi
    output="$output $os_output"
    printf "$output\e[0;39m\n"
}

list_distro_packages()
{
    list_node $n
    ps=( $(eval 'echo ${'${os_name}'__packages[@]}') )
    ps=( ${ps[@]} $(eval 'echo ${'${os_name}'_'${os_version}'_packages[@]}') )
    ps=( $( for p in ${ps[@]} ; do echo $p ; done | $_sort -u ) )
    for p in ${ps[@]} ; do
        printf "\e[0;33m - ${p}\n"
    done
}

list_applications()
{
    list_node $n
    for a in ${applications[@]} ; do
        printf "\e[0;33m - $a\n"
    done
}

list_classes()
{
    list_node $n
    for c in ${classes[@]} ; do
        printf "\e[0;33m - $c\n"
    done
}

list_node_stores()
{
    list_node $n
    list_node_arrays ${storagedirs[@]}
}

list_node_re_merge_exceptions()
{
    list_node $n
    list_node_arrays ${remergedirect[@]}
}

list_node_re_merge_custom()
{
    list_node $n
    list_re_merge_custom
}

list_node_type()
{
    list_node $n
    printf "\e[0;33m This host is a \e[1;33m${hosttype}\e[0;33m.\n"
    [ -n "$hostinfrastructure" ] &&
        printf " It is running on \e[1;33m${hostinfrastructure}\e[0;33m.\n" ||
        true
    [ -n "$hostlocation" ] &&
        printf " The ${hosttype} is located at "
        printf "\e[1;33m$hostlocation\e[0;33m.\n" ||
        true
}

list_re_merge_custom()
{
    for m in ${!remergecustomsrc[@]} ; do
        printf "\e[1;33m - $m\n"
        printf "\e[0;33m   file: \e[0;35m${remergecustomsrc[$m]}\n"
        printf "\e[0;33m   dest: \e[0;36m${remergecustomdest[$m]}\n"
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
process_applications()
{
    for a in ${applications[@]} ; do
        applications_dict[$a]=$n:${applications_dict[$a]}
    done
}

declare -A classes_dict
process_classes()
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

    for m in ${!remergecustomsrc[@]} ; do

        if [ -e "$1/${remergecustomsrc[$m]}" ] ; then

            $_mkdir -p ${remergecustomdest[$m]%/*}
            $_cp $1/${remergecustomsrc[$m]} ${remergecustomdest[$m]}
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
        $_mv $f $targetdir/$targetpath/${prefix}.${n}$suffix
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
        $_mv $f $targetdir/$targetpath/${n}.${basename}
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
        $_mv $f $targetdir/$targetpath/${basename}.${in}
    done
}

re_merge_exceptions_first()
{
    for f in ${remergedirect[@]} ; do
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
    case "$merge_mode" in
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
            re_merge_fix_$merge_mode $t

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
            die "merge mode '$merge_mode' is not supported.."
        ;;
    esac
}

[ -d "$inventorydir/nodes" ] || error "reclass environment not found at $inventorydir/nodes"
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

#* actions:
case $1 in
    ansible-*|put|fetch)
        [ -n "$_ansible" ] || error "Missing system tool: ansible."

        if [ -n "$nodefilter" ] && [ -n "${nodefilter//*\.*/}" ] ; then
            nodefilter="${nodefilter}*"
        fi
        if [ -n "$classfilter" ] && [ -n "$nodefilter" ] ; then
            hostpattern="$classfilter,$nodefilter"
        elif [ -n "$classfilter" ] ; then
            hostpattern="$classfilter"
        elif [ -n "$nodefilter" ] ; then
            hostpattern="$nodefilter"
        else
            error "No class or node was specified.."
        fi
    ;;&
#*  ansible-put src dest            ansible oversimplified copy module wrapper
#*                                  'src' is /path/file on local host
#*                                  'dest' is /path/.. on remote host
    ansible-put|put)

        src=$2
        dest=$3

        owner="" ; [ -z "$4" ] || owner="owner=$4"
        mode="" ; [ -z "$5" ] || mode="mode=$5"

        echo "wrapping $_ansible $hostpattern $ansible_root -m copy -a 'src=$src dest=$dest' $owner $mode"
        if [ 0 -ne "$force" ] ; then
            echo "Press <Enter> to continue <Ctrl-C> to quit"
            read
        fi
        $_ansible $hostpattern $ansible_root -m copy -a "src=$src dest=$dest" $owner $mode
    ;;
#*  ansible-fetch src dest [flat]   ansible oversimplified fetch module wrapper
#*                                  'src' is /path/file on remote host
#*                                  'dest' is /path/ on local side
#*                                  without 'flat' hostname is namespace
#*                                  else use 'flat' instead of hostname
#*                                  for destination path which looks like
#*                                  localhost:/localpath/namespace/path/file
    ansible-fetch|fetch)

        src=$2
        dest=$3

        flat=""
        if [ -n "$4" ] ; then

            dest=$dest/$4/$src
            flat="flat=true"
        fi

        echo "wrapping $_ansible $hostpattern $ansible_root -m fetch -a 'src=$src dest=$dest $flat'"
        if [ 0 -ne "$force" ] ; then
            echo "Press <Enter> to continue <Ctrl-C> to quit"
            read
        fi
        $_ansible $hostpattern $ansible_root -m fetch -a "src=$src dest=$dest $flat"
    ;;
    *)
        if [ -n "$classfilter" ] ; then
            process_nodes process_classes ${nodes[@]}
            nodes=()
            for a in ${classes_dict[$classfilter]//:/ } ; do
                nodes=( ${nodes[@]} $a )
            done
        fi
    ;;&
#*  applications-list (als)         list hosts sorted by applications
    als|app*)
        process_nodes process_applications ${nodes[@]}
        for a in ${!applications_dict[@]} ; do
            printf "\e[1;34m[$a]\n"
            for h in ${applications_dict[$a]//:/ } ; do
                printf "\e[0;32m$h\n"
            done
        done
    ;;
#*  help                            print this help
    help)
        print_help
    ;;
#*  shortlist (l)                   list nodes - but just the hostname
    l|shortlist)
        process_nodes list_node_short ${nodes[@]}
    ;;
#*  list (ls)                       list nodes
    ls|list*)
        process_nodes list_node ${nodes[@]}
    ;;
#*  list-applications (lsa)         list applications sorted by hosts
    lsa|list-a*)
        process_nodes list_applications ${nodes[@]}
    ;;
#*  list-classes (lsc)              list classes sorted by hosts
    lsc|list-c*)
        process_nodes list_classes ${nodes[@]}
    ;;
#*  classes-list (cls)              list hosts sorted by class
    cls|class*)
        process_nodes process_classes ${nodes[@]}
        for a in ${!classes_dict[@]} ; do
            printf "\e[1;35m[$a]\n"
            for h in ${classes_dict[$a]//:/ } ; do
                printf "\e[0;32m$h\n"
            done
        done
    ;;
    lsp)
        process_nodes list_distro_packages ${nodes[@]}
    ;;
#*  list-merge-customs (lsmc)       show custom merge rules
    lsmc|list-merge-c*)
        process_nodes list_node_re_merge_custom ${nodes[@]}
    ;;
#*  list-merge-exceptions (lsme)    show exceptions for merge modes
    lsme|list-merge-e*)
        process_nodes list_node_re_merge_exceptions ${nodes[@]}
    ;;
#*  list-storage (lss)              show storage directories
    lss|list-storage)
        process_nodes list_node_stores ${nodes[@]}
    ;;
#*  list-types (lst)                show maschine type and location
    lst|list-types)
        process_nodes list_node_type ${nodes[@]}
    ;;
#*  merge-all (mg)                  just merge all storage directories - flat
    merge|merge-a*|mg)
        process_nodes merge_all ${nodes[@]}
    ;;
#*  merge-custom (mc)               merge after custom rules defined in reclass
    merge-cu*|mc)
        merge_mode="custom"
        process_nodes merge_all ${nodes[@]}
    ;;
#*  merge-pre (mpr)                 merge storage dirs and prefix with hostname
    merge-pr*|mpr)
        merge_mode="pre"
        process_nodes merge_all ${nodes[@]}
    ;;
#*  merge-in (mi)                   merge storage dirs and infix with hostname
    merge-i*|mi)
        merge_mode="in"
        process_nodes merge_all ${nodes[@]}
    ;;
#*  merge-post (mpo)                merge storage dirs and postfix with
#*                                  hostname
    merge-po*|mpo)
        merge_mode="post"
        process_nodes merge_all ${nodes[@]}
    ;;
#*  re-merge                        remerge as specified in '--merge mode'
#    rem|re-merge*)
#        process_nodes re-merge ${nodes[@]}
#    ;;
#*  reclass                         just wrap reclass
    rec*)
        if [ -n "$nodefilter" ] ; then
            nodefilter=$($_find -L $inventorydir/nodes/ -name "$nodefilter" -o -name "${nodefilter}\.*" | $_sed -e 's;.yml;;' -e 's;.*/;;')

            if [ -n "$nodefilter" ] ; then
                reclassmode="-n $nodefilter"
            else
                error "The node does not seem to exist: $nodefilter"
            fi
        else
            reclassmode="-i"
        fi
        $_reclass -b $inventorydir $reclassmode
    ;;
#*  search variable                 show in which file a variable is configured
    search)
        shift
        printf "\e[1;33mSearch string is found in nodes:\e[0m\n"
        $_grep --color -Hn -R -e "^$1:" -e "\s$1:" -e "\${$1}" -e "{{ $1 }}" $inventorydir/nodes || true
        printf "\e[1;33mSearch string is found in classes:\e[0m\n"
        $_grep --color -Hn -R -e "^$1:" -e "\s$1:" -e "\${$1}" -e "{{ $1 }}" $inventorydir/classes || true
    ;;
#*  search-all                      show what variables are used
    search-all)
        printf "\e[1;33mSearch string is found in nodes:\e[0m\n"
        $_grep --color -Hn -R -e "^$1:" -e "\s$1:" -e "\${.*}" -e "{{ .* }}" $inventorydir/nodes || true
        printf "\e[1;33mSearch string is found in classes:\e[0m\n"
        $_grep --color -Hn -R -e "^$1:" -e "\s$1:" -e "\${.*}" -e "{{ .* }}" $inventorydir/classes || true
    ;;
#*  search-external variable        show in which file an external {{ variable }} is configured
    search-external)
        shift
        printf "\e[1;33mSearch string is found in nodes:\e[0m\n"
        $_grep --color -Hn -R -e "{{ $1 }}" $inventorydir/nodes || true
        printf "\e[1;33mSearch string is found in classes:\e[0m\n"
        $_grep --color -Hn -R -e "{{ $1 }}" $inventorydir/classes || true
    ;;
#*  search-external-all             show what external {{ variables }} are used
    search-external-all)
        printf "\e[1;33mSearch string is found in nodes:\e[0m\n"
        $_grep --color -Hn -R -e "{{ .* }}" $inventorydir/nodes || true
        printf "\e[1;33mSearch string is found in classes:\e[0m\n"
        $_grep --color -Hn -R -e "{{ .* }}" $inventorydir/classes || true
    ;;
#*  search-reclass variable         show in which file a ${variable} is configured
    search-reclass)
        shift
        printf "\e[1;33mSearch string is found in nodes:\e[0m\n"
        $_grep --color -Hn -R -e "^$1:" -e "\s$1:" -e "\${$1}" $inventorydir/nodes || true
        printf "\e[1;33mSearch string is found in classes:\e[0m\n"
        $_grep --color -Hn -R -e "^$1:" -e "\s$1:" -e "\${$1}" $inventorydir/classes || true
    ;;
#*  search-reclass-all              show what ${variables} are used
    search-reclass-all)
        printf "\e[1;33mSearch string is found in nodes:\e[0m\n"
        $_grep --color -Hn -R -e "^$1:" -e "\s$1:" -e "\${.*}" $inventorydir/nodes || true
        printf "\e[1;33mSearch string is found in classes:\e[0m\n"
        $_grep --color -Hn -R -e "^$1:" -e "\s$1:" -e "\${.*}" $inventorydir/classes || true
    ;;
#*  status (ss)                     test host by ssh and print distro and ip(s)
    ss|status)
        process_nodes connect_node ${nodes[@]}
    ;;
    *)
        print_usage
    ;;
esac

