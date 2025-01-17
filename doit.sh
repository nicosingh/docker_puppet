#!/bin/bash

source .env


usage() {
    cat <<ENDHERE

Usage: $0 [options] action

Options:
    -h   Print this help

Action:
    One of "setup", "start", "stop", "reset"

ENDHERE
}


err() {
    echo "$*" 1>&2
}


ask_yes_no() {
    local rv=1
    local msg="Is this ok?"
    [[ -n "$1" ]] && msg="$1"
    echo "$msg"
    select yn in "Yes" "No"; do
        case $yn in
            Yes) rv=0;;
            No ) rv=1;;
        esac
        break
    done
    return $rv
}


do_setup() {
    mkdir -p "${CUSTOM_ROOT}"/custom/r10k/logs
    mkdir -p "${CUSTOM_ROOT}"/custom/enc
    touch "${CUSTOM_ROOT}"/custom/enc/tables.yaml
    touch "${CUSTOM_ROOT}"/custom/enc/pup_enc.db
}


do_start() {
    do_setup
    docker-compose up -d "$@"
}


do_stop() {
    docker-compose stop "$@"
}


do_cleanup() {
    # remove containers
    docker ps -a --format "{{.ID}} {{.Names}}" \
    | awk '/dockerpup/{print $1}' \
    | xargs -r docker rm -f

    # Remove puppetservice images
    docker images --format "{{.ID}} {{.Repository}}" \
    | awk '/dockerpup/ {print $1}' \
    | xargs -r docker rmi

    # remove extraneous networks
    docker network prune --force
}


do_hard_cleanup() {
    rm_dirs=()
    vol_dir=$(readlink -e "${VOLUME_ROOT}"/volumes)
    if [[ -d "$vol_dir"/code ]] ; then
        rm_dirs+=( "$vol_dir" )
    fi
    r10k_dir=$(readlink -e "${CUSTOM_ROOT}"/custom/r10k)
    cache_dir="${r10k_dir}"/cache
    if [[ -d "$cache_dir" ]] ; then
        rm_dirs+=( "$cache_dir" )
    fi
    log_dir="${r10k_dir}"/logs
    if [[ -d "$log_dir" ]] ; then
        rm_dirs+=( "$log_dir" )
    fi
    if [[ ${#rm_dirs[@]} -gt 0 ]] ; then
        echo
        echo "* * * WARNING * * *"
        echo "About to recursively delete directories:"
        for d in "${rm_dirs[@]}"; do
            echo "  $d"
        done
        echo
        ask_yes_no \
        && sudo -- rm -rf "${rm_dirs[@]}"
    fi
    for fn in "${CUSTOM_ROOT}"/custom/enc/pup_enc.db ; do
        [[ -f "$fn" ]] \
        && rm "$fn"
    done
}


ENDWHILE=0
while [[ $# -gt 0 ]] && [[ $ENDWHILE -eq 0 ]] ; do
  case $1 in
    -h) usage;;
    --) ENDWHILE=1;;
    -*) echo "Invalid option '$1'"; exit 1;;
     *) ENDWHILE=1; break;;
  esac
  shift
done

[[ $# -lt 1 ]] && {
	usage
	exit
}
action="$1"
shift

case $action in
    setup)
        do_setup
        ;;
    start)
        do_start "$@"
        ;;
    stop)
        do_stop "$@"
        ;;
    clean)
        do_stop
        do_cleanup
        ;;
    reset)
        do_stop
        do_cleanup
        do_hard_cleanup
        ;;
    *)
        err "Unknown action: '$action'"
        usage
        ;;
esac
