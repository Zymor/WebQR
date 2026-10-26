import {readFileSync} from 'node:fs';
const text=readFileSync('.env.owner-setup.local','utf8');const line=text.match(/^OWNER_SETUP_URL=(.+)$/m)[1].trim();const link=line.startsWith('"')?JSON.parse(line):line;
const token=new URLSearchParams(new URL(link).hash.split('?')[1]).get('token');
const response=await fetch('https://afterwork-livid.vercel.app/api/staff/setup',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({setup_token:token,email:'invalid',name:'',password:''})});
console.log('Owner setup authorization valid:',response.status===400);console.log('No account created; form validation was deliberately stopped.');
