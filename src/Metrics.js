
export default class Metrics {

   constructor(name) {
      this.name = name;
   }

   async start(state) {
      Object.assign(this, state);
      this.redisNamespace = Asserts.assert(this.props.serviceNamespace, 'serviceNamespace');
      this.redisClient = service.createRedisClient(Asserts.assert(this.props.serviceRedis, 'serviceRedis'));
      this.logger.info('start');
   }

   async end() {
      this.ended = true;
      await this.redisClient.quitAsync();
   }

   async count(name, ...args) {
      try {
         const hashesKey = this.redisKey(name);
         this.logger.debug('count', name, hashesKey, args);
         await this.redisClient.multiExecAsync(multi => {
            logger.debug('count', hashesKey);
            multi.hincrby(hashesKey, 'count', 1);
            multi.hset(hashesKey, 'last', JSON.stringify(args));
         });
      } catch (err) {
         this.service.error(this, err);
      }
   }

   async sum(name, value, ...args) {
      try {
         const hashesKey = this.redisKey(name);
         const max = await this.redisClient.hgetAsync(hashesKey, 'max');
         this.logger.debug('sum', name, value, args);
         this.redisClient.multiExecAsync(multi => {
            multi.hincrby(hashesKey, 'count', 1);
            multi.hincrby(hashesKey, 'sum', value);
            if (!max || value > max) {
               multi.hset(hashesKey, 'max', value);
            }
         });
      } catch (err) {
         this.service.error(this, err);
      }
   }

   async histo(name, normalizedValue, ...args) {
      try {
         Invariants.validateRangeInclusive(normalizedValue, [0, 1], 'normalizedValue');
         const intervalIndex = Math.floor(normalizedValue*100);
         const hashesKey = this.redisKey(name);
         this.logger.debug('histo', name, normalizedValue, intervalIndex);
         await this.redisClient.multiExecAsync(multi => {
            multi.hincrby(hashesKey, 'histo' + intervalIndex, 1);
         });
      } catch (err) {
         this.service.error(this, err);
      }
   }

   async max(name, value, ...args) {
      try {
         const hashesKey = this.redisKey(name);
         const max = await this.redisClient.hgetAsync(hashesKey, 'max');
         this.logger.debug('done', name, value, args);
         this.redisClient.multiExecAsync(multi => {
            multi.hincrby(hashesKey, 'count', 1);
            if (!max || value > max) {
               multi.hset(hashesKey, 'max', value);
            }
         });
      } catch (err) {
         this.service.error(this, err);
      }
   }

   redisKey(...values) {
      return [this.redisNamespace, this.name, ...values].join(':');
   }
}
