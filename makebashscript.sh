#!/bin/bash -e
#################################################################
#** Version 1.0
#* This script helps creating bash scripts nicely and uniformly
#* while saving time..
#################################################################
# author/copyright: michael.lustenberger at inofix.ch
# license: gladly sharing with the universe and any lifeform,
#          be it naturally born or constructed, alien or kin..
#          USE AT YOUR OWN RISK.
#################################################################
[ "$1" == "debug" ] && shift && set -x
## variables ##

### you may copy the following variables into this file for having your own
### local config ...
conffile=~/.makebashscript

### {{{
author_name=""
author_email=""
### }}}
### ... now, leave alone from here on.

scriptname="$1"
license="$2"

## functions ##

print_usage()
{
    echo "usage: $0 scriptname [ license ]"
}

die()
{
    echo "$1"
    exit 1
}

error()
{
    print_usage
    echo ""
    die "Error: $@"
}

ask_to_write_config()
{
    echo -n "Do you want to permanently store this in $conffile? [N|y] "
    read answer
    case "$answer" in
        Y*|y*)
             echo "author_name='$author_name'" > $conffile
             echo "author_email='$author_email'" >> $conffile
        ;;
    esac
}

ask_author()
{
    echo "Please provide some author information for your script:"
    echo -n "Your name: "
    read author_name
    echo -n "Your email: "
    read author_email
    ask_to_write_config
}

## logic ##
case $scriptname in
    -*)
        print_usage
        /usr/bin/head $0 | /bin/grep "#\*"
        exit 0
    ;;
    "")
        error "Please provide a name for your script."
    ;;
esac

[ -r "$conffile" ] && . $conffile
gitconf=~/.gitconfig
if [ -r "$gitconf" ] ; then
    git_name=$(grep "name = " $gitconf | awk '{print $3" "$4}')
    git_email=$(grep "email = " $gitconf | awk '{print $3}')
    # if both differ, it is probably badly configured..
    if [ -n "$git_name" ] && [ "$git_name" != "$author_name" ] &&
            [ -n "$git_email" ] && [ "$git_name" != "$author_name" ] ; then
        echo "Do you want to use the git data for your personal info?"
        echo "Your name: $git_name"
        echo "Your email: <$git_email>"
        echo -n "Change? [N|y] "
        read answer
        case "$answer" in
            Y*|y*)
                author_name="$git_name"
                author_email="<$git_email>"
                ask_to_write_config
            ;;
            *)
                ask_author
            ;;
        esac
    fi
elif  [ -z "$author_name" ] ; then
    ask_author
fi

case "$license" in
    gpl*)
        license=\
"########################################################################
#
#  This is Free Software; feel free to redistribute and/or modify it
#  under the terms of the GNU General Public License as published by
#  the Free Software Foundation; version 3 of the License.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  Copyright $(/bin/date '+%Y'), $author_name $author_email
#
########################################################################"
    ;;
    *) license=\
"########################################################################
# author/copyright: $author_email
# license: gladly sharing with the universe and any lifeform,
#          be it naturally born or constructed, alien or kin..
#          USE AT YOUR OWN RISK.
########################################################################"
    ;;
esac

if [ -e "$scriptname" ] ; then
    error "A script with this name does already exist! NOT overwriteing.."
fi

/bin/cat > $scriptname << EOF
#!/bin/bash -e
########################################################################
#** Version:
#* This script helps ..?
#
# note: the frame for this script was auto-created with
# *https://github.com/inofix/admin-toolbox/blob/master/makebashscript.sh*
$license
[ "\$1" == "debug" ] && shift && set -x

## variables ##

### you may copy the following variables into this file for having your own
### local config ...
#conffile=.$scriptname

### {{{

dryrun=1
needsroot=1

### }}}

# Unsetting this helper variable
_pre=""

# The system tools we gladly use. Thank you!
declare -A sys_tools
sys_tools=( ["_awk"]="/usr/bin/awk"
            ["_cat"]="/bin/cat"
            ["_cp"]="/bin/cp"
            ["_grep"]="/bin/grep"
            ["_id"]="/usr/bin/id"
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
    echo "usage: \$0"
}

print_help()
{
    print_usage
    \$_grep "^#\* " \$0 | \$_sed_forced 's;^#\*;;'
}

print_version()
{
    \$_grep "^#\*\* " \$0 | \$_sed 's;^#\*\*;;'
}

die()
{
    echo "\$@"
    exit 1
}

error()
{
    print_usage
    echo ""
    die "Error: \$@"
}

## logic ##

## first set the system tools
for t in \${!sys_tools[@]} ; do
    if [ -x "\${sys_tools[\$t]##* }" ] ; then
        export \${t}="\${sys_tools[\$t]}"
    else
        error "Missing system tool: \${sys_tools[\$t]##* } must be installed."
    fi
done

[ ! -f "/etc/\$conffile" ] || . "/etc/\$conffile"
[ ! -f "/usr/etc/\$conffile" ] || . "/usr/etc/\$conffile"
[ ! -f "/usr/local/etc/\$conffile" ] || . "/usr/local/etc/\$conffile"
[ ! -f ~/"\$conffile" ] || . ~/"\$conffile"
[ ! -f "\$conffile" ] || . "\$conffile"

#*  options:
while true ; do
    case "\$1" in
#*      -c |--config conffile               alternative config file
        -c|--config)
            shift
            if [ -r "\$1" ] ; then
                . \$1
            else
                die " config file \$1 does not exist."
            fi
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
        -*|--*)
            error "option \$1 not supported"
        ;;
        *)
            break
        ;;
    esac
    shift
done

if [ \$dryrun -eq 0 ] ; then
    _pre="echo "
fi

if [ \$needsroot -eq 0 ] ; then

    iam=\$(\$_id -u)
    if [ \$iam -ne 0 ] ; then
        if [ -x "\$_sudo" ] ; then

            _pre="\$_pre \$_sudo"
        else
            error "Priviledges missing: use \${_sudo}."
        fi
    fi
fi

for t in \${danger_tools[@]} ; do
    export \${t}="\$_pre \${sys_tools[\$t]}"
done

exit 0

EOF

chmod 755 $scriptname

vi $scriptname

