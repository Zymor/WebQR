import {cpSync,existsSync,mkdirSync,renameSync,writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {verifyWeb} from './verify_web.mjs';
const web=verifyWeb('build/web');
const output=resolve('.vercel/output');
// Retain prior packaging as a sibling snapshot, never merge new files into it.
if (existsSync(output)) renameSync(output,`${output}.previous-${Date.now()}`);
mkdirSync(output,{recursive:true});
cpSync(web,`${output}/static`,{recursive:true,filter:(path)=>!resolve(path).startsWith(resolve(web,'qr-codes'))});
writeFileSync(`${output}/config.json`,JSON.stringify({version:3},null,2));
verifyWeb(`${output}/static`);
console.log('Ready for vercel deploy --prebuilt. Only build/web was packaged.');
