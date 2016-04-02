
export default class MessagePush {

   constructor(name) {
      this.name = name;
   }

   async start(state) {
      Object.assign(this, state);
      this.redisClient = service.createRedisClient(this.props.redis);
      this.runPromise = this.run();
   }

   async end() {
      this.ended = true;
      return this.runPromise;
   }

   async run() {
      this.logger.info('run');
      while (!this.ended && !this.service.ended) {
         try {
            if (!this.service.ended) {
               await this.service.validate();
               await this.pop();
            }
         } catch (err) {
            this.service.error(this, err);
            break;
         }
      }
      this.ended = true;
      return this.redisClient.quitAsync();
   }

   async pop() {
      this.logger.debug('brpoplpush', this.props.in, this.props.pending, this.props.popTimeout);
      const message = await this.redisClient.brpoplpushAsync(this.props.in, this.props.pending, this.props.popTimeout);
      if (message) {
         this.logger.debug('lpush', message, this.props.out);
         if (this.components.messageRegister) {
            await this.components.messageRegister.registerMessage(message);
         }
         const multi = this.redisClient.multi();
         this.props.out.forEach(out => multi.lpush(out, message));
         multi.lrem(this.props.pending, -1, message);
         await multi.execAsync();
      }
   }
}
