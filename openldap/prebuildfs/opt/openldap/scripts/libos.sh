#!/bin/bash
# Copyright Broadcom, Inc. All Rights Reserved.
# SPDX-License-Identifier: APACHE-2.0
#
# Library for operating system actions

# shellcheck disable=SC1091

# Load Generic Libraries
. /opt/openldap/scripts/liblog.sh
. /opt/openldap/scripts/libfs.sh
. /opt/openldap/scripts/libvalidations.sh

# Functions

########################
# Check if an user exists in the system
# Arguments:
#   $1 - user
# Returns:
#   Boolean
#########################
user_exists() {
    local user="${1:?user is missing}"
    id "$user" >/dev/null 2>&1
}

########################
# Check if a group exists in the system
# Arguments:
#   $1 - group
# Returns:
#   Boolean
#########################
group_exists() {
    local group="${1:?group is missing}"
    getent group "$group" >/dev/null 2>&1
}

########################
# Create a group in the system if it does not exist already
# Arguments:
#   $1 - group
# Flags:
#   -i|--gid - the ID for the new group
#   -s|--system - Whether to create new user as system user (uid <= 999)
# Returns:
#   None
#########################
ensure_group_exists() {
    local group="${1:?group is missing}"
    local gid=""
    local is_system_user=false

    # Validate arguments
    shift 1
    while [ "$#" -gt 0 ]; do
        case "$1" in
        -i | --gid)
            shift
            gid="${1:?missing gid}"
            ;;
        -s | --system)
            is_system_user=true
            ;;
        *)
            echo "Invalid command line flag $1" >&2
            return 1
            ;;
        esac
        shift
    done

    if ! group_exists "$group"; then
        local -a args=("$group")
        if [[ -n "$gid" ]]; then
            if group_exists "$gid"; then
                error "The GID $gid is already in use." >&2
                return 1
            fi
            args+=("--gid" "$gid")
        fi
        $is_system_user && args+=("--system")
        groupadd "${args[@]}" >/dev/null 2>&1
    fi
}

########################
# Create an user in the system if it does not exist already
# Arguments:
#   $1 - user
# Flags:
#   -i|--uid - the ID for the new user
#   -g|--group - the group the new user should belong to
#   -a|--append-groups - comma-separated list of supplemental groups to append to the new user
#   -h|--home - the home directory for the new user
#   -s|--system - whether to create new user as system user (uid <= 999)
# Returns:
#   None
#########################
ensure_user_exists() {
    local user="${1:?user is missing}"
    local uid=""
    local group=""
    local append_groups=""
    local home=""
    local is_system_user=false

    # Validate arguments
    shift 1
    while [ "$#" -gt 0 ]; do
        case "$1" in
        -i | --uid)
            shift
            uid="${1:?missing uid}"
            ;;
        -g | --group)
            shift
            group="${1:?missing group}"
            ;;
        -a | --append-groups)
            shift
            append_groups="${1:?missing append_groups}"
            ;;
        -h | --home)
            shift
            home="${1:?missing home directory}"
            ;;
        -s | --system)
            is_system_user=true
            ;;
        *)
            echo "Invalid command line flag $1" >&2
            return 1
            ;;
        esac
        shift
    done

    if ! user_exists "$user"; then
        local -a user_args=("-N" "$user")
        if [[ -n "$uid" ]]; then
            if user_exists "$uid"; then
                error "The UID $uid is already in use."
                return 1
            fi
            user_args+=("--uid" "$uid")
        else
            $is_system_user && user_args+=("--system")
        fi
        useradd "${user_args[@]}" >/dev/null 2>&1
    fi

    if [[ -n "$group" ]]; then
        local -a group_args=("$group")
        $is_system_user && group_args+=("--system")
        ensure_group_exists "${group_args[@]}"
        usermod -g "$group" "$user" >/dev/null 2>&1
    fi

    if [[ -n "$append_groups" ]]; then
        local -a groups
        read -ra groups <<<"$(tr ',;' ' ' <<<"$append_groups")"
        for group in "${groups[@]}"; do
            ensure_group_exists "$group"
            usermod -aG "$group" "$user" >/dev/null 2>&1
        done
    fi

    if [[ -n "$home" ]]; then
        mkdir -p "$home"
        usermod -d "$home" "$user" >/dev/null 2>&1
        configure_permissions_ownership "$home" -d "775" -f "664" -u "$user" -g "$group"
    fi
}

########################
# Check if the script is currently running as root
# Arguments:
#   $1 - user
#   $2 - group
# Returns:
#   Boolean
#########################
am_i_root() {
    if [[ "$(id -u)" = "0" ]]; then
        true
    else
        false
    fi
}

#########################
# Redirects output to /dev/null if debug mode is disabled
# Globals:
#   BITNAMI_DEBUG
# Arguments:
#   $@ - Command to execute
# Returns:
#   None
#########################
debug_execute() {
    if is_boolean_yes "${BITNAMI_DEBUG:-false}"; then
        "$@"
    else
        "$@" >/dev/null 2>&1
    fi
}

########################
# Retries a command a given number of times
# Arguments:
#   $1 - cmd (as a string)
#   $2 - max retries. Default: 12
#   $3 - sleep between retries (in seconds). Default: 5
# Returns:
#   Boolean
#########################
retry_while() {
    local cmd="${1:?cmd is missing}"
    local retries="${2:-12}"
    local sleep_time="${3:-5}"
    local return_value=1

    read -r -a command <<<"$cmd"
    for ((i = 1; i <= retries; i += 1)); do
        "${command[@]}" && return_value=0 && break
        sleep "$sleep_time"
    done
    return $return_value
}

########################
# Run command as a specific user and group (optional)
# Arguments:
#   $1 - USER(:GROUP) to switch to
#   $2..$n - command to execute
# Returns:
#   Exit code of the specified command
#########################
run_as_user() {
    run_chroot "$@"
}

########################
# Run a command using chroot
# Arguments:
#   $1 - USER(:GROUP) to switch to
#   $2..$n - command to execute
# Flags:
#   -r | --replace-process - Replace the current process image (optional)
# Returns:
#   Exit code of the specified command
#########################
run_chroot() {
    local userspec
    local user
    local homedir
    local replace=false
    local -r cwd="$(pwd)"

    # Parse and validate flags
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            -r | --replace-process)
                replace=true
                ;;
            --)
                shift
                break
                ;;
            -*)
                stderr_print "unrecognized flag $1"
                return 1
                ;;
            *)
                break
                ;;
        esac
        shift
    done

    # Parse and validate arguments
    if [[ "$#" -lt 2 ]]; then
        echo "expected at least 2 arguments"
        return 1
    else
        userspec=$1
        shift

        # userspec can optionally include the group, so we parse the user
        user=$(echo "$userspec" | cut -d':' -f1)
    fi

    if ! am_i_root; then
        error "Could not switch to '${userspec}': Operation not permitted"
        return 1
    fi

    # Get the HOME directory for the user to switch, as chroot does
    # not properly update this env and some scripts rely on it
    homedir=$(eval echo "~${user}")
    if [[ ! -d $homedir ]]; then
        homedir="${HOME:-/}"
    fi

    # Obtaining value for "$@" indirectly in order to properly support shell parameter expansion
    if [[ "$replace" = true ]]; then
        exec chroot --userspec="$userspec" / bash -c "cd ${cwd}; export HOME=${homedir}; exec \"\$@\"" -- "$@"
    else
        chroot --userspec="$userspec" / bash -c "cd ${cwd}; export HOME=${homedir}; exec \"\$@\"" -- "$@"
    fi
}
