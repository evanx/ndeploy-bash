#!/bin/bash

set -u -e

scriptDir=`dirname $0`

# help (listing commands)

if [ $# -eq 0 ]
then
   cat $0 | grep ^c[0-9] | sed 's/^c\([0-9]\)\(\w*\)() {\s*[\W#]*\s*\(.*\)$/\2 \1 \3/' | sort
   exit 0
fi


# env context

ns=${ns:=demo\:ndeploy}
rediscli=${rediscli:=redis-cli -n 13}


# client init

loggerName=client


# require utils

. $scriptDir/.util-ndeploy.sh

debug test

# client requests

f1req() { # gitUrl - create a new request
  gitUrl="$1"
  id=`incr $ns:req:id`
  hsetnx $ns:req:$id git $gitUrl
  lpush $ns:req $id
  debug "OK $id $gitUrl"
  echo $id
}

f3req() { # gitUrl branch commit - create a new request
  debug f3req $@
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
  debug "req $id $gitUrl"
  echo $id
}

f2brpop() { # reqId reqTimeout - brpop next response
  reqId=$1
  reqTimeout=$2
  resId=`brpop $ns:res $reqTimeout | tail -1`
  if [ -z "$resId" ]
  then
    error "timeout ($reqTimeout seconds) waiting for response (reqId $reqId)"
    return 1
  elif [ "$reqId" != "$resId" ]
  then
    lpush $ns:res $reqId
    error "mismatched ids: $reqId, $resId: lpush $ns:res $resId"
    return 1
  fi
  error=`$rediscli hget $ns:res:$resId error`
  if [ -n "$error" ]
  then
     error "$error"
     exit 9
  fi
  deployDir=`$rediscli hget $ns:res:$resId deployDir`
  echo "OK res $resId $deployDir"
  cd $deployDir
  git remote -v | head -1
  git status | head -1
  git log | head -3
  pwd
}

c2deploy() { # gitUrl reqTimeout - request new deployDir
  gitUrl=$1
  reqTimeout=$2
  id=`f1req $gitUrl | tail -1`
  f2brpop $id $reqTimeout
}

# command

info "rediscli: $rediscli"
info "args: $@"

if [ $# -ge 1 ]
then
  command=$1
  shift
  c$#$command $@
fi
