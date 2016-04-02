
module.exports = {
   redis: 'redis://localhost:6379/1',
   serviceRedis: 'redis://localhost:6379/1',
   serviceNamespace: 'demo:mpush',
   serviceExpire: 60,
   serviceRenew: 10,
   serviceCapacity: 10,
   messageExpire: 60,
   messageTimeout: 10,
   messageCapacity: 1000,
   popTimeout: 10,
   in: 'demo:mpush:in',
   pending: 'demo:mpush:pending',
   out: ['demo:mpush:out0', 'demo:mpush:out1'],
   done: 'demo:mpush:done',
};
