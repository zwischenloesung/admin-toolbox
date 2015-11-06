#!/bin/bash -e
########################################################################
#** Version: 0.5
#* This script per default unifies whitespace in files by changeing tabs
#* to spaces and eliminating trailing spaces. It can also be used to
#* replace (sed) other things.
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
conffile=~/.remtab.sh

declare -A sed_custom_expressions
### {{{

dryrun=1
needsroot=1
verbose=1
recursion_depth=1

sed_custom_expressions=(
    ["umlauts"]='s#Ã¤#ä#g;s#Ã¼#ü#g;s#Ã¶#ö#g;s#Ã<9c>#Ü#g;s#Ã<84>#Ä#g;s#Ã<96>#Ö#g'
    ["tab1s"]='s#\t# #g;s#[ \t]*$##'
    ["tab2s"]='s#\t#  #g;s#[ \t]*$##'
    ["tab4s"]='s#\t#    #g;s#[ \t]*$##'
    ["tab8s"]='s#\t#        #g;s#[ \t]*$##'
)
sed_expression=${sed_custom_expressions["tab4s"]}

# linus was right..
exclude_files=( ".svn" )
include_files=( )

### }}}

# Unsetting this helper variable
_pre=""

# The system tools we gladly use. Thank you!
declare -A sys_tools
sys_tools=( ["_awk"]="/usr/bin/awk"
            ["_cat"]="/bin/cat"
            ["_cp"]="/bin/cp"
            ["_find"]="/usr/bin/find"
            ["_grep"]="/bin/grep"
            ["_id"]="/usr/bin/id"
            ["_ls"]="/bin/ls"
            ["_mkdir"]="/bin/mkdir"
            ["_pwd"]="/bin/pwd"
            ["_rm"]="/bin/rm"
            ["_rmdir"]="/bin/rmdir"
            ["_sed"]="/bin/sed"
            ["_sed_forced"]="/bin/sed"
            ["_tr"]="/usr/bin/tr" )
# this tools get disabled in dry-run and sudo-ed for needsroot
danger_tools=( "_cp" "_cat" "_dd" "_mkdir" "_sed" "_rm" "_rmdir" )
# special case sudo (not mandatory)
_sudo="/usr/bin/sudo"

## functions ##

print_usage()
{
    echo "usage: $0 [-options] file.."
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

cleanthefile()
{
    [ $verbose -eq 0 ] && echo -e "\e[0;33mprocessing file: \e[0;39m$1"
    $_sed -e "$sed_expression" -i "$1"
}

cleanit()
{
    if [ -f "$1" ] ; then

        cleanthefile "$1"

    elif [ -d "$1" ] ; then

        if [ -z "$find_args" ] ; then
            [ $recursion_depth -gt 0 ] && find_args="-maxdepth $recursion_depth"

            find_args="$find_args -type f"

            include=""
            for p in ${include_files[@]} ; do
                [ -n "$include" ] && include="${include}-o "
                include="$include-name $p "
            done

            exclude=""
            for p in ${exclude_files[@]} ; do
                [ -n "$exclude" ] && exclude="${exclude}-o "
                exclude="$exclude-name $p -prune "
            done

            find_args="${find_args} ${exclude}-o ${include}-print" 
        fi

        OLDIFS=$IFS
        IFS=$( echo -ne "\n\b" )
        all_files=( $( IFS=$OLDIFS; $_find "$1" $find_args ) )
        IFS=$OLDIFS
        if [ $verbose -eq 0 ] ; then
            echo -e "\e[1;32mSearch: \e[0;39m"$1" $find_args"
            echo -e "\e[1;32mFound: \e[0;39m${all_files[@]}"
            echo -e "\e[1;32mApply: \e[0;39m'$sed_expression'"
        fi
        for (( i=0; i < ${#all_files[@]}; i++ )) ; do
            cleanthefile "${all_files[$i]}"
        done
    fi
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
#*      -c |--config conffile               alternative config file
        -c|--config)
            shift
            if [ -r "$1" ] ; then
                . $1
            else
                die " config file $1 does not exist."
            fi
        ;;
#*      -e |--exclude pattern               do not process these files
        -e|--exclude)
            shift
            exclude_files=( $1 ${exclude_files[@]} )
        ;;
#*      -f |--find-custom args              search this instead
        -f|--find-custom)
            shift
            find_args=$1
        ;;
#*      -h |--help                          print this help
        -h|--help)
            print_help
            exit 0
        ;;
#*      -i |--include pattern               apply to files matching
        -i|--include)
            shift
            include_files=( $1 ${include_files[@]} )
        ;;
#*      -l |--limit level                   limit recursion level depth
        -l|--limit)
            shift
            recursion_depth=$1
        ;;
#*      -n |--dry-run                       do not change anything
        -n|--dry-run)
            dryrun=0
        ;;
#*      -r |--recursive
        -r|--recursive)
            recursion_depth=0
        ;;
#*      -s |--sed expression                use custom expression for sed
#*                                          overwrites '--tab spaces'
        -s|--sed)
            shift
            sed_expression="$1"
        ;;
#*      -S |--sed-configured expr-name      preconfigured custom expression
#*                                          overwrites '--tab spaces'
        -S|--sed-configured)
            shift
            sed_expression="${sed_custom_expressions["$1"]}"
        ;;
#*      -t |--tab spaces                    replace tabs with 1, 2, 4, or 8
#*                                          spaces and remove trailing spaces
#*                                          (default 4; overwrites '--sed exp')
        -t|--tab)
            shift
            case $1 in
                1)
                    sed_expression="$sed_tab1s"
                ;;
                2)
                    sed_expression="$sed_tab2s"
                ;;
                4)
                    sed_expression="$sed_tab4s"
                ;;
                8)
                    sed_expression="$sed_tab8s"
                ;;
                *)
                    error "not supported"
                ;;
            esac
        ;;
#*      -v |--verbose)
        -v|-verbose)
            verbose=0
        ;;
#*      -V |--version
        -V|--version)
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

while [ -n "$1" ] ; do
    # action
    cleanit "$1"
    shift
done

