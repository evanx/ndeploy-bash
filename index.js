
global.assert = require('assert');
global.bluebird = require('bluebird');
global.bunyan = require('bunyan');
global.crypto = require('crypto');
global.fs = require('fs');
global.http = require('http');
global.lodash = require('lodash');
global.os = require('os');
global.redisLib = require('redis');

global.ServiceError = function() {
  this.constructor.prototype.__proto__ = Error.prototype;
  Error.captureStackTrace(this, this.constructor);
  this.name = this.constructor.name;
  var args = [].slice.call(arguments);
  this.message = JSON.stringify(args);
}

global.ValidationError = function() {
  this.constructor.prototype.__proto__ = Error.prototype;
  Error.captureStackTrace(this, this.constructor);
  this.name = this.constructor.name;
  var args = [].slice.call(arguments);
  this.message = JSON.stringify(args);
}

global.logger = global.bunyan.createLogger({name: 'entry', level: 'debug'});

bluebird.promisifyAll(redisLib.RedisClient.prototype);
bluebird.promisifyAll(redisLib.Multi.prototype);
redisLib.RedisClient.prototype.multiExecAsync = function(fn) {
   var multi = this.multi();
   fn(multi);
   return multi.execAsync();
};

require("babel-polyfill");
require('babel-core/register');
global.logger.debug('babel registered');

var propsMeta = require('./src/Service.props');

global.loggerLevel = 'info';
if (process.env.loggerLevel) {
   global.loggerLevel = process.env.loggerLevel;
} else if (process.env.NODE_ENV === 'development') {
   global.loggerLevel = 'debug';
}
global.Loggers = require('./src/Loggers');
global.Asserts = require('./src/Asserts');
global.Invariants = require('./src/Invariants');
global.Invariants.start(propsMeta);
var Service = require('./src/Service').default;
//logger.debug('App', typeof App, Object.keys(App));
global.service = new Service();
global.service.start().then(function() {
   global.logger.info('started pid', process.pid);
   process.on('SIGTERM', function() {
      global.logger.info('SIGTERM')
      global.service.end();
   });
}).catch(function(err) {
   global.logger.error(err);
   setTimeout(function() {
      global.service.end();
   }, 1000);
});
