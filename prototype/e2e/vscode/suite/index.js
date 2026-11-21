const path = require('path');
const Mocha = require('mocha');

exports.run = () => {
  const mocha = new Mocha({ ui: 'bdd', timeout: 120000, color: false });
  mocha.addFile(path.join(__dirname, 'terminal.test.js'));
  return new Promise((resolve, reject) => {
    mocha.run((failures) => (failures ? reject(new Error(`${failures} prueba(s) fallaron`)) : resolve()));
  });
};
