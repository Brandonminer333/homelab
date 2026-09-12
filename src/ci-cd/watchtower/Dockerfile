FROM docker:27-cli

# Pin mikefarah/yq (go) so boolean filters like `.run == true` are reliable.
ARG YQ_VERSION=v4.44.3
RUN apk add --no-cache git bash curl ca-certificates \
  && arch="$(uname -m)" \
  && case "$arch" in \
       x86_64) yq_arch=amd64 ;; \
       aarch64) yq_arch=arm64 ;; \
       armv7l) yq_arch=arm ;; \
       *) echo "unsupported arch: $arch" >&2; exit 1 ;; \
     esac \
  && curl -fsSL -o /usr/local/bin/yq \
       "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${yq_arch}" \
  && chmod +x /usr/local/bin/yq \
  && yq --version

# Prefer the bind-mounted script so git pulls update sync logic without rebuild.
# Fallback copy exists for first boot / missing mount.
COPY git-sync.sh /usr/local/bin/git-sync.sh
RUN chmod +x /usr/local/bin/git-sync.sh

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
