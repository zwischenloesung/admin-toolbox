#!/bin/bash -e
########################################################################
#** Version: 1.0
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
### local config, everything after the last slash will also be searched for
### in the current directory in order to support independent project dirs.
conffile=~/.conductor
### {{{

# for status mode concentrate on this ip protocol
ipprot="-4"

# whether to take action
dryrun=1
# whether we must run as root
needsroot=1

# rsync mode
rsync_options="-a -m --exclude=.keep"

merge_only_this_subdir=""
merge_mode="dir"

# here you can store short hands for your project specific configs
## the path to the core: the git repository storing the reclass-cmdb
inventorydir=""
## a collection of ansible plays to be used directly by this wrapper
playbookdir=""
## just a directory where output is stored temporarily and for external usage
workdir=""
## specify all local directories you intend to use in your reclass hosts in this
## associative array, now you can reference them by using their {{ key }}
localdirs=()

# this is the hosts link
ansible_connect=/usr/share/reclass/reclass-ansible

# options to pass to ansible (see also -A/--ansible-options)
ansibleoptions=""

### }}}

# Unsetting this helper variables (sane defaults)
_pre=""
classfilter=""
nodefilter=""
projectfilter=""

ansible_root=""
force=1
parser_dryrun=1
pass_ask_pass=""
ansible_verbose=""

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
            ["_ln"]="/bin/ln"
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
danger_tools=( "_cp" "_cat" "_dd" "_ln" "_mkdir"
               "_sed" "_rm" "_rmdir" "_rsync" )
# special case sudo (not mandatory)
_sudo="/usr/bin/sudo"

declare -A opt_sys_tools
opt_sys_tools=( ["_ansible"]="/usr/bin/ansible"
                ["_ansible_playbook"]="/usr/bin/ansible-playbook" )
opt_danger_tools=( "_ansible" "_ansible_playbook" )

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

[ -r "$conffile" ] && . "$conffile"
[ -r "${conffile##*/}" ] && . "${conffile##*/}"

#* options:
while true ; do
    case "$1" in
#*  -a |--ansible-extra-vars 'vars' variables to pass to ansible
        -a|--ansible-extra-vars)
            shift
            ansibleextravars="$1"
        ;;
#*  -A |--ansible-options 'options' options to pass to ansible or
#*                                  ansible_playbook resp.
        -A|--ansible-options)
            shift
            ansibleoptions="$1"
        ;;
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
#*  -k |--ask-pass                  prompt for the password (see ansible -k)
        -k|--ask-pass)
            pass_ask_pass="-k"
        ;;
#*  -m |--merge mode                specify how to merge, available modes:
#*                                    custom    based on "re-merge-custom"
#*                                    dir       nodename based dirs (default)
#*                                    in        nodename infixed files
#*                                    pre       nodename prefixed files
#*                                    post      nodename postfixed files
        -m|--merge)
            shift
            merge_mode=$1
        ;;
#*  -n |--dry-run                   do not change anything
        -n|--dry-run)
            dryrun=0
        ;;
#*  -H |--host host                 only process a certain host
        -H|--host|-N|--node)
            shift
            nodefilter="$1"
        ;;
#*  -p |--parser-test               only output what would be fed to script
        -p|--parser-test)
            parser_dryrun=0
        ;;
#*  -P |--project project           only process nodes from this project,
#*                                  which practically is the node namespace
#*                                  from reclass (directory hierarchy)
        -P|--project)
            shift
            projectfilter="$1"
            classfilter="project.$1"
        ;;
#*  -r |--rsync-dry-run
        -r|--rsync-dry-run)
            rsync_options="$rsync_options -n"
        ;;
#*  -R |--ansible-dry-run
        -R|--ansible-dry-run)
            ansibleoptions="$ansibleoptions -C"
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
#*  -v |--verbose
        -v|--verbose)
            ansible_verbose="-vvv"
            rsync_options="$rsync_options -v"
        ;;
#*  -V |--version
        -V|--version)
            print_version
            exit
        ;;
#*  -w |--workdir directory         Manually specify a temporary workdir
        -w|--workdir)
            shift
            workdir=$1
            $_mkdir -p $workdir
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

reclass_parser='BEGIN {
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
            !/^ *- / {
#print "we_are_here="metamode"-"mode
                tmp=$0
                # compare the number of leading spaces divided by 2 to
                # the number of colons in metamode to decide if we are
                # still in the same context
                sub("\\S.*", "", tmp)
                numspaces=length(tmp)
                tmp=metamode
                numcolons=gsub(":", "", tmp)
                doprint="f"
                if (( numcolons == 0 ) && ( numspaces == 2 )) {
                    doprint=""
                } else {
                    while ( numcolons >= numspaces/2 ) {
                        sub(":\\w*$", "", metamode)
                        numcolons--
                        doprint=""
                    }
                }
                if (( doprint == "" ) && ( mode != "none" ) && ( list != "" )) {
                    print mode"=( "list" )"
                    mode="none"
                    list=""
                    doprint="f"
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
            /^  os__distro:/ {
                if ( metamode == "parameters" ) {
                  mode="none"
                  print "os_distro="$2
                }
                next
            }
            /^  os__codename:/ {
                if ( metamode == "parameters" ) {
                  mode="none"
                  print "os_codename="$2
                }
                next
            }
            /^  os__release:/ {
                if ( metamode == "parameters" ) {
                  mode="none"
                  print "os_release="$2
                }
                next
            }
            /^  os__package-selections:/ {
                if ( metamode == "parameters" ) {
                  mode="none"
                  print "os_package_selections="$2
                }
                next
            }
            /^  host__infrastructure:/ {
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
            /^  host__type:/ {
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
            /^  debian-.*-packages:$/ {
                if ( metamode == "parameters" ) {
                  gsub("-", "_")
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
            /^  debops:$/ {
#print "debops_="metamode
                if ( metamode == "parameters" ) {
                    metamode=metamode":debops"
                    mode="debops"
                }
                next
            }
            /^  ansible:$/ {
                if ( metamode == "parameters" ) {
                    metamode=metamode":ansible"
                    mode="ansible"
                }
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
                    next
                }
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
            /^      .*$/ {
                if ( metamode == "parameters:debops" ) {
#print "debops___="metamode
                    gsub("'"'"'", "")
                    list=list "\n'"'"'" $0 "'"'"'"
                    next
                }
            }
            /^    .*$/ {
                if ( metamode == "parameters:debops" ) {
#print "debops__="metamode
                    next
                } else if ( metamode == "parameters:ansible" ) {
                    gsub("\"", "\x22")
                    gsub(":", "\x3A")
                    # pure trial and error as I just dont get it..
                    gsub("%", "%%")
                    a=$1
                    sub(":", "", a)
                    b=$0
                    sub(" *"$1" ", "", b)
                    print "ansible_meta[\""a"\"]='"'"'" b "'"'"'"
                    next
                }
            }
            /^ *- / {
                if (( mode != "none") && ( mode != "debops" )) {
                    gsub("'"'"'", "")
                    sub("- ", "")
                    list=list "\n'"'"'" $0 "'"'"'"
                }
                next
            }
            {
                mode="none"
            }
            END {
            }'

## define these in parse_node()
re_define_parsed_variables()
{
#*** Associative Array:     ansible_meta
    declare -g -A ansible_meta
    ansible_meta=()
#*** Array:                 applications
    applications=()
#*** Array:                 classes
    classes=()
#*** String:                environemnt
    environement=""
#*** Array:                 parameters.debops
    debops=()
#*** String:                parameters.host__infrastructure
    hostinfrastructure=""
#*** String:                parameters.host__locations
    hostlocation=""
#*** String:                parameters.host__type
    hosttype=""
#*** String:                parameters.os__codename
    os_codename=""
#*** String:                parameters.os__distro
    os_distro=""
#*** String:                parameters.os__name
    os_name=""
#*** String:                parameters.os__package-selections
    os_package_selections=""
#*** String:                parameters.os__release
    os_release=""
#*** String                 parameters.project
    project=""
#*** Array:                 parameters.storage-dirs
    storagedirs=()
#*** Array:                 parameters.re-merge.direct
    remergedirect=()
#*** Associative array:     parameters.re-merge.custom.src
    declare -g -A remergecustomsrc
    remergecustomsrc=()
#*** Associative array:     parameters.re-merge.custom.dest
    declare -g -A remergecustomdest
    remergecustomdest=()
}
re_define_parsed_variables

parse_node()
{
    # make sure they are empty
    re_define_parsed_variables

    awk_var_p_keys=";"
    awk_var_p_vals=";"
    for k in ${!localdirs[@]} ; do
        awk_var_p_keys="$k;$awk_var_p_keys"
        awk_var_p_vals="${localdirs[$k]};$awk_var_p_vals"
    done
    if [ $parser_dryrun -eq 0 ] ; then
        $_reclass -b $inventorydir -n $1 |\
            $_awk -v p_len=${#localdirs[@]} -v p_keys=$awk_var_p_keys \
                  -v p_vals=$awk_var_p_vals "$reclass_parser"
    else
        eval $(\
            $_reclass -b $inventorydir -n $1 |\
            $_awk -v p_len=${#localdirs[@]} -v p_keys=$awk_var_p_keys \
                  -v p_vals=$awk_var_p_vals "$reclass_parser"
        )
    fi
}

clone_config()
{
    [ -f "$1/${conffile##*/}" ] || $_cp "$conffile" "$1"
    $_sed -i "$1/${conffile##*/}" -e 's;inventorydir=.*;inventorydir="'$1'";'
}

clone_init()
{
    cdir="$1"
    f="$2"
    [ -f "$cdir/hosts" ] && error "a file '$cdir/hosts' already exists, please remove manually first.."
    [ -f "$cdir/reclass-config.yml" ] && error "a file '$cdir/reclass-config.yml' already exists, please remove manually first.."
    [ -d "$cdir/reclass-env" ] && error "a directory '$cdir/reclass-env' already exists, please remove manually first.."
    $_ln -s $ansible_connect "$cdir/hosts"
    if [ -z "$_pre" ] ; then
        $_cat > "$cdir/reclass-config.yml" << EOF
storage_type: yaml_fs
inventory_base_uri: $cdir/reclass-env
EOF
    else
        echo "write config file $cdir/reclass-config.yml"
        echo "  storage_type: yaml_fs"
        echo "  inventory_base_uri: $cdir/reclass-env"
    fi
    $_mkdir -p "$cdir/reclass-env/nodes" "$cdir/reclass-env/classes"
    if [ -z "$f" ] ; then
        l="$_ln -s"
    else
        l="$_cp -r"
    fi
    $l $inventorydir/classes/* "$cdir/reclass-env/classes/"
    if [ -z "$projectfilter" ] ; then
        $l $inventorydir/nodes/* "$cdir/reclass-env/nodes/"
    else
        $l $inventorydir/nodes/$projectfilter "$cdir/reclass-env/nodes/"
    fi
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

connect_well_known()
{
    echo "Please note that for the moment we do not have real means for"
    echo "automatically doing this step for you, instead we just list some"
    echo "options here:"
    echo " - ansible:    you need to set the 'hostfile' variable in the"
    echo "               (e.g. local) ansible.cfg to point to the newly"
    echo "               created environement, i.e. to point to the file"
    echo "               'hosts', this links to reclass-ansible and reads"
    echo "               the 'reclass-config.yml' configuration in order to"
    echo "               be able to find 'reclass-env'."
    echo " - debops:     for now, the 'inventory' is hard coded in debops"
    echo "               so the 'hostsfile' variable in ansible.cfg will"
    echo "               always be overwritten by debops. I do not know"
    echo "               any way to work around that problem yet. You can"
    echo "               only use the --inventory option at the moment."
}

noop()
{
    echo -n ""
}

ansible_connection_test()
{
    if [ "${ansible_meta['prompt_password']}" == "true" ] ; then
        printf "\e[1;33mWarning: "
        printf "\e[1;39m$n\e[0m has ansible:prompt_password set to 'true'.\n"
        printf "         You probably want to use the '-k' flag.\n"
    fi
    if [ -n "${ansible_meta['ssh_common_args']}" ] ; then
        printf "\e[1;33mWarning: "
        printf "\e[1;39m$n\e[0m has ansible:ssh_common_args set to '${ansible_meta['ssh_common_args']}'.\n"
        printf "         Please check your ssh configs for that host if you encounter problems.\n"
    fi
    for l in connect_timeout use_scp ; do
        if [ -n "${ansible_meta[$l]}" ] ; then
            printf "\e[1;33mWarning: "
            printf "\e[1;39m$n\e[0m has ansible:$l set to '${ansible_meta[$l]}'.\n"
            printf "         Please control your (.)ansible.cfg if you encounter problems.\n"
        fi
    done
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

list_debops()
{
    list_node $n
    for (( i=0 ; i < ${#debops[@]} ; i++ )) ; do
        echo "${debops[i]}"
    done
}

list_distro_packages()
{
    list_node $n
    ps=()
    psi=0
    l=$(eval 'echo ${#'${os_distro}'__packages[@]}')
    for (( i=0 ; i<l ; i++ )) ; do
        ps[$psi]=$(eval 'echo ${'${os_distro}'__packages['$i']}')
        let ++psi
    done
    l=$(eval 'echo ${'${os_distro}'_'${os_codename}'_packages[@]}')
    for (( i=0 ; i<l ; i++ )) ; do
        ps[$psi]=$(eval 'echo ${'${os_distro}'_'${os_codename}'_packages['$i']}')
        let ++psi
    done

    OLDIFS=$IFS
    IFS="
"
    ps=( $(
        for (( i=0 ; i<${#ps[@]} ; i++ )); do
            echo "${ps[$i]}"
        done | $_sort -u
    ) )
    IFS=$OLDIFS

    for (( i=0 ; i<${#ps[@]} ; i++ )); do
        printf "\e[0;33m - ${ps[$i]}\n"
    done
}

list_applications()
{
    list_node $n
    for a in ${applications[@]} ; do
        printf "\e[0;36m - $a\n"
    done
    printf "\e[0;39m"
}

list_classes()
{
    list_node $n
    for c in ${classes[@]} ; do
        printf "\e[0;35m - $c\n"
    done
    printf "\e[0;39m"
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
    printf "\e[0;39m"
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
        $_mv $f $workdir/$targetpath/${prefix}.${n}$suffix
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
        $_mv $f $workdir/$targetpath/${n}.${basename}
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
        $_mv $f $workdir/$targetpath/${basename}.${in}
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
    if [ ! -d "$workdir" ] ; then
        die "Target directory '$workdir' does not exist!"
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
                do_sync "$d/$src/" "$workdir/$n/$trgt/"
            done
        ;;&
        dir)
        ;;
        in|post|pre)
            t="$workdir/$n/"
            for d in $($_find $t -type d) ; do
                $_mkdir -p $workdir/${d/$t/}
            done
            re_merge_exceptions_first $n $workdir
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
            re_merge_custom $workdir/$n/
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
            $_tr -d ":" | $_sort -r ) )

#* actions:
case $1 in
    ansible-fetch*|ansible-put*|ansible-play*|play|put|fetch)
        [ -n "$_ansible" ] || error "Missing system tool: ansible."
        [ -n "$_ansible_playbook" ] ||
                        error "Missing system tool: ansible-playbook."

        # check for some connection settings in config or for -k option
        process_nodes ansible_connection_test ${nodes[@]}
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
#*  ansible-fetch src dest [flat]   ansible oversimplified fetch module
#*                                  wrapper (prefer ansible-play instead)
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

        echo "wrapping $_ansible $hostpattern $ansible_root ${ansibleextravars:+-e '$ansibleextravars'} $ansibleoptions -m fetch -a 'src=$src dest=$dest $flat'"
        if [ 0 -ne "$force" ] ; then
            echo "Press <Enter> to continue <Ctrl-C> to quit"
            read
        fi
        $_ansible $hostpattern $ansible_root ${ansibleextravars:+-e "$ansibleextravars"} $ansibleoptions -m fetch -a "src=$src dest=$dest $flat"
    ;;
#*  ansible-plays-list (apls)       list all available plays (see 'playbookdir'
#*                                  in your config.
    ansible-plays-list|apls|pls)
    foundplays=( $($_find $playbookdir -maxdepth 1 -name "*.yml" | $_sort -u) )
    for p in ${foundplays[@]} ; do
        o=${p%.yml}
        printf "\e[1;39m - ${o##*/}: \e[0;32m $p\e[0;35m\n"
        $_grep "^#\* " $p | $_sed 's;^#\*;  ;'
        printf "\e[0;39m"
    done
    ;;
#*  ansible-play (play) play        wrapper to ansible which also includes
#*                                  custom plays stored in the config
#*                                  file as '$playbookdir'.
#*                                  'play' name of the play
    ansible-play*|play)
        p="$($_find $playbookdir -maxdepth 1 -name ${2}.yml)"
        [ -n "$p" ] ||
            error "There is no play called ${2}.yml in $playbookdir"
        echo "wrapping $_ansible_playbook ${ansible_verbose} -l $hostpattern $pass_ask_pass ${ansible_root:+-b -K} -e 'workdir="$workdir" $ansibleextravars' $ansibleoptions $p"
        if [ 0 -ne "$force" ] ; then
            echo "Press <Enter> to continue <Ctrl-C> to quit"
            read
        fi
        $_ansible_playbook ${ansible_verbose} -l $hostpattern $pass_ask_pass ${ansible_root:+-b -K} -e "workdir='$workdir' $ansibleextravars" $ansibleoptions $p
    ;;
#*  ansible-put src dest            ansible oversimplified copy module wrapper
#*                                  (prefer ansible-play instead)
#*                                  'src' is /path/file on local host
#*                                  'dest' is /path/.. on remote host
    ansible-put|put)

        src=$2
        dest=$3

        owner="" ; [ -z "$4" ] || owner="owner=$4"
        mode="" ; [ -z "$5" ] || mode="mode=$5"

        echo "wrapping $_ansible $hostpattern $ansible_root ${ansibleextravars:+-e '$ansibleextravars'} $ansibleoptions -m copy -a 'src=$src dest=$dest' $owner $mode"
        if [ 0 -ne "$force" ] ; then
            echo "Press <Enter> to continue <Ctrl-C> to quit"
            read
        fi
        $_ansible $hostpattern $ansible_root ${ansibleextravars:+-e "$ansibleextravars"} $ansibleoptions -m copy -a "src=$src dest=$dest" $owner $mode
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
        for a in $( echo ${!applications_dict[@]} | $_tr " " "\n" | $_sort ) ; do
            printf "\e[1;34m[$a]\n"
            for h in $(echo -e ${applications_dict[$a]//:/ \\n} | $_sort -u); do
                printf "\e[0;32m$h\n"
            done
        done
        printf "\e[0;39m"
    ;;
#*  classes-list (cls)              list hosts sorted by class
    cls|class*)
        process_nodes process_classes ${nodes[@]}
        for a in $( echo ${!classes_dict[@]} | $_tr " " "\n" | $_sort ) ; do
            printf "\e[1;35m[$a]\n"
            for h in $( echo -e ${classes_dict[$a]//:/ \\n} | $_sort -u ) ; do
                printf "\e[0;32m$h\n"
            done
        done
        printf "\e[0;39m"
    ;;
#*  clone [directory]               clone your current knowledge base into a new
#*                                  path. (almost identical to 'init-clone';
#*                                  see also 'clone-link').
    clone)
        shift
        if [ -n "$1" ] ; then
            if [ -d "$1" ] ; then
                cdir="$1"
            else
                error "Could not find directory: $1"
            fi
        else
            cdir="$($_pwd)"
        fi
        clone_config $cdir
        clone_init $cdir force
    ;;
#*  clone-link [directory]          link your current knowledge base into a new
#*                                  path. (this is almost identical to 'init';
#*                                  see also 'clone').
    clone-link)
        shift
        if [ -n "$1" ] ; then
            if [ -d "$1" ] ; then
                cdir="$1"
            else
                error "Could not find directory: $1"
            fi
        else
            cdir="$($_pwd)"
        fi
        clone_config $cdir
        clone_init $cdir
    ;;
#*  help                            print this help
    help)
        print_help
    ;;
#*  init [directory]                connect a (ansible-/debops-/..) directory
#*                                  to your knowledge base (this is almost
#*                                  identical to 'clone-link' but does not
#*                                  produce a local config file).
    init)
        shift
        if [ -n "$1" ] ; then
            if [ -d "$1" ] ; then
                cdir="$1"
            else
                error "Could not find directory: $1"
            fi
        else
            cdir="$($_pwd)"
        fi
        clone_init $cdir
        connect_well_known
    ;;
#*  init-clone [directory]          clone the knowledge base to this
#*                                  project directory and connect the
#*                                  (ansible-/debops-/..) project
#*                                  (this is actually almost identical to
#*                                  'clone'; see also 'init').
    init-clone)
        shift
        if [ -n "$1" ] ; then
            if [ -d "$1" ] ; then
                cdir="$1"
            else
                error "Could not find directory: $1"
            fi
        else
            cdir="$($_pwd)"
        fi
        clone_config $cdir
        clone_init $cdir force
        connect_well_known
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
#*  list-debops-inventory           list the ansible inventory of debops hosts
    lsd|list-debops-inventory)
        process_nodes list_debops ${nodes[@]}
    ;;
#*  list-distro-packages            list app package names for the hosts distro
    lsp|list-distro-packages)
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
#*                                  to $workdir
    merge|merge-a*|mg)
        process_nodes merge_all ${nodes[@]}
    ;;
#*  merge-custom (mc)               merge after custom rules defined in reclass
#*                                  in $workdir, then move to the destination
#*                                  as specified
    merge-cu*|mc)
        merge_mode="custom"
        process_nodes merge_all ${nodes[@]}
    ;;
#*  merge-pre (mpr)                 merge storage dirs and prefix with hostname
#*                                  to $workdir
    merge-pr*|mpr)
        merge_mode="pre"
        process_nodes merge_all ${nodes[@]}
    ;;
#*  merge-in (mi)                   merge storage dirs and infix with hostname
#*                                  to $workdir
    merge-i*|mi)
        merge_mode="in"
        process_nodes merge_all ${nodes[@]}
    ;;
#*  merge-post (mpo)                merge storage dirs and postfix with hostname
#*                                  to $workdir
    merge-po*|mpo)
        merge_mode="post"
        process_nodes merge_all ${nodes[@]}
    ;;
##*  re-merge                        remerge as specified in '--merge mode'
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
        if [ -n "$projectfilter" ] ; then
            nodes_uri="$inventorydir/nodes/$projectfilter"
            if [ ! -d "$nodes_uri" ] ; then
                error "No such project dir: $nodes_uri"
            fi
        elif [ -n "$classfilter" ] ; then
            error "Classes are not supported here, use project filter instead."
        fi
        if [ -z "$nodes_uri" ] ; then
            $_reclass -b $inventorydir $nodes_uri $reclassmode
        else
            $_reclass -b $inventorydir -u $nodes_uri $reclassmode
        fi
    ;;
#*  show-reclass-summary            show variables used in reclass that are
#*                                  interpreted here
    show-rec*)
        printf "The following variables can be used in reclass and will\n"
        printf "be interpreted (and potentially used) by this script.\n"
        printf "\n"
        printf "\e[1mNote:\e[0m Of course you can use other variables as well,\n"
        printf "this is just a list of what $0\n"
        printf "is directly aware of.\n"
        printf "\n"
        printf " \e[1mType                   Variable\e[0m\n"
        $_grep "^#\*\*\* " $0 | $_sed_forced 's;^#\*\*\*;;'
        printf "\n"
        printf "Furthermore these variables are needed in $conffile\n"
        printf " Where to search for reclass:         inventorydir\n"
        printf " Where to put (temp.) results:        workdir\n"
        printf " Local directories to replace:        localdirs\n"
        printf " Ansible playbooks:                   playbookdir\n"
        printf "\n"
        printf "Currently these contain the following values:\n"
        printf " 'inventorydir':    $inventorydir\n"
        printf " 'workdir':         $workdir\n"
        printf " 'playbookdir':       $playbookdir\n"
        printf "\n"
        printf " The above 'localdirs' can be used in reclass like any other\n"
        printf " external variable, i.e. '{{ name }}'. Currently these names\n"
        printf " are used in your config:\n"
        for d in ${!localdirs[@]} ; do
            printf "  $d: ${localdirs[$d]}\n"
        done
    ;;
#*  search variable                 show in which file a variable is configured
    search)
        shift
        printf "\e[1;33mSearch string is found in nodes:\e[0m\n"
        $_grep --color -Hn -R -e "^$1:" -e "\s$1:" -e "\${$1}" -e "{{ *$1 *}}" $inventorydir/nodes || true
        printf "\e[1;33mSearch string is found in classes:\e[0m\n"
        $_grep --color -Hn -R -e "^$1:" -e "\s$1:" -e "\${$1}" -e "{{ *$1 *}}" $inventorydir/classes || true
    ;;
#*  search-all                      show what variables are used
    search-all)
        printf "\e[1;33mSearch string is found in nodes:\e[0m\n"
        $_grep --color -Hn -R -e "^.*:" -e "\s.*:" -e "\${.*}" -e "{{ *.* *}}" $inventorydir/nodes || true
        printf "\e[1;33mSearch string is found in classes:\e[0m\n"
        $_grep --color -Hn -R -e "^.*:" -e "\s.*:" -e "\${.*}" -e "{{ *.* *}}" $inventorydir/classes || true
    ;;
#*  search-class class              show which class or node refers to a given
#*                                  class
    search-class)
        shift
        printf "\e[1;33mSearch string is found in nodes:\e[0m\n"
        $_grep --color -Hn -R -e "^  - $1$" $inventorydir/nodes || true
        printf "\e[1;33mSearch string is found in classes:\e[0m\n"
        $_grep --color -Hn -R -e "^  - $1$" $inventorydir/classes || true
    ;;
#*  search-in-playbooks variable    search the common-playbooks for a certain
#*                                  parameter as they overlap
    search-in-playbooks)
        shift
        printf "\e[1;33mSearch string is found in plays:\e[0m\n"
        $_grep --color -Hn -R -e "{{[a-zA-Z0-9_+ ]*${1}[a-zA-Z0-9_+ ]*}}" $playbookdir || true
    ;;
#*  search-external variable        show in which file an external
#*                                  {{ variable }} is configured
    search-external)
        shift
        printf "\e[1;33mSearch string is found in nodes:\e[0m\n"
        $_grep --color -Hn -R -e "{{ *$1 *}}" $inventorydir/nodes || true
        printf "\e[1;33mSearch string is found in classes:\e[0m\n"
        $_grep --color -Hn -R -e "{{ *$1 *}}" $inventorydir/classes || true
    ;;
#*  search-external-all             show what external {{ variables }} are used
    search-external-all)
        printf "\e[1;33mSearch string is found in nodes:\e[0m\n"
        $_grep --color -Hn -R -e "{{ *.* *}}" $inventorydir/nodes || true
        printf "\e[1;33mSearch string is found in classes:\e[0m\n"
        $_grep --color -Hn -R -e "{{ *.* *}}" $inventorydir/classes || true
    ;;
#*  search-reclass variable         show in which file a ${variable} is
#*                                  configured
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

