#!/bin/bash -e
########################################################################
#* This script helps you to stay informed while working - at least
#* if your swiss and used to a certain level of noice while working...
#* Basically it is a wrapper to watch SF DRS 10vor10 and Rundschau
#* Podcasts from the command line with the help of mplayer.
#
########################################################################
# author/copyright: <michael.lustenberger@inofix.ch>
# license: gladly sharing with the universe and any lifeform,
#          be it naturally born or constructed, alien or kin..
########################################################################
[ "$1" == "debug" ] && shift && set -x

## variables ##

### you may copy the following variables into this file for having your own
### local config ...
#conffile=~/.rundschau.sh

### {{{

rundschau_url="http://www.srf.ch/feed/podcast/hd/49863a84-1ab7-4abb-8e69-d8e8bda6c989.xml"
zvz_url="https://www.srf.ch/feed/podcast/hd/c38cc259-b5cd-4ac1-b901-e3fddd901a3d.xml"


### }}}

# The system tools we gladly use. Thank you!
declare -A sys_tools
sys_tools=( ["_awk"]="/usr/bin/awk"
            ["_cat"]="/bin/cat"
            ["_cp"]="/bin/cp"
            ["_grep"]="/bin/grep"
            ["_mkdir"]="/bin/mkdir"
            ["_mplayer"]="/usr/bin/mplayer"
            ["_pwd"]="/bin/pwd"
            ["_rm"]="/bin/rm"
            ["_rmdir"]="/bin/rmdir"
            ["_sed"]="/bin/sed"
            ["_tr"]="/usr/bin/tr"
            ["_wget"]="/usr/bin/wget"
            ["_xml2"]="/usr/bin/xml2" )
danger_tools=( "_cp" "_cat" "_dd" "_mkdir" "_rm" "_rmdir" )

## functions ##

print_usage()
{
    echo "usage: $0"
}

print_help()
{
    print_usage
    $_grep "^#\* " $0 | $_sed 's;^#\*;;'
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

playlatest=1
#*  options:
while true ; do
    case "$1" in
#*      -h |--help                          print this help
        -h|--help)
            print_help
            exit 0
        ;;
#*      -l |--latest                        show the latest right away
        -l|--latest)
            playlatest=0
        ;;
        -*|--*)
            error "option $1 not supported"
        ;;
#*      10vor10                             consider 10vor10
        10*)
            url=${zvz_url}
        ;;
#*      rundschau                           consider rundschau
        r*)
            url=$rundschau_url
        ;;
        *)
            break
        ;;
    esac
    shift
done

if [ -z "$url" ] ; then
    echo "Wa wetsch luege? 10vor10 oder rondschau?"
    read answer
    if [ "$answer" == "10vor10" ] ; then
        url=${zvz_url}
    elif [ "$answer" == "rondschau" ] ; then
        url=$rundschau_url
    else
        echo "Hani ned verstande, sorry..."
        exit 1
    fi
fi

channels=( $($_wget -O - "$url" | $_xml2 | $_grep "/rss/channel/item/enclosure/@url" | $_awk 'BEGIN{FS="="}{print $2}') )

if [ $playlatest -eq 0 ] ; then

    $_mplayer ${channels[0]}

else

    echo "Die channels hani gfonde.."
    i=0
    for c in ${channels[@]} ; do
        echo "$i) $c"
        let ++i
    done
    echo "wele wotsch? oder eifach nuet"
    read answer
    if [ -n "$answer" ] ; then
        $_mplayer --zoom --framedrop ${channels[answer]}
    fi
fi

exit 0

