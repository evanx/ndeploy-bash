

### Related projects

#### vpush-redis

An upcoming `vpush-redis` service will "reliably" move messages to a "remote" Redis queue.

That name is an acronym for "value push," since it's purpose is to push a Redis value

The `vpush` microservice must:
- be configured with one input and one output queue on different Redis URLs
- retry delivery of each message indefinitely
- process at most one message at a time, across all replica service instances


#### lpush-redis

We will implement another microservice, namely `lpush,` for the case where input and output queues are on the same Redis instance. This implementation will use `multi.`

This service is clearly trivial, but still operationally useful.

For example, it might be used in conjunction with dedupe or rate-limiting microservices.


### Further plans

#### Multiple repos vs a unified toolkit

It might make more sense to combine the various services e.g. `mpush` vs `lpush` et al, into a toolkit, i.e. in one repo.

However, the idea of "immutable microservices" appeals to me.

This effort seems to have become an exploratory re-implementation of my Redex framework. However it was really prompted by a production need for `mpush,` and a belief in the practicality of independently-deployable microservices.

Ideally speaking:
- Generally-useful microservices should be feature-complete.
- Generally-useful modules should be in their own repo.

This work will surely prompt a refactoring of Redex, say for version 0.2, and some services will use Redex 0.2, as a git submodule.


#### Mpush "suite"

The over-arching goal is to implement many such microservices for common integration and messaging patterns, for the purpose of composing stateless Redis-based microservices.

- vpush - transport messages to a remote Redis instance
- mdispatch - tracking messages for response handling, e.g. building a distributed web server
- mbalance - push a message to a work queue with the lowest queue length

Also, for the fun of building a distributed web server:
- hfiler - file server for serving static assets i.e. a "static webserver"
- hgateway - import an HTTP request into a Redis queue for subsequent routing and processing
- hrouter - route an HTTP message by matching its URL (using regex)
- hrender - render a React template
- rquery - retrieve data from Redis
- ndeploy - NPM module installation triggered by Redis-based messaging
- rcontrol - service "orchestration" e.g. control and monitoring, triggered by Redis-based messaging

Typically these are microservices that interact "internally" via Redis, and externally via HTTP, e.g. the `hgateway` service includes an ExpressJS webserver.


#### Technology choices

Incidently, similar services are also planned which use NATS for high-performance "fire-and-forget" messaging.

However, we typically prefer to use Nginx to handle high-performance HTTP caching and switching, and Node/Redis to handle application programming. Microservices that must handle say 10k messages per second, should be probably be developed in Go, and be using NATS.

For microservices which individually handle a hundred or less requests per second, and are scaled horizontally, I believe Node is a great choice. Node is highly productive, and performant enough for most applications.

We observe that enterprise and server-side development tends to follow web development trends. Clearly "Universal JavaScript" is compelling for web development, and especially now with:
- ES6 - e.g. arrow functions with sane `this`
- ES2016 - async/await sugaring of ES6 promises/generators

The new features of JavaScript are too numerous to mention. Moreover these are enabled for immediate use on all platforms via Babel. The annual cadence of JS/ES standardisation, and the convergence of JavaScript and TypeScript, is rather exciting.

I believe that stateless microservices, Redis, Node and ES2016 are complementary technologies:
- microservices are simple to write
- Redis is great for shared state and asynchronous messaging, to enable stateless microservices
- Node is great for small codebases like microservices
- ES2016 async/await is great for Node i.e. to avoid nested callbacks and repetitive error handling


#### Planned demo

My "holy grail" goal would be demonstrating a resilient auto-scaling distributed webserver. I believe that this can be implemented relatively easily by leveraging a Redis Cluster for persistent message storage, shared memory/state for "stateless" microservices, metrics/monitoring, and "declarative" service orchestration.

For example, setting the number of replicas for a service in Redis, should enable the activation of standby instances, the automatic provisioning of additional instances, and/or the deactivation of excess instances. The performance and health of services (and hosts) will be monitored via metrics published via Redis, e.g. to rollback faulty updates.

While generally-speaking I favour "active" monitoring e.g. HTTP/JSON pull, I'm currently interested in the convenience of pushing metrics directly into Redis.

I don't argue that using nginx, Kubernetes, Prometheus etc, is the sane approach. Nevertheless, building a demo as described would be a fun R&D experience, with various potential positive outcomes.


#### hgateway

This implements a "web server", i.e. accepts incoming HTTP requests e.g. via ExpressJS i.e. via TCP/IP socket. However, its purpose however is to merely to publish these into a Redis queue for further processing by other microservices. Those services will accept HTTP-request messages via a Redis queue, rather than a TCP/IP socket.

`hgateway` must:
- discover its configuration, including the HTTP port, via Redis hashes.
- start webserver on the configured port i.e. `listen(PORT)` for incoming HTTP requests.
- implement a request handler e.g. invoked by ExpressJS with `(req, res)`
- schedule a timeout handler e.g. a closure with access to `res`
- construct an HTTP request message i.e. including the URL, HTTP headers and "body content."
- push this "immutable" message into a Redis list e.g. `hgateway:req`
- `brpoplpush` a response message from a Redis list e.g. `hgateway:res`
- cancel the timeout handler
- respond to the original HTTP request via ExpressJS


#### hfiler

`hfiler` implements an HTTP service, meaning it processes HTTP messages. However it is not necessarily an "HTTP server" in the usual sense i.e. binding to a TCP/IP socket.

Its purpose is to enable a "static webserver" e.g. for serving assets.

`hfiler` must:
- match an HTTP request URL to a file-system based asset
- load this asset from the filesystem into Redis, with flexible expiry
- enable programmable expiry via a configurable Node module path
- optionally gzip the content in Redis


#### ndeploy

This service should `git clone` and `npm install` packages according to a Redis-based request.

Read: https://github.com/evanx/mpush-redis/blob/master/ndeployBash.md


###### req

We `brpoplpush` a request `id` and `hget :req:$id` fields:
- the `git` URL
- optional `branch` otherwise defaulted to `master`
- optional `commit` otherwise defaulted to `HEAD`

So the `req` hashes contain the git URL at least:
```
hgetall demo:ndeploy:req:9
1) "git"
2) "https://github.com/evanx/hello-component"
```

We run a test service instance in the background that will pop a single request and then exit
```
$ ndeploy pop 60 &
```
where the pop timeout is `60` seconds, after which it will error.

Incidently, the script should exit in the event of any errors, and so should be automatically restarted.

For example if a new service instance is going to be started by the cron every minute, then its `:service:$id` could expire every 120 seconds, so that we have at most two running at once.

This deployment is commanded as follows:
```
$ ndeploy deploy https://github.com/evanx/hello-component | tail -1
```
This should echo the directory with the successful deployment:
```
/home/evans/.ndeploy/demo-ndeploy/8
```

We can inspect the response metadata as follows:
```
> hgetall demo:ndeploy:res:8
1) "deployDir"
2) "/home/evans/.ndeploy/demo-ndeploy/1"
3) "cloned"
4) "1459607390"
5) "npmInstalled"
6) "1459607395"
7) "actualCommit"
8) "c6a9326f46a92d1f7edc4d2a426c583ec8f168ad"
```

Code: https://github.com/evanx/mpush-redis/blob/master/scripts/ndeploy.sh


### Further reading

Service lifecycle management: https://github.com/evanx/mpush-redis/blob/master/service.md

Message lifecycle management, for timeouts etc: https://github.com/evanx/mpush-redis/blob/master/message.md

Metrics, for timeouts etc: https://github.com/evanx/mpush-redis/blob/master/metrics.md

Component model: https://github.com/evanx/component-validator/blob/master/README.md
