// Prueba del prototipo dentro de la terminal integrada de VS Code.
// Variantes de carga (MODE):
// - auto:           VS Code inyecta su integración de shell por sí mismo, como al abrir una terminal normal.
//                   crumb se carga desde un perfil aislado: HOME temporal con .bashrc (bash) o el profile.ps1
//                   de la copia portable de PowerShell 7 (solo actúa si CRUMB_E2E_PROTO está definida).
// - crumb-primero:  crumb y luego la integración de VS Code cargada a mano (mismo orden que un perfil real).
// - vscode-primero: la integración de VS Code y luego crumb (por ejemplo, si alguien carga crumb a mano).
// Las teclas se envían a la PTY igual que las mandaría el teclado (texto, flecha arriba = ESC [ A, Ctrl+C = \x03).
// La pantalla se lee con "seleccionar todo" + "copiar" de la terminal.
// El historial global apunta a un archivo temporal: no toca tu historial real.
const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const vscode = require('vscode');

const PROTO_DIR = path.resolve(__dirname, '..', '..', '..').replace(/\\/g, '/');
const SI_DIR = path.join(vscode.env.appRoot, 'out', 'vs', 'workbench', 'contrib', 'terminal', 'common', 'scripts').replace(/\\/g, '/');
const PWSH7 = process.env.CRUMB_PWSH7 || path.join(process.env.LOCALAPPDATA || '', 'crumb-dev', 'pwsh7', 'pwsh.exe');
const BASH = process.env.CRUMB_BASH || 'C:\\Program Files\\Git\\bin\\bash.exe';

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// Perfil de la copia portable de PowerShell 7. No afecta a ninguna otra instalación.
const PWSH7_PROFILE = [
  '# Creado por las pruebas de crumb. Solo actua dentro de esas pruebas.',
  'if ($env:CRUMB_E2E_PROTO) {',
  '    Set-PSReadLineOption -HistorySavePath $env:CRUMB_E2E_GLOBAL',
  '    . $env:CRUMB_E2E_PROTO',
  '}',
  '',
].join('\r\n');

function shellConfig(shell, mode, T) {
  const g = `${T}/global-history.txt`;
  const si = shell === 'bash' ? `${SI_DIR}/shellIntegration-bash.sh` : `${SI_DIR}/shellIntegration.ps1`;

  if (shell === 'bash') {
    const proto = `source '${PROTO_DIR}/crumb-proto.sh'`;
    if (mode === 'auto') {
      fs.mkdirSync(`${T}/home`, { recursive: true });
      fs.writeFileSync(`${T}/home/.bashrc`, `HISTFILE='${g}'\n${proto}\n`);
      return { shellPath: BASH, env: { HOME: `${T}/home` } };
    }
    const lines = mode === 'crumb-primero' ? [proto, `source '${si}'`] : [`source '${si}'`, proto];
    fs.writeFileSync(`${T}/rc.sh`, [`HISTFILE='${g}'`, ...lines, ''].join('\n'));
    return { shellPath: BASH, shellArgs: ['--rcfile', `${T}/rc.sh`, '-i'] };
  }

  const exe = shell === 'pwsh' ? PWSH7 : 'powershell.exe';
  if (mode === 'auto') {
    const profile = path.join(path.dirname(PWSH7), 'profile.ps1');
    if (!fs.existsSync(profile) || fs.readFileSync(profile, 'utf8') !== PWSH7_PROFILE) fs.writeFileSync(profile, PWSH7_PROFILE);
    return { shellPath: exe, env: { CRUMB_E2E_PROTO: `${PROTO_DIR}/crumb-proto.ps1`, CRUMB_E2E_GLOBAL: g } };
  }
  const proto = `. '${PROTO_DIR}/crumb-proto.ps1'`;
  const vsc = `. '${si}'`;
  const init = [
    `Set-PSReadLineOption -HistorySavePath '${g}'`,
    'Set-ExecutionPolicy -Scope Process Bypass -Force',
    ...(mode === 'crumb-primero' ? [proto, vsc] : [vsc, proto]),
  ].join('; ');
  return { shellPath: exe, shellArgs: ['-NoProfile', '-NoLogo', '-NoExit', '-Command', init] };
}
async function screen() {
  await vscode.commands.executeCommand('workbench.action.terminal.selectAll');
  await vscode.commands.executeCommand('workbench.action.terminal.copySelection');
  await vscode.commands.executeCommand('workbench.action.terminal.clearSelection');
  return vscode.env.clipboard.readText();
}

async function waitFor(pred, what, ms = 8000) {
  const end = Date.now() + ms;
  let s = '';
  while (Date.now() < end) {
    s = await screen();
    if (pred(s)) return s;
    await sleep(300);
  }
  throw new Error(`No apareció: ${what}\n--- pantalla ---\n${s}`);
}

async function expectAbsent(text, ms = 1200) {
  await sleep(ms);
  const s = await screen();
  assert.ok(!s.includes(text), `No debería aparecer "${text}"\n--- pantalla ---\n${s}`);
}

function waitShellIntegration(term, ms = 20000) {
  if (term.shellIntegration) return Promise.resolve(true);
  return new Promise((resolve) => {
    const sub = vscode.window.onDidChangeTerminalShellIntegration((e) => {
      if (e.terminal === term) { sub.dispose(); resolve(true); }
    });
    setTimeout(() => { sub.dispose(); resolve(!!term.shellIntegration); }, ms);
  });
}

const shells = (process.env.CRUMB_E2E_SHELLS || 'powershell,pwsh,bash').split(',').map((s) => s.trim()).filter(Boolean);
const modes = (process.env.CRUMB_E2E_MODES || 'auto,crumb-primero,vscode-primero').split(',').map((s) => s.trim()).filter(Boolean);
const variants = [];
for (const shell of shells) for (const mode of modes) {
  // Windows PowerShell 5.1: su perfil global vive en System32, así que no hay forma aislada de probar 'auto'.
  if (!(shell === 'powershell' && mode === 'auto')) variants.push({ shell, mode });
}

for (const { shell, mode } of variants) {
  describe(`VS Code + ${shell} (${mode})`, function () {
    let term;
    let T;

    before(function () {
      if (shell === 'pwsh' && !fs.existsSync(PWSH7)) this.skip();
      if (shell === 'bash' && !fs.existsSync(BASH)) this.skip();
    });

    after(() => term && term.dispose());

    it('cambia el historial por proyecto dentro de la terminal integrada', async () => {
      T = fs.mkdtempSync(path.join(os.tmpdir(), `crumb-vsc-${shell}-${mode}-`)).replace(/\\/g, '/');
      for (const d of ['demo/proyecto/.git', 'demo/proyecto/sub', 'demo/otra/.git', 'crumb']) {
        fs.mkdirSync(path.join(T, d), { recursive: true });
      }
      const send = async (text) => { term.sendText(text, true); await sleep(600); };
      const keys = async (seq, n = 1) => { for (let i = 0; i < n; i++) { term.sendText(seq, false); await sleep(300); } };
      const UP = '\x1b[A';
      const CTRL_C = '\x03';
      const clear = async () => { await vscode.commands.executeCommand('workbench.action.terminal.clear'); await sleep(300); };

      const cfg = shellConfig(shell, mode, T);
      term = vscode.window.createTerminal({
        name: `crumb-${shell}-${mode}`,
        cwd: `${T}/demo`,
        shellPath: cfg.shellPath,
        shellArgs: cfg.shellArgs,
        env: { CRUMB_HOME: `${T}/crumb`, CRUMB_ANSWER: '', ...(cfg.env || {}) },
      });
      term.show(false);

      // La integración de VS Code se activa aunque crumb haya envuelto el prompt.
      assert.ok(await waitShellIntegration(term), 'La integración de shell de VS Code no se activó');
      await sleep(1000);

      // 1. Fuera de un proyecto no pregunta.
      await expectAbsent('Primera vez');

      // 2. En un proyecto pregunta con 3 opciones.
      await send('cd proyecto');
      await waitFor((s) => s.includes('3) por proyecto'), 'pregunta con opción 3');
      await send('3');
      await send('echo uno');

      // 3. Subcarpeta: no repregunta, flecha arriba trae el historial del proyecto.
      await send('cd sub');
      await clear();
      await keys(UP, 2); // cd sub, echo uno
      await waitFor((s) => s.includes('echo uno'), 'echo uno con flecha arriba');
      await expectAbsent('Primera vez', 300);
      await keys(CTRL_C);

      // 4. Otro proyecto en modo carpeta: historial propio.
      await send('cd ../../otra');
      await waitFor((s) => s.includes('Primera vez'), 'pregunta en otra');
      await send('2');
      await clear();
      await keys(UP, 3);
      await expectAbsent('echo uno');
      await keys(CTRL_C);

      // 5. Volver al proyecto: no pregunta y recupera su historial.
      await send('cd ../proyecto');
      await clear();
      await keys(UP, 3); // cd ../../otra, cd sub, echo uno
      await waitFor((s) => s.includes('echo uno'), 'echo uno al volver');
      await expectAbsent('Primera vez', 300);
      await keys(CTRL_C);

      // 6. Comando con espacio inicial no se guarda.
      await send(' echo secreto');
      await clear();
      await keys(UP, 1);
      await expectAbsent('secreto');
      await keys(CTRL_C);

      // 7. La detección de comandos de VS Code sigue funcionando con crumb.
      const ended = new Promise((resolve) => {
        const sub = vscode.window.onDidEndTerminalShellExecution((e) => {
          if (e.terminal === term) { sub.dispose(); resolve(e.exitCode); }
        });
        setTimeout(() => { sub.dispose(); resolve('timeout'); }, 10000);
      });
      term.shellIntegration.executeCommand('echo integracion-ok');
      const code = await ended;
      assert.notStrictEqual(code, 'timeout', 'VS Code no detectó el fin del comando');

      // 8. Archivos: el del proyecto tiene "echo uno" y ninguno tiene "secreto".
      await sleep(500);
      const histDir = path.join(T, 'crumb', 'histories');
      const files = fs.readdirSync(histDir).map((f) => path.join(histDir, f));
      const proj = files.find((f) => path.basename(f).startsWith('proyecto-'));
      assert.ok(proj && fs.readFileSync(proj, 'utf8').includes('echo uno'), 'El archivo del proyecto no tiene "echo uno"');
      const all = files.concat([path.join(T, 'global-history.txt')]).filter((f) => fs.existsSync(f));
      for (const f of all) assert.ok(!fs.readFileSync(f, 'utf8').includes('secreto'), `Se guardó un secreto en ${f}`);
    });
  });
}
