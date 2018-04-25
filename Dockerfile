# Dockerfile
#
#   docker run --rm -d --name miniircd helje5/nio-miniircd:latest
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

# Build Image

FROM swift:4.1 AS builder

LABEL maintainer "Helge Heß <me@helgehess.eu>"

ENV DEBIAN_FRONTEND noninteractive
ENV CONFIGURATION   release

WORKDIR /src/
COPY Sources        Sources
COPY Package.swift  .

RUN mkdir -p /opt/miniircd/bin
RUN swift build -c ${CONFIGURATION}
RUN cp $(swift build -c ${CONFIGURATION} --show-bin-path)/miniircd \
    /opt/miniircd/bin/


# Deployment Image

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

WORKDIR /opt/miniircd

RUN mkdir -p /opt/miniircd/logs

RUN bash -c "echo '#!/bin/bash'                                        > run; \
             echo ''                                                  >> run; \
             echo echo RUN Started  \$\(date\) \>\>logs/run.log       >> run; \
             echo ''                                                  >> run; \
             echo ./bin/miniircd \>\>logs/run.log 2\>\>logs/error.log >> run; \
             echo ''                                                  >> run; \
             echo echo RUN Finished \$\(date\) \>\>logs/run.log       >> run; \
             echo echo RUN ------------------- \>\>logs/run.log       >> run; \
             chmod +x run"

CMD ["supervise", "/opt/miniircd"]
