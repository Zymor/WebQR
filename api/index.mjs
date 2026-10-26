import {database} from '../backend/db.mjs';
import {initialize} from '../backend/schema.mjs';
import {httpHandler} from '../backend/http.mjs';
let ready,handler;
export const config={maxDuration:60};
export default async function(req,res){
 try{
  const db=database();
  if(!ready)ready=initialize(db).catch(e=>{ready=null;throw e;});
  await ready;
  handler??=httpHandler(db,{production:true});
  await handler(req,res);
 }catch(e){res.statusCode=503;res.setHeader('Content-Type','application/json');res.setHeader('Cache-Control','no-store');res.end(JSON.stringify({error:'Ordering database is not configured or is temporarily unavailable.'}));console.error('Database initialization unavailable',e.code??e.name);}
}
