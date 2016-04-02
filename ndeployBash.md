

## ndeploy bash script

#### ndeploy

This service should `git clone` and `npm install` packages according to a Redis-based request.

We `brpoplpush` a request `id` and `hget :req:$id` fields:
- mandatory `git` URL
- optional `branch` - otherwise defaulted to `master`
- optional `commit` SHA - otherwise defaulted to `HEAD`
- optional `tag`

So the `req` hashes contain the git URL at least:
```
hgetall demo:ndeploy:req:9
1) "git"
2) "https://github.com/evanx/hello-component"
```

Let's implement this service in bash:
```shell
set -u -e # exit on error, including undefined parameters

c1pop() {
  popTimeout=$1
  redis1 expire $ns:service:$serviceId 120
  id=`brpoplpush $ns:req $ns:pending $popTimeout`
  if [ -z "$id" ]
  then
    >&1 echo "ERROR $id timeout"
    return 1
  then
    set -e
    c1popped $id
    set +e
  fi
}
```
where we `brpoplpush` with a `popTimeout` (in seconds).

Note that we choose to expire the service instance in `120` seconds. After that, the subsequent call to `pop` will error, and the script will exit.  

###### Service expiry

When the `service` key has expired, and the `expire` command will reply with `0.` Our `redis1` utility function expects a reply of `1` and otherwise errors.

Since the script will exit in the event of any errors, it should be automatically restarted. For example if a new service instance is going to be started by the cron every minute, then its `:service:$id` could expire every 120 seconds, so that we have at most two running at once.

###### Request handling

Otherwise the popped id is handled as follows.
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
where `c5deploy` will `git clone` and `npm install` the `deployDir.`

For demonstration, we manually try a sample deploy:
```shell
c1deploy() {
  gitUrl=$1
  id=`c1req | tail -1`
  c1brpop $id
}
```

We `incr` and `lpush` the request id as follows:
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

The following function will match the response:
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
where this will echo the `deployDir` and otherwise lpush the id back into the queue, and error out.

We run a test service instance in the background that will pop a single request and then exit
```
$ ndeploy pop 60 &
```
where the pop timeout is `60` seconds, after which it will error.

This is commanded as follows:
```
$ ndeploy deploy https://github.com/evanx/hello-component | tail -1
```
This will echo the directory with the successful deployment:
```
/home/evans/.ndeploy/demo-ndeploy/8
```

###### git clone

The service must:
- `git clone` the URL e.g. from Github, into the directory `.ndeploy/demo-ndeploy/$id/master`
- `git checkout $commit` if a commit hash is specified in the `:req:$id` hashes

```shell
  git clone $git -b $branch $branch
  cd $branch
  if [ -n "$commit" ]
  then
    git checkout $commit
  fi
  hsetnx $ns:res:$id cloned `stat -c %Z $deployDir`
```
where we set the `cloned` timestamp.

###### npm install

```shell  
  if [ -f package.json ]
  then
    npm --silent install
    hsetnx $ns:res:$id npmInstalled `stat -c %Z node_modules`
  fi
```

Let's manually check the `package.json` for this deployment:
```shell
~/mpush-redis$ cat ~/.ndeploy/demo-ndeploy/9/master/package.json
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

###### res

We set `:res:$id` hashes for:
 - the `deployDir` of the `git clone` et al
 - the `actualCommit` SHA according to `git log`

```shell
  actualCommit=`git log | head -1 | cut -d' ' -f2`
  hsetnx $ns:res:$id actualCommit $actualCommit
```
where we `hsetnx` response hashes e.g. `demo:ndeploy:res:9` (matching the `req:9` request).

Finally we pushes the request `id` to the `:res` list.
```shell
  lpush $ns:res $id
```
We can now `lrem :req:pending $id`
```shell
  lrem $ns:req:pending -1 $id
```
where we scan from the tail of the list.


##### Resources

See: https://github.com/evanx/mpush-redis/blob/master/scripts/ndeploy.sh


### Further reading

Related projects and further plans: https://github.com/evanx/mpush-redis/blob/master/related.md
