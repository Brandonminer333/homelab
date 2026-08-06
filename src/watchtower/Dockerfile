FROM docker:27-cli

# yq (mikefarah): parse config/config.yml for desired stack state
RUN apk add --no-cache git bash curl \
  && (apk add --no-cache yq-go || apk add --no-cache yq)

COPY git-sync.sh /usr/local/bin/git-sync.sh
RUN chmod +x /usr/local/bin/git-sync.sh

ENTRYPOINT ["/usr/local/bin/git-sync.sh"]
