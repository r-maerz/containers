#!/bin/bash
# Copyright Broadcom, Inc. All Rights Reserved.
# SPDX-License-Identifier: APACHE-2.0

# shellcheck disable=SC1091

set -o errexit
set -o nounset
set -o pipefail

# Load libraries
. /opt/openldap/scripts/libfs.sh
. /opt/openldap/scripts/liblog.sh
. /opt/openldap/scripts/libopenldap.sh

# Load LDAP environment variables
eval "$(ldap_env)"

# Ensure non-root user has write permissions on a set of directories and files
for dir in "$LDAP_SHARE_DIR" "$LDAP_DATA_DIR" "$LDAP_ONLINE_CONF_DIR" "${LDAP_VAR_DIR}" "${LDAP_RUN_DIR}" "/docker-entrypoint-initdb.d"; do
    ensure_dir_exists "$dir" "${LDAP_DAEMON_USER}"
    chmod -R g+rwX "$dir"
done

if [ -f "/etc/openldap/slapd.ldif" ]; then
  owned_by "/etc/openldap/slapd.ldif" "${LDAP_DAEMON_USER}"
fi

setcap CAP_NET_BIND_SERVICE=+eip /usr/sbin/slapd
