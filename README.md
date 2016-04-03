
## ndeploy-bash

To celebrate a big week for `bash` with the Windows 10 announcement, we implement a ephemeral stateless microservice that will `git clone` and `npm install` repos according to a Redis-based request.

- performs a blocking pop on an Redis list for an incoming request
- request/response pairs are assigned a unique id by incrementing a Redis serial number
- information is exchanged via Redis request/response hashes
- an async response notification is published via a Redis list

This service is intended for the orchestration of a distributed system of Redis-driven microservices, e.g. a distributed webserver as per https://github.com/evanx/mpush-redis/blob/master/related.md

The maximum TTL of each instance is controlled via its service key e.g. which expires in 120 seconds.

This service uses a similar Redis-based service lifecycle model as our `mpush-redis` Node service, described in: https://github.com/evanx/mpush-redis/blob/master/service.md.


### bash

As an exercise, this service is implemented in `bash.` We improve its robustness by `set -e` i.e. by automatically exiting when any command "errors" i.e. returns nonzero. We use `grep` to check Redis replies and exit if it is not as expected.

Any number of concurrent redundant instances is supported. Typically we might start a new service instance every minute via `crond.` Since its maximum TTL is 2 minutes, this ensures that at most two instances are running concurrently.


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

Firstly, to make the script robust, we must exit on error:
```shell
set -u -e
```

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

Note that our `redis1` utility function expects a reply of `1` and otherwise errors.

So if the `service` key has expired or been deleted:
- the `exists` command will reply with `0`
- consequently the `redis1` function errors, since this checks for a `1` reply
- the script will exit, because we `set -e`

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

Note we use a convention for CLI-capable command functions where e.g. a `c1` prefix means there is `1` argument for this command:
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

We use the following `deploy` "command" with a `gitUrl` parameter.
```shell
c1deploy() {
  gitUrl=$1
  id=`c1req | tail -1`
  c1brpop $id
}
```

Note that since `{branch, commmit, tag}` have not been specified, we default `master` and `HEAD.`

The script will `incr` and `lpush` the request id as follows:
```shell
c1req() {
  gitUrl="$1"
  id=`nsincr $ns:req:id`
  hsetnx $ns:req:$id git $gitUrl
  lpush $ns:req $id
  echo $id
}
```
where we set the Git URL via request hashes.

The following function will match the response id:
```shell
c1brpop() {
  reqId="$1"
  resId=`brpop $ns:res`
  if [ "$reqId" != $id ]
  then
    >&2 echo "mismatched id: $resId"
    lpush $ns:res $resId
    return 1
  fi
  hget $ns:req:$id deployDir | grep '/'
}
```
where this will echo the `deployDir` and otherwise `lpush` the id back into the queue, and error out.


##### Test server

We run a test service instance in the background that will pop a single request and then exit:
```
$ ndeploy pop 60 &
```
where the blocking pop timeout is specified as `60` seconds.

This is commanded as follows:
```
$ ndeploy deploy https://github.com/evanx/hello-component | tail -1
```
This will echo the directory with the successful deployment:
```
/home/evans/.ndeploy/demo-ndeploy/8
```
where `demo` relates to the service namespace, and `8` is the service id.

Incidently, the default `serviceDir` is formatted from the `ns` as follows:
```shell
serviceDir=$HOME/.ndeploy/`echo $ns | tr ':' '-'`
```
where any semi-colon in the `ns` is converted to a dash in the `deployDir.`


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
where we `hsetnx` response hashes e.g. `demo:ndeploy:res:8` (matching the `req:8` request).

We push the request `id` to the `:res` list.
```shell
  lpush $ns:res $id
```
 Fiinally we `lrem` the request id from the pending list:
```shell
  lrem $ns:req:pending -1 $id
```
where we scan from the tail of the list.


### Resources

See: https://github.com/evanx/mpush-redis/blob/master/bin/ndeploy


### Further reading

Related projects and further plans: https://github.com/evanx/mpush-redis/blob/master/related.md
