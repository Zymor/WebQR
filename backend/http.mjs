import {createPlatform} from './platform.mjs';
import {Problem} from './security.mjs';
export function httpHandler(db,options={}){
 const app=createPlatform(db,options);
 return async(req,res)=>{
  const url=new URL(req.url,'http://internal');
  let path=url.pathname.replace(/^\/api(?=\/|$)/,'')||'/';
  if(path==='/index'){const captured=url.searchParams.get('path')??req.query?.path;if(captured)path='/'+(Array.isArray(captured)?captured.join('/'):String(captured)).replace(/^\//,'');}
  const origin=req.headers.origin;
  const context={token:(req.headers.authorization??'').replace(/^Bearer /,''),orderToken:req.headers['x-order-token'],ip:String(req.headers['x-real-ip']??req.socket?.remoteAddress??'local')};
  function json(value,status=200){if(res.writableEnded)return;res.statusCode=status;res.setHeader('Content-Type','application/json; charset=utf-8');res.setHeader('Cache-Control','no-store');res.setHeader('X-Content-Type-Options','nosniff');res.end(JSON.stringify(value));}
  try{
   if(origin){
    const settings=await app.config();
    const allowed=[settings.customer_url,settings.staff_url,process.env.STAFF_ORIGIN,process.env.CUSTOMER_ORIGIN].filter(Boolean).map(s=>{try{return new URL(s).origin;}catch{return '';}});
    const local=!options.production&&/^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(origin);
    if(!allowed.includes(origin)&&!local)throw new Problem('This website origin is not allowed to access the API.',403);
    res.setHeader('Access-Control-Allow-Origin',origin);res.setHeader('Vary','Origin');
   }
   if(req.method==='OPTIONS'){res.setHeader('Access-Control-Allow-Headers','Content-Type, Authorization, X-Order-Token');res.setHeader('Access-Control-Allow-Methods','GET,POST,PATCH,OPTIONS');res.statusCode=204;res.end();return;}
   if(/^\/media\/[A-Za-z0-9-]+$/.test(path)&&req.method==='GET'){
    const media=(await db.query('SELECT mime,data FROM aw_media WHERE id=$1',[path.split('/')[2]])).rows[0];
    if(!media)throw new Problem('Photo not found.',404);
    res.statusCode=200;res.setHeader('Content-Type',media.mime);res.setHeader('Vary','Origin');res.setHeader('X-Content-Type-Options','nosniff');res.setHeader('Cache-Control','public, max-age=31536000, immutable');res.end(Buffer.from(media.data));return;
   }
   if(path==='/staff/stream'&&req.method==='GET'){
    await app.route('GET','/staff/me',{}, {},context);
    res.statusCode=200;res.setHeader('Content-Type','text/event-stream');res.setHeader('Cache-Control','no-cache, no-transform');res.setHeader('X-Accel-Buffering','no');res.flushHeaders?.();
    let closed=false,last=null;res.on('close',()=>{closed=true;});
    const started=Date.now();
    while(!closed&&Date.now()-started<(options.streamMs??45000)){
     if(!await app.session(context.token)){res.write('event: expired\ndata: {}\n\n');break;}
     const revision=(await app.config()).revision;
     if(String(revision)!==String(last)){const snapshot=await app.route('GET','/staff/orders',{}, {},context);res.write(`id: ${snapshot.revision}\ndata: ${JSON.stringify(snapshot)}\n\n`);last=snapshot.revision;}
     else res.write(': heartbeat\n\n');
     await new Promise(resolve=>setTimeout(resolve,options.streamInterval??2000));
    }
    res.end();return;
   }
   let data=req.body;
   const maxBody=path==='/staff/media'?2900000:32768;
   if(data===undefined){let raw='';for await(const chunk of req){raw+=chunk;if(Buffer.byteLength(raw)>maxBody)throw new Problem('Request is too large.',413);}data=raw?JSON.parse(raw):{};}
   if(Buffer.byteLength(typeof data==='string'?data:JSON.stringify(data??{}))>maxBody)throw new Problem('Request is too large.',413);
   if(typeof data==='string')data=JSON.parse(data);
   if(!data||typeof data!=='object'||Array.isArray(data))throw new Problem('Expected a JSON object.');
   json(await app.route(req.method,path,data,Object.fromEntries(url.searchParams),context));
  }catch(e){
   if(res.headersSent){res.end();return;}
   if(e.code==='23505')json({error:'This table, email address or request already exists.'},409);
   else if(e instanceof SyntaxError)json({error:'Invalid JSON.'},400);
   else if(e.status)json({error:e.message},e.status);
   else{console.error('Ordering service error',e.code??e.name);json({error:'The ordering service is temporarily unavailable. Please retry; saved orders remain in the database.'},503);}
  }
 };
}
