const path = require('path');

module.exports = {
  entry: './src/index.js',
  resolve: {
    extensions: ['.js'],
  },
  target: 'node',
  output: {
    filename: 'bundle.js',
    path: path.resolve(__dirname, 'dist'),
  },
};
