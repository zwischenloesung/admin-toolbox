#!/bin/bash -e
########################################################################
#** Version: 0.1
#* This script checks a mirror for files and checksums..
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
#conffile=.debian-installer-checksums.sh

### {{{

dryrun=1
needsroot=1

debian_mirror="http://ftp.uni-stuttgart.de/debian/dists/"
debian_version="stable"
debian_arch="amd64"

### }}}

# Unsetting this helper variable
_pre=""

# The system tools we gladly use. Thank you!
declare -A sys_tools
sys_tools=( ["_awk"]="/usr/bin/awk"
            ["_cat"]="/bin/cat"
            ["_cp"]="/bin/cp"
            ["_gpg"]="/usr/bin/gpg"
            ["_grep"]="/bin/grep"
            ["_id"]="/usr/bin/id"
            ["_mkdir"]="/bin/mkdir"
            ["_mktemp"]="/bin/mktemp"
            ["_mv"]="/bin/mv"
            ["_pwd"]="/bin/pwd"
            ["_rm"]="/bin/rm"
            ["_rmdir"]="/bin/rmdir"
            ["_sed"]="/bin/sed"
            ["_sed_forced"]="/bin/sed"
            ["_sha256sum"]="/usr/bin/sha256sum"
            ["_tr"]="/usr/bin/tr"
            ["_wget"]="/usr/bin/wget" )
# this tools get disabled in dry-run and sudo-ed for needsroot
danger_tools=( "_cp" "_cat" "_dd" "_mkdir" "_sed" "_rm" "_rmdir" )
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
#*      -a |--arch architecture             provide the target arch (default: 'amd64')
        -a|--arch)
            shift
            debian_arch=$1
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
#*      -V |--debian-version version        version to search for (default: 'stable')
        -V|--debian-version)
            shift
            debian_version=$1
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

#*  actions:
action=$1

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

get_checksums() {

    [ -z "$debian_version" ] && error "There was no Debian version provided. See action: 'versions'"
    echo "Trying to get the checksums for $debian_version/$debian_arch from $debian_mirror"

    tempdir=$($_mktemp -d)
    cd $tempdir
    $_wget "$debian_mirror/$debian_version/Release.gpg"
    $_wget "$debian_mirror/$debian_version/Release"
    $_mv Release.gpg Release.sig
    $_gpg -v Release.sig ; retval=$?
    if [ $retval -ne 0 ] ; then
        die "The Release file could not be verified with Release.gpg!"
    fi

    $_awk 'BEGIN{
                mode="false"
            }
            /^SHA256:/{
                mode="true"
            }
            /main\/installer-'${debian_arch}'\/current\/images\/SHA256SUMS/{
                if (mode == "true"){
                    print $1" SHA256SUMS"
            }}' Release > Release.sha256sums

    $_wget "$debian_mirror/$debian_version/main/installer-${debian_arch}/current/images/SHA256SUMS"
    $_sha256sum -c Release.sha256sums

    if [ "$1" == "persist" ] ; then

        $_grep "./netboot/debian-installer/${debian_arch}/initrd.gz$" SHA256SUMS | $_sed 's;  .*/\(initrd.gz\).*;  ./\1;' > $cwd/SHA256SUMS
        $_grep "./netboot/debian-installer/${debian_arch}/linux$" SHA256SUMS | $_sed 's;  .*/\(linux\).*;  ./\1;' >> $cwd/SHA256SUMS
    else

        $_grep "./MANIFEST$" SHA256SUMS
        $_grep "./MANIFEST.udebs$" SHA256SUMS
        $_grep "./netboot/debian-installer/${debian_arch}/initrd.gz$" SHA256SUMS
        $_grep "./netboot/debian-installer/${debian_arch}/linux$" SHA256SUMS
    fi

    $_rm $tempdir/*
    $_rmdir $tempdir
}

get_files() {

    [ -z "$debian_version" ] && error "There was no Debian version provided. See action: 'versions'"
    echo "Trying to get the kernel and the initrd for $debian_version/$debian_arch from $debian_mirror installing it here $cwd"

    get_checksums persist
    cd $cwd

    $_wget "$debian_mirror/$debian_version/main/installer-${debian_arch}/current/images/netboot/debian-installer/${debian_arch}/initrd.gz"
    $_wget "$debian_mirror/$debian_version/main/installer-${debian_arch}/current/images/netboot/debian-installer/${debian_arch}/linux"

    $_sha256sum -c SHA256SUMS
}

get_versions() {
    $_wget -O - http://ftp.uni-stuttgart.de/debian/dists// 2>/dev/null | $_grep "Debian[0-9]\+\.[0-9]\+" | $_sed 's;.*\(Debian[0-9]\+\.[0-9]\+\).*;\1;' | $_sed 's;/;;'
}

cwd=$($_pwd)

case $action in
#*      checksums       Verify the signature and print the checksum for central files.
    checksums|sum)
        get_checksums
    ;;
#*      files           Get the files needed for a minimal installation.
    files)
        get_files
    ;;
#*      versions        Show what versions are available on the mirror.
    versions)
        get_versions
    ;;
    *)
        echo "action not supported."
        print_help
    ;;
esac

