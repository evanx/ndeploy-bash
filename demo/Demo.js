
export default class Demo {

   constructor(name, options) {
      this.name = name;
      this.options = options;
   }

   async start(that) {
      Object.assign(this, that);
      this.logger.info('started', this.props.redis);
      this.redisClient = this.service.createRedisClient(this.props.redis);
      const messages = ['one', 'two', 'three'];
      setTimeout(async () => {
         for (const message of messages) {
            this.logger.info('push', this.props.in, message);
            await this.service.delay(500);
            await this.redisClient.lpushAsync(this.props.in, message);
         }
         setTimeout(async () => {
            if (this.options && this.options.auto) {
               let [[id0], [id1]] = await this.redisClient.multiExecAsync(multi => {
                  logger.info('lrange', this.props.out);
                  multi.lrange(this.props.out[0], 0, 0);
                  multi.lrange(this.props.out[1], 0, 0);
               });
               logger.info('results', id0, id1);
               assert.equal(id0, lodash.last(messages), 'last id');
               assert.equal(id1, lodash.last(messages), 'last id');
               this.service.end();
            }
         }, 1000);
      }, 1000);
   }

   async end() {
      await this.redisClient.quitAsync();
   }
}
