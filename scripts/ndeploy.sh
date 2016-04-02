
set -u -e

# context

ns='demo:ndeploy'
rediscli='redis-cli -n 13'

if ! set | grep '^ns='
then
  ns='demo:ndeploy'
fi

if ! set | grep '^rediscli='
then
  rediscli='redis-cli -n 13'
fi


# logging

debug() {
  >&2 echo "DEBUG $ns $serviceId - $*"
}

info() {
  >&2 echo "INFO $ns $serviceId - $*"
}

warn() {
  >&2 echo "WARN $ns $serviceId - $*"
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

grepe() {
  [ $# -eq 1 ]
  expect="$1"
  if ! cat | grep -q "$expect"
  then
    echo "WARN $expect"
    return 0
  else
    return 1
  fi
}

# redis utils

redis() {
  $rediscli $*
}

redise() {
  expect=$1
  shift
  rcmd="$@"
  if echo "$rcmd" | grep -qv " $ns:"
  then
    >&2 echo "WARN $rcmd"
    return 1
  fi
  reply=`$rediscli $rcmd`
  if echo "$reply" | grep -v "^${expect}$"
  then
    >&2 echo "WARN $rcmd - reply $reply - not $expect"
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
  [ $# -eq 2 ]
  info "expire $*"
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
  echo "$reply" | -q grep '^[1-9][0-9]*$'
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

nsincr() {
  [ $# -eq 1 ]
  name=$1
  id=`incr $ns:$name:id`
  redis0 exists $ns:$name:$id
  echo $id
}

# init service, to expire after 120 seconds

serviceId=`nsincr service | tail -1`
redis0 exists $ns:service:$serviceId
hsetnx $ns:service:$serviceId pid $$
hsetnx $ns:service:$serviceId started `$rediscli time | head -1`
expire $ns:service:$serviceId 120
hgetall $ns:service:$serviceId
serviceDir=$HOME/.ndeploy/`echo $ns | tr ':' '-'`
info "service: $serviceId $ns $serviceDir"
mkdir -p $serviceDir && cd $serviceDir || exit 1
info 'pwd' `pwd`

v1popError() {
  id=$1
  echo "ERROR pop: $*"
  $rediscli lpush $ns:req $id
  $rediscli lrem $ns:req:pending -1 $id
  exit 9
}

pendingId=''

c0exit() {
  if [ -n "$pendingId" ]
  then
    v1popError $pendingId
  fi

}

trap c0exit exit

c1pop() {
  popTimeout=$1
  expire $ns:service:$serviceId $popTimeout
  rcmd="brpoplpush $ns:req $ns:pending $popTimeout"
  id=`$rediscli $rcmd | grep '^[1-9][0-9]*$'`
  debug "popped $id"
  [ -n $id ]
  pendingId=$1
  expire $ns:req:$id 10
  hgetall $ns:req:$id
  c1popped $id
  redis1 sadd $ns:res:ids $id
  redis1 persist $ns:res:$id
  hgetall $ns:res:$id
  lpush $ns:res $id
  pendingId=''
}

c1popped() {
  id=$1
  git=`$rediscli hget $ns:req:$id git | grep '^http\|^git@'`
  branch=`hgetd master $ns:req:$id branch`
  commit=`$rediscli hget $ns:req:$id commit`
  cd $serviceDir
  ls -lht
  deployDir="$serviceDir/$id"
  [ ! -d $deployDir ]
  hsetnx $ns:res:$id deployDir $deployDir
  expire $ns:res:$id 600
  echo "INFO deployDir $deployDir"
  mkdir -p $deployDir && cd $deployDir
  git clone $git -b $branch $branch
  cd $branch
  if [ -n "$commit" ]
  then
    echo "INFO git checkout $commit -- $git $branch"
    git checkout $commit
  fi
  hsetnx $ns:res:$id cloned `stat -c %Z $deployDir`
  if [ -f package.json ]
  then
    cat package.json
    npm --silent install
    hsetnx $ns:res:$id npmInstalled `stat -c %Z node_modules`
  fi
  actualCommit=`git log | head -1 | cut -d' ' -f2`
  echo "INFO actualCommit $actualCommit"
  hsetnx $ns:res:$id actualCommit $actualCommit
  deployDir=`$rediscli hget $ns:res:$id deployDir`
  2>&1 echo "OK $id $deployDir"
  echo $deployDir | grep '/'
}


# test

c1req() {
  gitUrl="$1"
  id=`incr $ns:req:id`
  hsetnx $ns:req:$id git $gitUrl
  lpush $ns:req $id
  echo "OK $id $gitUrl"
  echo $id
}

c2brpop() {
  reqId=$1
  popTimeout=$2
  resId=`brpop $ns:res $popTimeout`
  if [ "$reqId" != $id ]
  then
    >&2 echo "mismatched id: $resId"
    redis-cli lpush $ns:res $resId
    return 1
  fi
  echo "$reqId" | grep '^[1-9][0-9]*$'
  $rediscli hget $ns:res:$id deployDir | grep '/'
}

c2deploy() {
  gitUrl=$1
  popTimeout=$2
  id=`c1req $gitUrl | tail -1`
  c2brpop $id $popTimeout
}

c0tdeploy() {
  set -e
  c2deploy https://github.com/evanx/hello-component 60
}

c0clear13() {
  redis-cli -n 13 keys "$ns:*" | xargs -n1 redis-cli -n 13 del
  rm -rf $HOME/.ndeploy/demo-ndeploy
}

c0test() {
  c0tpush & c1pop 10
}


# command

info "rediscli $rediscli"
info "args $@"

command=test
if [ $# -ge 1 ]
then
  command=$1
  shift
  c$#$command $@
fi
