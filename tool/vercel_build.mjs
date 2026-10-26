import {spawnSync} from 'node:child_process';
import {existsSync, mkdtempSync} from 'node:fs';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {verifyWeb} from './verify_web.mjs';
const version = '3.47.6';
function run(binary,args,options={}) {
  const result=spawnSync(binary,args,{stdio:'inherit',...options});
  if (result.error) throw result.error;
  if (result.status!==0) throw new Error(`${binary} exited with ${result.status}`);
}
let flutter=process.env.FLUTTER_BIN || (process.platform==='win32'?'flutter.bat':'flutter');
if (spawnSync(flutter,['--version'],{stdio:'ignore',shell:process.platform==='win32'}).status!==0) {
  const folder=join(mkdtempSync(join(tmpdir(),'afterwork-sdk-')),'flutter');
  run('git',['clone','--depth','1','--branch',version,'https://github.com/flutter/flutter.git',folder]);
  flutter=join(folder,'bin','flutter');
}
const api=process.env.SOCIAL_API || '/api';
if (process.env.VERCEL && (/^http:\/\//i.test(api) || /(?:localhost|127\.0\.0\.1|192\.168\.)/i.test(api))) throw new Error('Set SOCIAL_API to a public HTTPS API URL; local addresses cannot serve public visitors.');
run(flutter,['pub','get'],{shell:process.platform==='win32'});
run(flutter,['build','web','--release','--base-href','/',`--dart-define=SOCIAL_API=${api}`],{shell:process.platform==='win32'});
verifyWeb('build/web');
