FROM docker:27-cli

RUN apk add --no-cache git bash curl

COPY git-sync.sh /usr/local/bin/git-sync.sh
RUN chmod +x /usr/local/bin/git-sync.sh

ENTRYPOINT ["/usr/local/bin/git-sync.sh"]
