#!/bin/bash -e
########################################################################
#** Version:
#* This script helps in translating one fingerprint format into another
#* for quick access during new host setups.
#
# TODO try to fix all translations (sha includes the method in the string)
## in python it works as expected...
#import hashlib
#import base64
#b64pubkey = 'AAAA...'
#sha256 = hashlib.sha256()
#sha256.update(base64.b64decode(b64pubkey))
#b64fingerprint = base64.b64encode(sha256.digest())
#print(b64fingerprint)
#
# note: the frame for this script was auto-created with
# *https://github.com/inofix/admin-toolbox/blob/master/makebashscript.sh*
########################################################################
# author/copyright: mic@inofix.ch
# license: gladly sharing with the universe and any lifeform,
#          be it naturally born or constructed, alien or kin..
#          USE AT YOUR OWN RISK.
########################################################################
[ "$1" == "debug" ] && shift && set -x

## variables ##

### you may copy the following variables into this file for having your own
### local config ...
#conffile=.ssh-fingerprints.sh

### {{{

# supported: anyone supported by openssh
default_algorithm="ed25519"

# supported: md5, sha1, sha256, sha512
default_hash="sha256"

default_host="localhost"
default_port="22"

### }}}

algorithm="$default_algorithm"
hashfunction="$default_hash"
rehash=1
hostname="$default_host"
portnumber="$default_port"
separated=1
remote=0
dropbear=1

# The system tools we gladly use. Thank you!
declare -A sys_tools
sys_tools=( ["_awk"]="awk"
            ["_base64"]="base64"
            ["_grep"]="grep"
            ["_md5sum"]="md5sum"
            ["_sed"]="sed"
            ["_sha1sum"]="sha1sum"
            ["_sha256sum"]="sha256sum"
            ["_sha512sum"]="sha512sum"
            ["_ssh"]="ssh"
            ["_ssh_keygen"]="ssh-keygen"
            ["_ssh_keyscan"]="ssh-keyscan" )

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
    retval=0
    tool=$(which ${sys_tools[$t]}) || retval=$?
    if [ $retval -eq 0 ] ; then
        export ${t}="$tool"
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
#*      -a |--algorithm algorithm           which host-key file to read
        -a|--algorithm)
            shift
            if [ -z "$1" ] ; then
                die " please provide an algorithm with this option"
            fi
            algorithm="$1"
        ;;
#*      -A |--hash-algorithm hash          which hash function to use for the
#*                                         fingerprint
        -A|--hash-algorithm)
            shift
            if [ -z "$1" ] ; then
                die " please provide a hash function with this option"
            fi
            hashfunction="$1"
            rehash=0
        ;;
#*      -c |--config conffile               alternative config file
        -c|--config)
            shift
            if [ -r "$1" ] ; then
                . $1
            else
                die " config file $1 does not exist."
            fi
        ;;
#*      -d |--direct                        per default we ssh to the host and
#*                                          collect the key there as ssh-scankey
#*                                          does not know all the ssh tricks.
#*                                          However sometimes it's handy to use
#*                                          ssh-scankey directly.
        -d|--direct)
            remote=1
        ;;
#*      -D |--dropbear                      connect to the host using dropbear
#*                                          to get the pub key and calculate
#*                                          the hash
        -D|--dropbear)
            dropbear=0
        ;;
#*      -h |--help                          print this help
        -h|--help)
            print_help "no"
            exit 0
        ;;
#*      -H |--host                          which host to connect to
        -H|--host)
            shift
            if [ -z "$1" ] ; then
                die " please provide a host with this option"
            fi
            hostname="$1"
        ;;
#*      -P |--port                          which port to connect to
        -P|--port)
            shift
            if [ -z "$1" ] ; then
                die " please provide a port with this option"
            fi
            portnumber="$1"
        ;;
#*      -s |--separated                     print output as separated ascii
#*                                          values for comparison (with e.g.
#*                                          old dropbear)
        -s|--separated)
            rehash=0
            separated=0
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

fingerprint=""
if [ "$portnumber" != "22" ] ; then
    ssh_port="-p $portnumber"
fi

if [ $dropbear -eq 1 ] ; then
    if [ $remote -eq 0 ] ; then
        fingerprint=$($_ssh $ssh_port $hostname $_ssh_keyscan -t $algorithm localhost 2>/dev/null | \
            $_awk '{print $3}')
    else
        fingerprint=$($_ssh_keyscan -t $algorithm $ssh_port $hostname 2>/dev/null | \
            $_awk '{print $3}')
    fi
else
    tmp_file=$(mktemp)
    $_ssh $ssh_port $hostname "dropbearkey -y -f /etc/dropbear/dropbear_${algorithm}_host_key" | head -2 | tail -1 > $tmp_file
    fingerprint=$($_ssh_keygen -l -f $tmp_file)
    rm $tmp_file
fi

if [ -z "$fingerprint" ] ; then
    die "unable to get the fingerprint from $hostname"
fi

if [ $rehash -eq 0 ] ; then
    hashtool="_${hashfunction}sum"
    _hash="${!hashtool}"

    if [ -x "$_hash" ] ; then
        export _hash="$_hash"
    fi
    fingerprint=$(echo "$fingerprint" | $_base64 -d | $_hash -b | $_awk '{print $1}')
fi

if [ $separated -eq 0 ] ; then
        fingerprint=$(echo "$fingerprint" | $_sed -e 's;\(..\);\1:;g' -e 's;:$;\n;')
fi

echo $fingerprint


