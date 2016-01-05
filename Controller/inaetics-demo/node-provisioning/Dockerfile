# Dockerfile for inaetics/node-provisioning-service
FROM slintes/jre8:java8-8u51

MAINTAINER Marc Sluiter <marc.sluiter@luminis.eu>

# Install etcdctl
RUN cd /tmp \
  && export ETCDVERSION=v2.0.13 \
  && curl -k -L https://github.com/coreos/etcd/releases/download/$ETCDVERSION/etcd-$ETCDVERSION-linux-amd64.tar.gz | gunzip | tar xf - \
  && cp etcd-$ETCDVERSION-linux-amd64/etcdctl /bin/

# Add resources
ADD resources /tmp

# Either uncomment this line, or map the bundles folder as a docker volume to /bundles when starting the container!
#ADD bundles /bundles
