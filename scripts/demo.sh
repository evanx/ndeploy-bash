
set -e -u

unset ns
unset rediscli

pwd=`pwd`

ns='demo:ndeploy'
rediscli='redis-cli -n 13'

  ns=$ns rediscli=$rediscli sh scripts/test-client.sh tclear13
  ns=$ns rediscli=$rediscli sh bin/ndeploy pop 10 &
  deployDir=`ns=$ns rediscli=$rediscli sh scripts/test-client.sh deploy | tail -1`
  echo deployDir $deployDir
