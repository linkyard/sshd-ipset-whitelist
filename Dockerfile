FROM alpine:latest as downloader

COPY pgp.asc /tmp/pgp.asc
RUN set -x \
  && apk add --no-cache curl gnupg \
  && cat /tmp/pgp.asc | gpg --batch --import \
  && export TINI_VERSION=v0.18.0 \
  && curl -L https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini -o /tini \
  && curl -L https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini.asc -o /tini.asc \
  && gpg --batch --verify /tini.asc /tini

# https://github.com/kubernetes/kubernetes/tree/master/build/debian-iptables
# https://console.cloud.google.com/gcr/images/google-containers/GLOBAL/debian-iptables-amd64
FROM gcr.io/google-containers/debian-iptables-amd64:v11.0.2

COPY --from=downloader /tini /usr/bin/tini

RUN set -x \
  && clean-install \
      curl \
      bash \
  && chmod +x /usr/bin/tini

COPY apply-ipset-whitelist.sh /apply-ipset-whitelist.sh
COPY entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/usr/bin/tini","-g","--","/entrypoint.sh"]
CMD ["apply-ipset-whitelist.sh"]
