import {database} from '../backend/db.mjs';
import {passwordHash,secret,uuid} from '../backend/security.mjs';
const db=database();const password=secret().slice(0,22);const staffId=uuid();let email;
await db.transaction(async c=>{
 await c.query('SELECT pg_advisory_xact_lock(71402629)');
 for(let n=1;n<=20;n++){const candidate=n===1?'admin@afterwork.invalid':`admin${n}@afterwork.invalid`;const exists=await c.query('SELECT id FROM aw_staff WHERE email=$1',[candidate]);if(!exists.rows.length){email=candidate;break;}}
 if(!email)throw new Error('No unused internal admin login is available.');
 await c.query("INSERT INTO aw_staff(id,email,name,password_hash,role) VALUES($1,$2,$3,$4,'owner')",[staffId,email,'Admin',await passwordHash(password)]);
 await c.query('INSERT INTO aw_audit(actor_id,action,record_id,details) VALUES($1,$2,$3,$4)',[null,'staff.created_via_workspace',staffId,JSON.stringify({role:'owner',reason:'User requested a new admin-only account'})]);
});
try{
 const response=await fetch('https://afterwork-livid.vercel.app/api/staff/auth/login',{method:'POST',headers:{'Content-Type':'application/json','Origin':'https://afterwork-admin.vercel.app'},body:JSON.stringify({email,password})});
 const result=await response.json();if(response.status!==200||result.user.id!==staffId)throw new Error('Account saved but login verification failed.');
 const logout=await fetch('https://afterwork-livid.vercel.app/api/staff/auth/logout',{method:'POST',headers:{'Content-Type':'application/json','Authorization':'Bearer '+result.token},body:'{}'});if(logout.status!==200)throw new Error('Verification session could not be closed.');
 console.log(JSON.stringify({created:true,name:'Admin',email,password,role:'owner',login_verified:true}));
}finally{process.exitCode=process.exitCode??0;setTimeout(()=>process.exit(process.exitCode),100);}
