#!/bin/bash -e
########################################################################
#** Version: 1.0
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
# not used yet: favorite_term="/usr/bin/urxvt -fn 6x13 +sb -tr -bg black -fg white -sh 60 -sl 10000"

### }}}

# The system tools we gladly use. Thank you!
declare -A sys_tools
sys_tools=(
            ["_cut"]="/usr/bin/cut"
            ["_find"]="/usr/bin/find"
            ["_grep"]="/bin/grep"
            ["_head"]="/usr/bin/head"
            ["_mkdir"]="/bin/mkdir"
            ["_rm"]="/bin/rm"
            ["_rmdir"]="/bin/rmdir"
            ["_sed"]="/bin/sed"
            ["_tmux"]="/usr/bin/tmux"
)
danger_tools=( "_mkdir" "_rm" "_rmdir" )

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
        sgroup="${vs[0]}"
        session="${vs[1]%.*}"
        client=$($_tmux list-clients 2> /dev/null | \
                             $_grep " $session " | $_cut -d":" -f1)
        store="$s"
        if ! $_tmux has-session -t "$session" 2> /dev/null ; then
            sessions["$session"]="$has_session;;$sgroup;$client;$store"
        fi
    done

    active_sessions=( $($_tmux list-sessions -F '#{session_group};#S') ) || true
    for s in ${active_sessions[@]} ; do
        ifs=$IFS
        IFS=";" 
        vs=( $s )
        IFS=$ifs
        group="${vs[0]}"
        [ -z "$group" ] && group=$nogroup
        session="${vs[1]}"
        client=$($_tmux list-clients | $_grep " $session " | $_cut -d":" -f1)
        store=$($_find $confdir -type f -name "$session.new")
        [ -z "$store" ] &&
            store=$($_find $confdir -type f -name "$session.copy")
        store=${store##$confdir}
        sgroup=${store%/*}
        sessions["$session"]="y;$group;$sgroup;$client;$store"
    done

    printf "[\e[1mgroup#:name]%6s[session\e[0m]%10s[\e[1mclient\e[0m]%6s[\e[1mstorage file\e[0m]\n"
    for session in ${!sessions[@]} ; do
        ifs=$IFS
        IFS=";" 
        vs=( ${sessions[$session]} )
        IFS=$ifs
        has_session="${vs[0]}"
        group="${vs[1]}"
        sgroup="${vs[2]}"
        client="${vs[3]}"
        store="${vs[4]}"
        out="["
        s=1
        if [ -z "$group" ] || [ "$group" == "$nogroup" ] ; then
            out="$out\e[0;31m.\e[0;39m:"
            (( s++ ))
        else
            out="$out\e[0;32m$group\e[0;39m:"
            (( s += ${#group} ))
        fi
        if [ -z "$sgroup" ] ; then
            out="$out\e[0;31m.\e[0;39m]"
            (( s++ ))
        elif [ "$sgroup" == "$nogroup" ] ; then
            out="$out\e[0;33m$sgroup\e[0;39m]"
            (( s += ${#sgroup} ))
        else
            out="$out\e[0;32m$sgroup\e[0;39m]"
            (( s += ${#sgroup} ))
        fi
        (( s = 17 - s ))
        out="$out%${s}s"
        if [ -n "$client" ] ; then
            out="$out[\e[1;32m$session\e[0;39m]"
        elif [ -n "$has_session" ] ; then
            out="$out[\e[1;33m$session\e[0;39m]"
        else
            out="$out[\e[1;31m$session\e[0;39m]"
        fi
        (( s = 17 - ${#session} ))
        out="$out%${s}s"
        if [ -n "$client" ] ; then
            out="$out[\e[0;32m$client\e[0;39m]"
            (( s = 12 - ${#client} ))
        else
            out="$out[\e[0;31m...\e[0;39m]"
            s=9
        fi
        out="$out%${s}s"
        if [ -n "$store" ] ; then
            out="$out[\e[0;32m$store\e[0;39m]"
        else
            out="$out[\e[0;31m...\e[0;39m]"
        fi
        printf "$out\n"
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
        stored=$($_find $confdir -type f -name "${session}.*" -printf '%P\n')
        if [ -n "$stored" ] ; then
            group=${stored%/*}
        fi
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

#* TODO:
#*  Missing Features:
#*   * Implement the attach action
#*  Known Bugs:
