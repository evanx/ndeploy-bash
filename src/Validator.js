

export default class Validator {

   constuctor(meta) {
      assert(meta && Object.keys(meta).length, 'meta');
      this.meta = meta;
   }

   validate(name, value) {
      const meta = this.meta[name];
      if (meta) {
      }
      return value;
   }

   validateInteger(name, value) {
      var meta = this.meta[name];
      if (meta) {
      }
      return value;
   }

   validateIntegerMin(name, value, limit) {
      if (!Number.isInteger(value)) {
         return {message: "not integer", name, value};
      } else if (value < limit) {
         return {message: "less than", name, value, limit};
      }
      return value;
   }
}
