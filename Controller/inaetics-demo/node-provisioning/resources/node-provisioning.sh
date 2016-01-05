#!/bin/bash

cd $(dirname $0)

#
# Config
#
GOSH_NONINTERACTIVE=true
DEBUG_LOG=true

#
# Libs
#
source etcdctl.sh

MAX_PROVISIONING_RESTART=10
MAX_RETRY_ETCD_REPO=10
RETRY_ETCD_REPO_INTERVAL=5
ETCD_TTL_INTERVALL=60
ETCD_REWRITE_INTERVALL=45

#
# Functions
#

# Wraps a function call to redirect or filter stdout/stderr
# depending on the debug setting
#   args: $@ - the wrapped call
#   return: the wrapped call's return
_call () {
  if [ "$DEBUG_LOG" != "true"  ]; then
    $@ &> /dev/null
    return $?
  else
    $@ 2>&1 | awk '{print "[DEBUG] "$0}' >&2
    return ${PIPESTATUS[0]}
  fi
}

# Echo a debug message to stderr, perpending each line
# with a debug prefix.
#   args: $@ - the echo args
_dbg() {
  if [ "$DEBUG_LOG" == "true" ]; then
    echo $@ | awk '{print "[DEBUG] "$0}' >&2
  fi
}

# Echo a log message to stderr, perpending each line
# with a info prefix.
#   args: $@ - the echo args
_log() {
  echo $@ | awk '{print "[INFO] "$0}' >&2
}

function store_etcd_data(){

  # check if provisioning is running
  if [ "$provisioning_id" == "" ]; then
  	_log "service not running, skipping store_etcd_data"
    return
  fi

  PROVISIONING_ETCD_PATH_FOUND=0
  RETRY=1
  while [ $RETRY -le $MAX_RETRY_ETCD_REPO ] && [ $PROVISIONING_ETCD_PATH_FOUND -eq 0 ]
  do
    etcd/putTtl "/inaetics/node-provisioning-service/$provisioning_id" "$provisioning_ipv4:$provisioning_port" "$ETCD_TTL_INTERVALL"

    if [ $? -ne 0 ]; then
        _log "Tentative $RETRY of storing Provisioning Server to etcd failed. Retrying..."
        ((RETRY+=1))
        sleep $RETRY_ETCD_REPO_INTERVAL
    else
        _log "Pair </inaetics/node-provisioning-service/$provisioning_id,$provisioning_ipv4:$provisioning_port> stored in etcd"
        PROVISIONING_ETCD_PATH_FOUND=1
    fi
  done

  if [ $PROVISIONING_ETCD_PATH_FOUND -eq 0 ]; then
    _log "Cannot store pair </inaetics/node-provisioning-service/$provisioning_id,$provisioning_ipv4:$provisioning_port> in etcd"
  fi

}

start_provisioning () {
  java $JAVA_PROPS -jar server-allinone.jar &
  provisioning_pid=$!
}

stop_provisioning () {
  etcd/rm "/inaetics/node-provisioning-service/$provisioning_id"
  if [ "$provisioning_pid" != "" ]; then
    kill -SIGTERM $provisioning_pid
    provisioning_pid=""
  fi
}

clean_up () {
  stop_provisioning
  rm /tmp/health
  exit
}

#
# Main
#
trap clean_up SIGHUP SIGINT SIGTERM

provisioning_id=$1
if [ "$provisioning_id" == "" ]; then
  # get docker id
  provisioning_id=`cat /proc/self/cgroup | grep -o  -e "docker-.*.scope" | head -n 1 | sed "s/docker-\(.*\).scope/\\1/"`
fi
if [ "$provisioning_id" == "" ]; then
  _log "provisioning_id param required!"
  exit 1
fi

provisioning_ipv4=$2
if [ "$provisioning_ipv4" == "" ]; then
  # get IP
  provisioning_ipv4=`hostname -i`
fi
if [ "$provisioning_ipv4" == "" ]; then
  _log "provisioning_ipv4 param required!"
  exit 1
fi

# get port from env variable set by kubernetes pod config
provisioning_port=$HOSTPORT
if [ "$provisioning_port" == "" ]; then
  provisioning_port=8080
fi

JAVA_PROPS="-Dace.gogo.script=/bundles/default-mapping.gosh"
if [ $GOSH_NONINTERACTIVE ]; then
  JAVA_PROPS="$JAVA_PROPS -Dgosh.args=--nointeractive"
fi

# we are healthy, used by kubernetes
echo ok > /tmp/health

PROVISIONING_RESTART=0

while [ $PROVISIONING_RESTART -le $MAX_PROVISIONING_RESTART ]; do

  if [ "$provisioning_pid" == "" ]; then
    _log "Starting Provisioning."
    ((PROVISIONING_RESTART+=1))
    start_provisioning
  elif [ ! -d "/proc/$provisioning_pid" ]; then
    # clean up and exit loop
    echo "provisioning process not running anymore, cleaning up..."
    clean_up
    break
  else
    _log "store to etcd and wait..."
    store_etcd_data
    sleep $ETCD_REWRITE_INTERVALL &
    wait $!
  fi
done
