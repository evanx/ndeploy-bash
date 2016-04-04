
set -e -u

unset ns
unset rediscli

pwd=`pwd`

ns='demo:ndeploy'
rediscli='redis-cli -n 13'

gitUrl='https://github.com/evanx/hello-component-class'

  ns=$ns rediscli=$rediscli sh scripts/adhoc.sh clear13
  ns=$ns rediscli=$rediscli bin/server-ndeploy.sh pop 10 &
  deployDir=`ns=$ns rediscli=$rediscli bin/ndeploy.sh $gitUrl 60 | tail -1`
  echo deployDir $deployDir
