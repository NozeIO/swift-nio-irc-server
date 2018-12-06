# Dockerfile
#
#   docker run --rm -d --name miniircd helje5/nio-miniircd:latest
#   docker run --rm -d -p 127.0.0.1:1337:80 \
#                      -p 127.0.0.1:6667:6667 \
#                      --name miniircd helje5/nio-miniircd:latest
#
# Attach w/ new shell
#
#   docker exec -it miniircd bash
#
# To build:
#
#   docker build -t helje5/nio-miniircd:latest .
#   docker push helje5/nio-miniircd:latest
#
# Rebuild:
#
#   docker build --no-cache -t helje5/nio-miniircd:latest .
#

# Build Image
# - this just builds miniircd and its depdencies
# - we also grab the necessary Swift runtime libs from this

FROM swift:4.2.1 AS builder

LABEL maintainer "Helge Heß <me@helgehess.eu>"

ENV DEBIAN_FRONTEND noninteractive
ENV CONFIGURATION   release
ENV NIO_DAEMON_INSTALL_DIR /opt/miniircd/bin

WORKDIR /src/
COPY Sources        Sources
COPY Package.swift  .

RUN mkdir -p ${NIO_DAEMON_INSTALL_DIR}
RUN swift build -c ${CONFIGURATION}

RUN cp Package.resolved ${NIO_DAEMON_INSTALL_DIR}/miniircd-Package.resolved
RUN cp $(swift build -c ${CONFIGURATION} --show-bin-path)/miniircd \
    ${NIO_DAEMON_INSTALL_DIR}/


# Deployment Image
# - we copy in the shared libs from the builder image /usr/lib/swift/linux/
# - we copy in /opt/miniircd/bin from the builder image
# - we generate a supervise run script

FROM ubuntu:16.04

LABEL maintainer  "Helge Heß <me@helgehess.eu>"
LABEL description "A MiniIRCd deployment container"

RUN apt-get -q update && apt-get -q -y install \
    libatomic1 libbsd0 libcurl3 libicu55 libxml2 \
    daemontools \
    && rm -r /var/lib/apt/lists/*

WORKDIR /

COPY --from=builder /usr/lib/swift/linux/*.so /usr/lib/swift/linux/
COPY --from=builder /opt/miniircd/bin         /opt/miniircd/bin

EXPOSE 1337
EXPOSE 6667
EXPOSE 80

WORKDIR /opt/miniircd

RUN mkdir -p /opt/miniircd/logs

RUN bash -c "echo '#!/bin/bash'                                        > run; \
             echo ''                                                  >> run; \
             echo echo RUN Started  \$\(date\) \>\>logs/run.log       >> run; \
             echo ''                                                  >> run; \
             echo stdbuf -oL -eL ./bin/miniircd --web http://0.0.0.0:80/websocket --extweb wss://irc.noze.io:443/websocket \>\>logs/run.log 2\>\>logs/error.log >> run; \
             echo ''                                                  >> run; \
             echo echo RUN Finished \$\(date\) \>\>logs/run.log       >> run; \
             echo echo RUN ------------------- \>\>logs/run.log       >> run; \
             chmod +x run"

CMD ["supervise", "/opt/miniircd"]
