
  NODE_ENV=development redis='redis://localhost:6379' nodemon -e js index.js $@ | node_modules/.bin/bunyan -o short

