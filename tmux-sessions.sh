#!/bin/bash -e
########################################################################
#** Version: 0.9
#* This script stores and restores tmux sessions.
#
########################################################################
# author/copyright: <michael.lustenberger@inofix.ch>
# license: gladly sharing with the universe and any lifeform,
#          be it naturally born or constructed, alien or kin..
#          USE AT YOUR OWN RISK.
########################################################################
[ "$1" == "debug" ] && shift && set -x

## variables ##

### you may copy the following variables into this file for having your own
### local config ...
#conffile=~/.tmux-sessions.sh

### {{{

confdir=~/.tmux-sessions/
nogroup="nogroup"
rm_interactive=0
verbose=0
favorite_term="/usr/bin/urxvt -fn 6x13 +sb -tr -bg black -fg white -sh 60 -sl 10000"

### }}}

# The system tools we gladly use. Thank you!
declare -A sys_tools
sys_tools=( ["_awk"]="/usr/bin/awk"
            ["_basename"]="/usr/bin/basename"
            ["_cat"]="/bin/cat"
            ["_cut"]="/usr/bin/cut"
            ["_cp"]="/bin/cp"
            ["_find"]="/usr/bin/find"
            ["_grep"]="/bin/grep"
            ["_head"]="/usr/bin/head"
            ["_ls"]="/bin/ls"
            ["_mkdir"]="/bin/mkdir"
            ["_pwd"]="/bin/pwd"
            ["_rm"]="/bin/rm"
            ["_rmdir"]="/bin/rmdir"
            ["_sed"]="/bin/sed"
            ["_tmux"]="/usr/bin/tmux"
            ["_tr"]="/usr/bin/tr" )
danger_tools=( "_cp" "_cat" "_dd" "_mkdir" "_rm" "_rmdir" )

## functions ##

print_usage()
{
    echo "usage: $0 [options] action"
}

print_help()
{
    print_usage
    $_grep "^#\* " $0 | $_sed 's;^#\*;;'
}

print_version()
{
    $_grep "^#\*\* " $0 | $_sed 's;^#\*\*;;'
}

die()
{
    [ $verbose -eq 0 ] && echo "$@"
    exit 1
}

error()
{
    [ $verbose -eq 0 ] && print_usage
    [ $verbose -eq 0 ] && echo ""
    die "Error: $@"
}

list()
{
    declare -A sessions
    stored_sessions=( $($_find $confdir -type f -printf '%P\n') )
    for s in ${stored_sessions[@]} ; do
        ifs=$IFS
        IFS="/" 
        vs=( $s )
        IFS=$ifs
        has_session=""
        group="${vs[0]}"
        session="${vs[1]%.*}"
        client=$($_tmux list-clients | $_grep " $session " | $_cut -d":" -f1)
        store="$confdir/$s"
        if $_tmux has-session -t "$session" 2> /dev/null ; then
            has_session="y"
        fi
        sessions["$session"]="$has_session;$group;$client;$store"
    done

    active_sessions=( $($_tmux list-sessions -F '#{session_group};#S') )
    for s in ${active_sessions[@]} ; do
        ifs=$IFS
        IFS=";" 
        vs=( $s )
        IFS=$ifs
        group="${vs[0]}"
        [ -z "$group" ] && group=$nogroup
        session="${vs[1]}"
        client=$($_tmux list-clients | $_grep " $session " | $_cut -d":" -f1)
        store=$($_find $confdir/$group/ -type f -name "$session.new")
        [ -z "$store" ] &&
            store=$($_find $confdir/$group/ -type f -name "$session.copy")
        sessions[$session]="y;$group;$client;$store"
    done

    echo -e "[\e[1mgroup:session\e[0m] [\e[1mclient\e[0m] [\e[1mstorage file\e[0m]"
    for session in ${!sessions[@]} ; do
        ifs=$IFS
        IFS=";" 
        vs=( ${sessions[$session]} )
        IFS=$ifs
        has_session="${vs[0]}"
        group="${vs[1]}"
        client="${vs[2]}"
        store="${vs[3]}"
        if [ -z "$group" ] || [ "$group" == "$nogroup" ] ; then
            out="[\e[0;31m.\e[0;39m:"
        else
            out="[\e[0;32m$group\e[0;39m:"
        fi
        if [ -n "$client" ] ; then
            out="$out\e[1;32m$session\e[0;39m] "
        elif [ -n "$has_session" ] ; then
            out="$out\e[1;33m$session\e[0;39m] "
        else
            out="$out\e[1;31m$session\e[0;39m] "
        fi
        if [ -n "$client" ] ; then
            out="$out[\e[0;32m$client\e[0;39m] "
        else
            out="$out[\e[0;31m...\e[0;39m] "
        fi
        if [ -n "$store" ] ; then
            out="$out[\e[0;32m$store\e[0;39m]"
        else
            out="$out[\e[0;31m...\e[0;39m]"
        fi
        echo -e "$out"
    done
}

store()
{
    requested=" $@ "
    sessions=( $($_tmux list-sessions -F '#{session_group};#S') )

    for s in ${sessions[@]} ; do

        ifs=$IFS
        IFS=";"
        vs=( $s )
        IFS=$ifs
        group="${vs[0]}"
        session="${vs[1]}"

        if [ ${#@} -gt 0 ] ; then
            [ -n "${requested/*$session*/}" ] && continue
        fi

        [ $verbose -eq 0 ] && echo "processing: $group:$session"
        if [ -z "$group" ] ; then

            group="$nogroup"
        elif [ -d "$confdir/$group" ] ; then

            orig="$($_find $confdir/$group -type f -name "*.new" \
                                            -printf '%f\n' | $_head -1)"
            if [ -n "$orig" ] && [ "$session" != "${orig%.new}" ] ; then

                echo "$_tmux new-session -d -t ${orig%.new} -s $session"\
                                        > $confdir/$group/${session}.copy
                continue
            fi
        fi
        $_mkdir -p $confdir/$group

        workpaths=( $($_tmux list-panes -t $session -F '#{pane_current_path}') )
        echo "cd ${workpaths[0]}" > $confdir/$group/${session}.new

        windows=( $($_tmux list-windows -t $session -F '#W') )

        echo "$_tmux new -d -s $session -n ${windows[0]}" \
                                >> $confdir/$group/${session}.new
        for (( i=1; i<${#windows[@]}; i++ )) ; do
            echo "$_tmux new-window -t $session -n ${windows[i]}" \
                                 >> $confdir/$group/${session}.new
        done
    done
}

init()
{
    [ $verbose -eq 0 ] && echo "Creating config directory: $confdir"
    $_mkdir -p $confdir
}

attach()
{
    echo "please implement me first.."
    exit 0
}

cleanup()
{
    [ -d "$confdir" ] && $_rm $rm_options $confdir/*/*
}

restore()
{
    requested=" $@ "
    sessions=( $($_find $confdir -type f -name "*.new") \
                $($_find $confdir -type f -name "*.copy") )
    for f in ${sessions[@]} ; do
        s="${f##*/}"
        session="${s%.*}"

        if [ ${#@} -gt 0 ] ; then
            [ -n "${requested/*$session*/}" ] && continue
        fi

        if ! $_tmux has-session -t "$session" 2> /dev/null ; then
            . "$f"
            [ $verbose -eq 0 ] && echo "Session $session restored."
        fi
    done
}

## logic ##

## first set the system tools
for t in ${!sys_tools[@]} ; do
    if [ -x "${sys_tools[$t]%% *}" ] ; then
        export ${t}="${sys_tools[$t]}"
    else
        error "Missing system tool: ${sys_tools[$t]##* } must be installed."
    fi
done

[ -r "$conffile" ] && . $conffile

#*  options:
while true ; do
    case "$1" in
#*      -f |--force                         do not ask
        -f|--force)
            rm_interactive=1
        ;;
#*      -h |--help                          print this help
        -h|--help)
            print_help
            exit 0
        ;;
#*      -i |--interactive                   ask before removing
        -i|--interactive)
            rm_interactive=0
        ;;
#*      -q |--quiet                         be as silent as reasonable
        -q|--quiet)
            verbose=1
        ;;
#*      -v |--verbose                       give some feedback
        -v|--verbose)
            verbose=0
        ;;
#*      -V |--version                       print version info and exit
        -V|--version)
            print_version
            exit
        ;;
        --*|-*)
            error "option $1 not supported"
        ;;
        *)
            break
        ;;
    esac
    shift
done

rm_options=""
[ $verbose -eq 0 ] && rm_options="-v"
[ $rm_interactive -eq 0 ] && rm_options="$rm_options -i"

#*  actions:
case $1 in
##*      attach                              attach all deattached sessions
#    a*)
#        restore
#        attach
#    ;;
#*      store                               save the current sessions setup
    s*)
        shift
        init
        store $@
    ;;
#*      cleanup                             remove the stored session setup
    cle*)
        cleanup
    ;;
#*      restore                             create sessions from stored setup
    re*)
        shift
        restore $@
    ;;
#*      list                                list active and stored sessions
    l*)
        list
    ;;
    *)
        print_usage
    ;;
esac

#* TODO Bug: What if the same session group number exists already?
