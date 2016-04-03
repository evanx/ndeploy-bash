#!/bin/bash

set -u -e

# env context

ns=${ns:=demo\:ndeploy}
rediscli=${rediscli:=redis-cli -n 13}


# logging

debug() {
  >&2 echo "DEBUG client $*"
}

info() {
  >&2 echo "INFO client $*"
}

warn() {
  >&2 echo "WARN client - $*"
}

error() {
  >&2 echo "ERROR client $*"
}

# lifecycle

abort() {
  echo "WARN abort: $*"
  exit 1
}


# utils

grepq() {
  [ $# -eq 1 ]
  grep -q "^${1}$"
}


# redis utils

redis() {
  $rediscli $*
}

redise() {
  expect=$1
  shift
  redisCommand="$@"
  if ! echo "$redisCommand" | grep -q " $ns:"
  then
    warn "$redisCommand"
    return 1
  fi
  reply=`$rediscli $redisCommand`
  if [ "$reply" != $expect ]
  then
    warn "$redisCommand - reply $reply - not $expect"
    return 2
  else
    return 0
  fi
}

redis0() {
  [ $# -gt 1 ]
  redise 0 $*
}

redis1() {
  [ $# -gt 1 ]
  redise 1 $*
}

expire() {
  info "expire $*"
  [ $# -eq 2 ]
  redis1 expire $*
}

exists() {
  [ $# -eq 1 ]
  redis1 exists $1
}

nexists() {
  [ $# -eq 1 ]
  redis0 exists $1
}

hgetall() {
  [ $# -eq 1 ]
  key=$1
  echo "$key" | grep -q "^$ns:\w[:a-z0-9]*$"
  >&2 echo "DEBUG hgetall $key"
  >&2 $rediscli hgetall $key
}

incr() {
  [ $# -eq 1 ]
  key=$1
  echo "$key" | grep -q "^$ns:\w[:a-z0-9]*$"
  seq=`$rediscli incr $key`
  echo "$seq" | grep '^[1-9][0-9]*$'
}

hsetnx() {
  [ $# -eq 3 ]
  $rediscli hsetnx $* | grep -q '^1$'
}

lpush() {
  [ $# -eq 2 ]
  reply=`$rediscli lpush $*`
  debug "lpush $* - $reply"
  echo "$reply" | grep -q '^[1-9][0-9]*$'
}

brpoplpush() {
  [ $# -eq 3 ]
  popId=`$rediscli brpoplpush $*`
  debug "brpoplpush $* - $popId"
  echo $popId | grep '^[1-9][0-9]*$'
}

brpop() {
  [ $# -eq 2 ]
  debug "$rediscli brpop $*"
  popId=`$rediscli brpop $* | tail -1`
  debug "brpop $* - $popId"
  echo $popId | grep '^[1-9][0-9]*$'
}

lrem() {
  [ $# -eq 3 ]
  $rediscli lrem $* | grep -q '^[1-9][0-9]*$'
}

llen() {
  [ $# -eq 1 ]
  llen=`$rediscli llen $*`
  debug "llen $* - $llen"
  echo $llen | grep '^[1-9][0-9]*$'
}

hincrbyq() {
  [ $# -eq 3 ]
  reply=`$rediscli hincrby $*`
  debug "hincrby $* - $reply"
  echo $reply | grep -q '^[1-9][0-9]*$'
}

hgetd() {
  [ $# -eq 3 ]
  defaultValue=$1
  key=$2
  field=$3
  value=`$rediscli hget $key $field`
  if [ -z "$value" ]
  then
    echo "$defaultValue"
  else
    echo $value
  fi
}

incrid() {
  [ $# -eq 1 ]
  name=$1
  id=`incr $ns:$name:id`
  redis0 exists $ns:$name:$id
  echo $id
}

count() {
   hincrbyq $ns:service:metric:$1 count 1
}

# test

c1req() {
  gitUrl="$1"
  id=`incr $ns:req:id`
  hsetnx $ns:req:$id git $gitUrl
  lpush $ns:req $id
  debug "OK $id $gitUrl"
  echo $id
}

c3req() {
  debug c3req $@
  [ $# -eq 3 ]
  gitUrl="$1"
  branch="$2"
  commit="$3"
  id=`incr $ns:req:id`
  hsetnx $ns:req:$id git $gitUrl
  [ -n "$branch" -a "$branch" != 'master' ] && hsetnx $ns:req:$id branch $branch
  [ -n "$commit" -a "$commit" != 'HEAD' ] && hsetnx $ns:req:$id commit $commit
  #[ -n "$tag" ] && hsetnx $ns:req:$id tag $tag
  lpush $ns:req $id
  debug "OK $id $gitUrl"
  echo $id
}

c2brpop() {
  reqId=$1
  popTimeout=$2
  resId=`brpop $ns:res $popTimeout | tail -1`
  if [ "$reqId" != "$resId" ]
  then
    warn "mismatched ids: $reqId, $resId: lpush $ns:res $resId"
    lpush $ns:res $resId
    return 1
  fi
  $rediscli hget $ns:res:$resId deployDir | grep '/'
}

c2deploy() {
  popTimeout=$1
  gitUrl=$2
  id=`c1req $gitUrl | tail -1`
  c2brpop $id $popTimeout
}

c4deploy() {
  [ $# -eq 4 ]
  resTimeout=$1
  shift
  id=`c3req $@ | tail -1`
  c2brpop $id $resTimeout
}

c0deploy() {
  set -e
  c4deploy 60 https://github.com/evanx/hello-component master HEAD
}

c0tclear13() {
  rm -rf $HOME/.ndeploy/demo-ndeploy
  redis-cli -n 13 keys "$ns:*" | xargs -n1 redis-cli -n 13 del
}


# command

info "rediscli: $rediscli"
info "args: $@"

command=test
if [ $# -ge 1 ]
then
  command=$1
  shift
  c$#$command $@
fi
