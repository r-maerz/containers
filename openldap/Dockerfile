# Copyright Broadcom, Inc. All Rights Reserved.
# SPDX-License-Identifier: APACHE-2.0

FROM alpine:3.22

LABEL Maintainer="Robert Maerz <171489683+r-maerz@users.noreply.github.com>" \
      Description="OpenLDAP on Alpine Linux with Bitnami scripts."

ADD https://r-maerz.github.io/alpine-packages/r-maerz.rsa.pub /etc/apk/keys/r-maerz.rsa.pub
RUN apk update && apk upgrade && apk add --no-cache bash

RUN addgroup -S -g 102 ldap 2>/dev/null && \
    adduser -S -D -H -h /usr/lib/openldap -s /sbin/nologin -G ldap -g "OpenLdap User" -u 101 ldap 2>/dev/null

COPY prebuildfs /
SHELL ["/bin/bash", "-o", "errexit", "-o", "nounset", "-o", "pipefail", "-c"]
RUN install_packages shadow libcap-setcap ca-certificates
RUN install_packages openldap libldap openldap-backend-all openldap-overlay-all openldap-clients openldap-dev openldap-passwd-argon2 openldap-passwd-pbkdf2 openldap-passwd-sha2 openldap-slapi ca-certificates --repository=https://r-maerz.github.io/alpine-packages/main
RUN rm -rf /var/cache/apk/*
RUN chmod g+rwX /opt/openldap
RUN find / -perm /6000 -type f -exec chmod a-s {} \; || true

COPY rootfs /
RUN /opt/openldap/scripts/openldap/postunpack.sh

EXPOSE 1389 1636

USER ldap
ENTRYPOINT [ "/opt/openldap/scripts/openldap/entrypoint.sh" ]
CMD [ "/opt/openldap/scripts/openldap/run.sh" ]
