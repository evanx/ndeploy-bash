
export function createLogger(filename) {
   var name = filename.match(/([^\/\\]+)\.[a-z0-9]+/)[1];
   return bunyan.createLogger({name: name, level: global.loggerLevel});
};
