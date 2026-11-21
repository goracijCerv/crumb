// Descarga una copia aislada de VS Code (en .vscode-test) y ejecuta las pruebas dentro de ella.
// Uso: npm test            (todas las shells)
//      CRUMB_E2E_SHELLS=bash npm test
const path = require('path');
const fs = require('fs');
const os = require('os');
const { runTests } = require('@vscode/test-electron');

async function main() {
  const userDataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'crumb-vscode-user-'));
  try {
    await runTests({
      version: process.env.CRUMB_VSCODE_VERSION || 'stable',
      extensionDevelopmentPath: __dirname,
      extensionTestsPath: path.join(__dirname, 'suite', 'index.js'),
      launchArgs: [
        '--disable-extensions',
        '--disable-workspace-trust',
        '--skip-welcome',
        '--skip-release-notes',
        `--user-data-dir=${userDataDir}`,
      ],
    });
  } catch (err) {
    console.error('Las pruebas fallaron:', err);
    process.exit(1);
  }
}

main();
