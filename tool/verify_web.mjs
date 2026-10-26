import {existsSync, readdirSync, readFileSync, statSync} from 'node:fs';
import {resolve, join} from 'node:path';

export function verifyWeb(directory) {
  const root = resolve(directory);
  for (const file of ['index.html', 'flutter_bootstrap.js', 'main.dart.js', 'assets/FontManifest.json']) {
    if (!existsSync(join(root,file))) throw new Error(`Missing compiled web artifact: ${file}. Run flutter build web; do not publish the source directory.`);
  }
  if (readFileSync(join(root,'index.html'),'utf8').includes('$FLUTTER_BASE_HREF')) throw new Error('index.html is an uncompiled Flutter template.');
  const forbidden = /^(?:\.git|\.dart_tool|\.env.*|server|lib|android|ios|windows|linux|macos|pubspec\.yaml|.*\.sqlite3(?:-.*)?|.*\.pyc)$/i;
  function walk(folder) {
    for (const entry of readdirSync(folder)) {
      if (forbidden.test(entry)) throw new Error(`Unsafe deployment file: ${join(folder, entry)}`);
      if (statSync(join(folder, entry)).isDirectory()) walk(join(folder,entry));
    }
  }
  walk(root);
  console.log(`Verified compiled website: ${root}`);
  return root;
}
if (process.argv[1] && resolve(process.argv[1]) === resolve(import.meta.filename)) verifyWeb(process.argv[2] || 'build/web');
