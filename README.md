
## ndeploy-bash

To celebrate a big week for `bash` with the Windows 10 announcement, we implement a ephemeral stateless microservice that will `git clone` and `npm install` repos according to a Redis-based request.

- performs a blocking pop on an Redis list for an incoming request
- request/response pairs are assigned a unique id by incrementing a Redis serial number
- information is exchanged via Redis request/response hashes
- an async response notification is published via a Redis list

This service is intended for the orchestration of a distributed system of Redis-driven microservices, e.g. a distributed webserver as per https://github.com/evanx/mpush-redis/blob/master/related.md

This service uses a similar Redis-based service lifecycle model as our `mpush-redis` Node service, described in: https://github.com/evanx/mpush-redis/blob/master/service.md.

The maximum TTL of each instance is controlled via its service key e.g. which expires in 120 seconds.


### bash

As an exercise, this service is implemented in `bash.` We improve its robustness by `set -e` i.e. by automatically exiting when any command "errors" i.e. returns nonzero.

For example, we use `grep` to check Redis replies:
```shell
redis1() {
  $rediscli | grep -q '^1$'
}
```
where the script will automatically exit if the reply is not matched, because of the exit-on-error setting.

As such redundant instances must be supported. Typically we might start a new service instance every minute via the cron. Since its maximum TTL is 2 minutes, this ensures that at most two instances are running concurrently.


### Status

UNSTABLE - untested initial prototype for demonstration purposes


### Demo

```shell
~/ndeploy-bash$ sh scripts/demo.sh
```
Beware the defaults:
```shell
ns='demo:ndeploy'
rediscli='redis-cli -n 13'
```
where `ns` is the "namespace" used to prefix keys.


### Implementation

Let's walk through the `ndeploy` script: https://github.com/evanx/ndeploy-bash/blob/master/bin/ndeploy

The script is configured via environment variables:
- `ns` - the Redis "namespace" e.g. `demo:ndeploy`
- `rediscli` - the Redis connection command e.g. `redis-cli -n 13 -p 6379`


##### Self-registration

In this case, we `incr` a unique sequential `serviceId.` We `hsetnx` the details on the `serviceKey:`
```shell
serviceId=`incr $ns:service:id`
serviceKey="$ns:service:$serviceId"
startedTimestamp=`$rediscli time | head -1`
count started $startedTimestamp
hsetnx $serviceKey started $startedTimestamp
expire $serviceKey 120
hsetnx $serviceKey host `hostname -s`
hsetnx $serviceKey pid $$
sadd $ns:service:ids $serviceId
```
Clearly the `serviceKey` is unique, but nevertheless for sanity we use `hsetnx` rather than `hset.` Our `hsetnx` utility function expects a reply of `1` and otherwise errors, and so the script will exit.

For example, service instance hashes are as follows:
```
hgetall demo:ndeploy:service:8
1) "host"
2) "eowyn"
3) "pid"
4) "14527"
5) "started"
6) "1459637169"
```


##### Blocking pop

We `brpoplpush` a request `id` and `hget` its request details, namely:
- mandatory `git` URL
- optional `branch` - otherwise defaulted to `master`
- optional `commit` SHA - otherwise defaulted to `HEAD`
- optional `tag`

So the request hashes contain the git URL at least:
```
hgetall demo:ndeploy:req:8
1) "git"
2) "https://github.com/evanx/hello-component"
```
In this case, we default to `HEAD` of the `master` branch.

Let's implement this service in bash:
```shell
c0pop() { # popTimeout
  popTimeout=$1
  redis1 exists $serviceKey
  id=`brpoplpush $ns:req $ns:pending $popTimeout`
  [ -n "$id" ] && c1popped $id
}
```
where we `brpoplpush` the next request `id` and call `c1popped` with that.

Note that we exit if the the service key does not exist, courtesy of our `redis1` function.

Otherwise we loop forever as follows:
```shell
c1loop() { # popTimeout
   popTimeout=$1
   while true
   do
     c0pop $popTimeout
   done
}   
```

#### Command functions

We use a convention for CLI-capable command functions where e.g. a `c1` prefix means there is `1` argument for this command:
```shell
if [ $# -ge 1 ]
then
  command=$1
  shift
  c$#$command $@
fi
```
We can call command functions from the command-line as follows:
```shell
$ bin/ndeploy loop 60
```
where this will call `c1loop 60` i.e. with a parameter of `60` for the `popTimeout` seconds.

To help, we print out the commands:
```shell
evans@eowyn:~/ndeploy-bash$ bin/ndeploy
1 loop # popTimeout
1 popped # id
1 pop # popTimeout
```

##### Service expiry

We expire its `serviceKey` in 120 seconds:
```shell
redis1 expire $serviceKey 120
```

At this expire interval, if starting a new instance every minute via the cron, then we should observe at most two instances running at a time. If each instance errors immediately, then no instances will be running for the minute.


##### Metrics

We push metrics into Redis:
```shell
hincrby $ns:service:metric:started count 1
```
where these metrics are published/alerted by another microservice i.e. out the scope.


#### Request handling

The popped id is handled as follows:
```shell
c1popped() {
  id=$1
  hsetnx $ns:res:$id service $serviceId
  git=`hget $ns:req:$id git`
  branch=`hget $ns:req:$id branch`
  commit=`hget $ns:req:$id commit`
  tag=`hget $ns:req:$id tag`
  deployDir="$serviceDir/$id"
  mkdir -p $deployDir && cd $deployDir && pwd
  hsetnx $ns:res:$id deployDir $deployDir
  c5deploy $git "$branch" "$commit" "$tag" $deployDir
```
where `c5deploy` will `git clone` and `npm install` the package into `deployDir.`


### Demo client

Let's walk through the client-side request script: https://github.com/evanx/ndeploy-bash/blob/master/scripts/test-client.sh

This is invoked by the "demo" script to initiate a test request:

```shell
  sh bin/ndeploy pop 10 &
  deployDir=`sh scripts/test-client.sh deploy | tail -1`
```

See: https://github.com/evanx/ndeploy-bash/blob/master/scripts/demo.sh


#### Request creation

We try the following client `deploy` "command" with a `gitUrl` parameter.
```shell
c1deploy() { # gitUrl
  gitUrl=$1
  id=`c1req | tail -1`
  c1brpop $id
}
```

Note that since `{branch, commmit, tag}` have not been specified, we expect the current `HEAD` of `master.`

We create a new client request as follows:
```shell
c1req() {
  gitUrl="$1"
  id=`nsincr $ns:req:id`
  hsetnx $ns:req:$id git $gitUrl
  lpush $ns:req $id
  echo $id
}
```
where we:
- `incr` a sequence number to get a unique request id
- `hsetnx` the git URL on request hashes
- `lpush` the request id to submit the request to the service


#### Response processing

The service will asynchronously respond to the client's request via a Redis list e.g. `demo:ndeploy:res.`

We pop responses to get the prepared `deployDir` as follows:
```shell
c1brpop() {
  reqId="$1"
  resId=`brpop $ns:res`
  if [ "$reqId" != $id ]
  then
    >&2 echo "mismatched id: $resId"
    lpush $ns:res $resId
    sleep 1
    return 1
  fi
  hget $ns:req:$resId deployDir | grep '/'
}
```
where we match the request id, and then output the `deployDir` as successfully prepared by the backend service.

If the response id does not match our request, then we `lpush` the id back into the queue, and error/exit.


##### Test server

We run a test service instance in the background that will pop a single request and then exit:
```
$ bin/ndeploy pop 60 &
```
where the blocking pop timeout is specified as `60` seconds.

We command test client as follows:
```
$ scripts/test-client.sh deploy https://github.com/evanx/hello-component | tail -1
```
This will error, or echo the directory with the successful deployment:
```
/home/evans/.ndeploy/demo-ndeploy/8
```
where `demo-ndeploy` relates to the service namespace, and `8` is the service id.

Incidently, the default `serviceDir` is formatted from the `ns` as follows:
```shell
serviceDir=$HOME/.ndeploy/`echo $ns | tr ':' '-'`
```
where any semicolon in the `ns` is converted to a dash in the `deployDir.`


##### git clone

The service must:
- `git clone` the URL e.g. from Github into the directory: `.ndeploy/demo/$id/master`
- `git checkout $commit` if a commit hash is specified in the `:req:$id` hashes
- `git checkout tags/$tag` if a tag is specified rather than a commit hash

```shell
  git clone $git -b $branch $branch
  cd $branch
  if [ -n "$commit" ]
  then
    git checkout $commit
  fi
  hsetnx $ns:res:$id cloned `stat -c %Z $deployDir`
```
where we set the `cloned` timestamp to the modtime of the `deployDir.`


##### npm install

```shell  
  if [ -f package.json ]
  then
    npm --silent install
    hsetnx $ns:res:$id npmInstalled `stat -c %Z node_modules`
  fi
```
where we set the `npmInstalled` timestamp to the modtime of `node_modules/.`

Let's manually check the `package.json` for this deployment:
```shell
~/mpush-redis$ cat ~/.ndeploy/demo/8/master/package.json
```

```json
{
  "name": "hello-component",
  "version": "0.1.0",
  "description": "",
  "main": "index.js",
  "scripts": {
    "start": "node index.js"
  },
  "author": "@evanxsummers",
  "license": "ISC",
  "dependencies": {
  }
}
```

##### res

We can inspect the response metadata as follows:
```
hgetall demo:ndeploy:res:8
1) "deployDir"
2) "/home/evans/.ndeploy/demo-ndeploy/1"
3) "cloned"
4) "1459607390"
5) "npmInstalled"
6) "1459607395"
7) "actualCommit"
8) "c6a9326f46a92d1f7edc4d2a426c583ec8f168ad"
```
which includes the `actualCommit` SHA according to `git log` e.g. for `HEAD` at the time of the checkout:
```shell
  actualCommit=`git log | head -1 | cut -d' ' -f2`
  hsetnx $ns:res:$id actualCommit $actualCommit
```
where the service sets e.g. `:res:8` (matching the `:req:8` request).

It notifies the client that the response is ready by pushing the id to the `:res` list.
```shell
  lpush $ns:res $id
```
 Incidently, the service will `lrem` the id from the pending list:
```shell
  lrem $ns:req:pending -1 $id
```
where we scan from the tail of the list via the `-1` parameter.


### Resources

See: https://github.com/evanx/mpush-redis/blob/master/bin/ndeploy


### Further reading

Related projects and further plans: https://github.com/evanx/mpush-redis/blob/master/related.md
