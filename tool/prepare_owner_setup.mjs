import {randomBytes,createHash} from 'node:crypto';import {writeFileSync,readFileSync} from 'node:fs';import {spawnSync} from 'node:child_process';
const origin=process.argv[2];if(!origin||!origin.startsWith('https://'))throw new Error('Usage: node tool/prepare_owner_setup.mjs https://your-staff-site.vercel.app');
const token=randomBytes(32).toString('base64url'),digest=createHash('sha256').update(token).digest('hex'),expires=new Date(Date.now()+8*3600000).toISOString();
for(const [key,value]of [['OWNER_SETUP_HASH',digest],['OWNER_SETUP_EXPIRES_AT',expires],['STAFF_ORIGIN',new URL(origin).origin]]){
 const run=spawnSync(process.platform==='win32'?'npx.cmd':'npx',['--yes','vercel','env','add',key,'production','--force','--scope','starling-gg'],{input:value,encoding:'utf8',shell:process.platform==='win32'});
 if(run.status!==0)throw new Error('Could not configure '+key+'. '+run.stderr);
 console.log('Configured '+key+' (value hidden)');
}
const link=`${origin.replace(/\/$/,'')}/#/setup?token=${token}`;
writeFileSync('.env.owner-setup.local',`# PRIVATE. Expires ${expires}. Never commit or publish.\nOWNER_SETUP_URL=${JSON.stringify(link)}\n`,{mode:0o600});
console.log('Private owner setup URL saved to .env.owner-setup.local. Redeploy the API before using it.');
