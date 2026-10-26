import {Problem,hash,id,secret,uuid,passwordHash,passwordMatches,text,integer,address,validateTransition} from './security.mjs';
const staffRoles=['owner','manager','staff'];
const terminal=['completed','rejected','cancelled'];
export function createPlatform(db,options={}){
 const now=()=>new Date();
 async function rows(sql,args=[],client=db){return (await client.query(sql,args)).rows;}
 async function config(c=db){return (await rows('SELECT * FROM aw_settings WHERE id=1',[],c))[0];}
 async function audit(c,user,action,record,details={}){await c.query('INSERT INTO aw_audit(actor_id,action,record_id,details) VALUES($1,$2,$3,$4)',[user?.id??null,action,record,JSON.stringify(details)]);}
 async function revision(c){await c.query('UPDATE aw_settings SET revision=revision+1 WHERE id=1');}
 async function session(token){if(!token)return null;return (await rows('SELECT s.id,s.name,s.email,s.role FROM aw_staff s JOIN aw_sessions t ON t.staff_id=s.id WHERE t.token_hash=$1 AND t.expires_at>now() AND s.active=true',[hash(token)]))[0]??null;}
 function requireUser(user,roles=staffRoles){if(!user)throw new Problem('Please sign in to the staff website.',401);if(!roles.includes(user.role))throw new Problem('Your role cannot perform this action.',403);return user;}
 async function rate(key,limit=30){const value=(await rows(`INSERT INTO aw_rate_limits(key,hits,window_start) VALUES($1,1,now()) ON CONFLICT(key) DO UPDATE SET hits=CASE WHEN aw_rate_limits.window_start<now()-interval '1 minute' THEN 1 ELSE aw_rate_limits.hits+1 END,window_start=CASE WHEN aw_rate_limits.window_start<now()-interval '1 minute' THEN now() ELSE aw_rate_limits.window_start END RETURNING hits`,[hash(key)]))[0];if(value.hits>limit)throw new Problem('Too many requests. Please wait one minute.',429);}
 async function detail(orderId,c=db){const order=(await rows('SELECT * FROM aw_orders WHERE id=$1',[orderId],c))[0];if(!order)throw new Problem('Order not found.',404);delete order.access_hash;order.items=await rows('SELECT id,menu_id,name,unit_price,quantity,notes FROM aw_order_items WHERE order_id=$1 ORDER BY id',[orderId],c);order.history=await rows('SELECT status,reason,created_at FROM aw_order_history WHERE order_id=$1 ORDER BY id',[orderId],c);return order;}
 async function orders(query={}){
  const params=[],clauses=[];
  for(const [key,column]of [['table','table_id'],['status','status']])if(query[key]){params.push(query[key]);clauses.push(`${column}=$${params.length}`);}
  if(query.date){if(!/^\d{4}-\d{2}-\d{2}$/.test(query.date))throw new Problem('Invalid date.');params.push(query.date);clauses.push(`(created_at AT TIME ZONE 'Asia/Phnom_Penh')::date=$${params.length}::date`);}
  if(query.search){params.push('%'+String(query.search).slice(0,100)+'%');clauses.push(`(id ILIKE $${params.length} OR table_name ILIKE $${params.length})`);}
  const result=await rows(`SELECT id FROM aw_orders ${clauses.length?'WHERE '+clauses.join(' AND '):''} ORDER BY created_at DESC LIMIT 300`,params);
  return Promise.all(result.map(r=>detail(r.id)));
 }
 async function route(method,path,data={},query={},context={}){
  const user=await session(context.token);
  if(method!=='GET')await rate(`${context.ip??'local'}:${path.startsWith('/staff/auth')?path:path.split('/').slice(0,2).join('/')}`,path==='/staff/auth/login'?10:40);
  if(path==='/health')return {status:'ok',database:'connected'};
  if(path==='/settings'&&method==='GET'){const s=await config();return {address:'',phone:'',email:'',hours:{},venue_name:'After Work',website_url:s.customer_url,staff_url:s.staff_url,ordering_enabled:s.ordering_enabled,tax_basis_points:s.tax_basis_points,currency:'USD',payment_method:'pay_at_counter',timezone:'Asia/Phnom_Penh',demo:false};}
  if(path==='/menu'&&method==='GET')return {items:(await rows('SELECT m.*,c.name AS category,c.experience FROM aw_menu m JOIN aw_categories c ON c.id=m.category_id WHERE available=true ORDER BY m.name')).map(m=>({...m,vegetarian:m.vegetarian?1:0}))};
  if(path==='/tables'&&method==='GET'){const s=await config();return {tables:(await rows('SELECT * FROM aw_tables WHERE active=true ORDER BY id')).map(t=>({...t,active:1})),website_url:s.customer_url};}
  if(/^\/tables\/[^/]+$/.test(path)&&method==='GET'){const t=(await rows('SELECT * FROM aw_tables WHERE id=$1 AND active=true',[path.split('/')[2]]))[0];if(!t)throw new Problem('This table is not available. Please ask a staff member.',404);return t;}
  if(path==='/staff/setup'&&method==='POST'){
   const token=text(data,'setup_token',20,150),expected=options.setupHash??process.env.OWNER_SETUP_HASH;
   const expires=options.setupExpires??process.env.OWNER_SETUP_EXPIRES_AT;
   if(!expected||hash(token)!==expected||(expires&&Date.now()>Date.parse(expires)))throw new Problem('This setup link is invalid or expired.',403);
   const email=address(data.email),name=text(data,'name',2,100),password=text(data,'password',12,200),pwd=await passwordHash(password);
   await db.transaction(async(c)=>{await c.query('SELECT pg_advisory_xact_lock(71402628)');if((await rows('SELECT id FROM aw_staff LIMIT 1',[],c)).length)throw new Problem('The owner account has already been created.',409);const sid=uuid();await c.query("INSERT INTO aw_staff(id,email,name,password_hash,role) VALUES($1,$2,$3,$4,'owner')",[sid,email,name,pwd]);await audit(c,{id:sid},'owner.created',sid);});
   return {message:'Owner account created. Sign in to continue.'};
  }
  if(path==='/staff/auth/login'&&method==='POST'){
   const email=address(data.email),password=text(data,'password',1,200);
   await rate('login:'+hash(email)+':'+(context.ip??'local'),10);
   const u=(await rows('SELECT * FROM aw_staff WHERE email=$1 AND active=true',[email]))[0];
   if(!u||!await passwordMatches(password,u.password_hash))throw new Problem('Email or password is incorrect.',401);
   const token=secret();await db.query("INSERT INTO aw_sessions(token_hash,staff_id,expires_at) VALUES($1,$2,now()+interval '12 hours')",[hash(token),u.id]);
   return {token,user:{id:u.id,name:u.name,email:u.email,role:u.role},expires_in:43200};
  }
  if(path==='/staff/auth/logout'&&method==='POST'){requireUser(user);await db.query('DELETE FROM aw_sessions WHERE token_hash=$1',[hash(context.token)]);return {message:'Signed out.'};}
  if(path==='/orders/quote'&&method==='POST')return quote(data);
  if(path==='/orders'&&method==='POST'){
   const requestKey=text(data,'request_key',16,160),fingerprint=hash(JSON.stringify({table:data.table_id,items:data.items,notes:data.notes??'',name:data.name??'Guest'}));
   const token=text(data,'access_token',32,150); // Created by the customer before submission; the server stores only its hash.
   return db.transaction(async(c)=>{
    await c.query('SELECT pg_advisory_xact_lock(hashtext($1))',[requestKey]);
    const previous=(await rows('SELECT * FROM aw_idempotency WHERE key=$1',[requestKey],c))[0];
    if(previous){if(previous.fingerprint!==fingerprint)throw new Problem('This order key was already used with different details.',409);const p=(await rows('SELECT access_hash FROM aw_orders WHERE id=$1',[previous.order_id],c))[0];if(p.access_hash!==hash(token))throw new Problem('The order access token does not match.',403);return {order:await detail(previous.order_id,c),access_token:token,replayed:true};}
    const q=await quote(data,c,true);
    const oid=id('AW-'),name=text(data,'name',0,100)||'Guest',notes=text(data,'notes',0,1000);
    await c.query('INSERT INTO aw_orders(id,access_hash,table_id,table_name,name,notes,subtotal,tax,total) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9)',[oid,hash(token),q.table.id,q.table.name,name,notes,q.subtotal,q.tax,q.total]);
    for(const line of q.items)await c.query('INSERT INTO aw_order_items(id,order_id,menu_id,name,unit_price,quantity,notes) VALUES($1,$2,$3,$4,$5,$6,$7)',[uuid(),oid,line.id,line.name,line.unit_price,line.quantity,line.notes]);
    await c.query('INSERT INTO aw_idempotency VALUES($1,$2,$3)',[requestKey,fingerprint,oid]);
    await c.query("INSERT INTO aw_order_history(order_id,status) VALUES($1,'new')",[oid]);await audit(c,null,'order.created',oid);await revision(c);
    return {order:await detail(oid,c),access_token:token,replayed:false};
   });
  }
  if(/^\/orders\/[^/]+$/.test(path)&&method==='GET'){
   const oid=path.split('/')[2],access=context.orderToken??query.access_token??'';
   const stored=(await rows('SELECT access_hash FROM aw_orders WHERE id=$1',[oid]))[0];
   if(!stored||hash(String(access))!==stored.access_hash)throw new Problem('Order not found or access token is incorrect.',404);
   return {order:await detail(oid)};
  }
  if(path.startsWith('/staff')){
   requireUser(user);
   if(path==='/staff/me')return {user};
   if(path==='/staff/orders'&&method==='GET')return {orders:await orders(query),revision:(await config()).revision};
   if(/^\/staff\/orders\/[^/]+$/.test(path)&&method==='GET')return {order:await detail(path.split('/')[3])};
   if(/^\/staff\/orders\/[^/]+\/status$/.test(path)&&method==='PATCH'){
    const oid=path.split('/')[3],status=text(data,'status',1,30),reason=text(data,'reason',0,500);
    return db.transaction(async(c)=>{const order=(await rows('SELECT * FROM aw_orders WHERE id=$1 FOR UPDATE',[oid],c))[0];if(!order)throw new Problem('Order not found.',404);validateTransition(order.status,status,reason);await c.query('UPDATE aw_orders SET status=$1,updated_at=now() WHERE id=$2',[status,oid]);await c.query('INSERT INTO aw_order_history(order_id,status,actor_id,reason) VALUES($1,$2,$3,$4)',[oid,status,user.id,reason]);await audit(c,user,'order.'+status,oid,{reason});await revision(c);return {order:await detail(oid,c)};});
   }
   if(path==='/staff/tables'&&method==='GET')return {tables:await rows('SELECT * FROM aw_tables ORDER BY id'),settings:await config()};
   if(path==='/staff/menu'&&method==='GET')return {items:await rows('SELECT m.*,c.name AS category,c.experience FROM aw_menu m JOIN aw_categories c ON c.id=m.category_id ORDER BY m.name'),categories:await rows('SELECT * FROM aw_categories ORDER BY name')};
   requireUser(user,['owner','manager']);
   if(path==='/staff/menu'&&method==='PATCH'){
    const mid=text(data,'id',1,100),price=integer(data.price,0,1000000,'Price'),name=text(data,'name',2,150),description=text(data,'description',1,2000),allergens=text(data,'allergens',0,300);
    if(typeof data.available!=='boolean')throw new Problem('Availability must be true or false.');
    await db.transaction(async(c)=>{const r=await c.query('UPDATE aw_menu SET name=$1,price=$2,description=$3,allergens=$4,available=$5,updated_at=now() WHERE id=$6 RETURNING id',[name,price,description,allergens,data.available,mid]);if(!r.rows.length)throw new Problem('Menu item not found.',404);await audit(c,user,'menu.updated',mid);await revision(c);});return {message:'Menu updated.'};
   }
   if(path==='/staff/tables'&&['POST','PATCH'].includes(method)){
    const tid=text(data,'id',1,40),name=text(data,'name',1,80),seats=integer(data.seats,1,30,'Seats'),area=text(data,'area',1,60);
    if(!/^[A-Za-z0-9_-]+$/.test(tid))throw new Problem('Use letters, numbers, underscores or hyphens for the table ID.');
    if(typeof data.active!=='boolean')throw new Problem('Active must be true or false.');
    await db.transaction(async(c)=>{if(method==='POST')await c.query('INSERT INTO aw_tables(id,name,seats,area,active) VALUES($1,$2,$3,$4,$5)',[tid,name,seats,area,data.active]);else{const r=await c.query('UPDATE aw_tables SET name=$2,seats=$3,area=$4,active=$5,updated_at=now() WHERE id=$1 RETURNING id',[tid,name,seats,area,data.active]);if(!r.rows.length)throw new Problem('Table not found.',404);}await audit(c,user,'table.updated',tid);await revision(c);});return {message:'Table saved.'};
   }
   if(path==='/staff/settings'&&method==='GET')return {settings:await config()};
   if(path==='/staff/settings'&&method==='PATCH'){
    if(typeof data.ordering_enabled!=='boolean')throw new Problem('Set ordering enabled to true or false.');const tax=integer(data.tax_basis_points,0,10000,'Tax basis points');
    const customer=text(data,'customer_url',1,300),staff=text(data,'staff_url',0,300);
    for(const url of [customer,staff].filter(Boolean)){const parsed=new URL(url);if(!['https:','http:'].includes(parsed.protocol)||parsed.username||parsed.password||parsed.hash||parsed.search)throw new Problem('Enter a valid website origin without credentials or query parameters.');if(options.production&&parsed.protocol!=='https:')throw new Problem('Production websites must use HTTPS.');}
    await db.transaction(async(c)=>{await c.query('UPDATE aw_settings SET ordering_enabled=$1,tax_basis_points=$2,customer_url=$3,staff_url=$4,revision=revision+1 WHERE id=1',[data.ordering_enabled,tax,customer.replace(/\/$/,''),staff.replace(/\/$/,'')]);await audit(c,user,'settings.updated','venue');});return {message:'Settings saved.'};
   }
   if(path==='/staff/audit'&&method==='GET')return {audit:await rows('SELECT a.*,s.name AS actor FROM aw_audit a LEFT JOIN aw_staff s ON s.id=a.actor_id ORDER BY a.id DESC LIMIT 200')};
   if(path==='/staff/users'&&method==='GET')return {users:await rows('SELECT id,name,email,role,active FROM aw_staff ORDER BY created_at')};
   if(path==='/staff/users'&&['POST','PATCH'].includes(method)){
    requireUser(user,['owner']);const role=text(data,'role',1,20);if(!['manager','staff'].includes(role))throw new Problem('New or edited accounts must be manager or staff.');
    const name=text(data,'name',2,100),email=address(data.email);
    await db.transaction(async(c)=>{if(method==='POST'){const pwd=await passwordHash(text(data,'password',12,200)),sid=uuid();await c.query('INSERT INTO aw_staff(id,email,name,password_hash,role) VALUES($1,$2,$3,$4,$5)',[sid,email,name,pwd,role]);await audit(c,user,'staff.created',sid);}else{const sid=text(data,'id',1,100);const existing=(await rows('SELECT role FROM aw_staff WHERE id=$1 FOR UPDATE',[sid],c))[0];if(!existing)throw new Problem('Staff member not found.',404);if(existing.role==='owner')throw new Problem('The owner cannot be changed here.',403);if(typeof data.active!=='boolean')throw new Problem('Set active to true or false.');await c.query('UPDATE aw_staff SET name=$2,email=$3,role=$4,active=$5 WHERE id=$1',[sid,name,email,role,data.active]);await c.query('DELETE FROM aw_sessions WHERE staff_id=$1',[sid]);await audit(c,user,'staff.updated',sid);}});return {message:'Staff account saved.'};
   }
  }
  throw new Problem('This endpoint is not available.',404);
 }
 async function quote(data,c=db,lock=false){
  const settings=(await rows('SELECT * FROM aw_settings WHERE id=1'+(lock?' FOR SHARE':''),[],c))[0];if(!settings.ordering_enabled)throw new Problem('The kitchen is not accepting orders right now.',409);
  const table=(await rows('SELECT id,name FROM aw_tables WHERE id=$1 AND active=true'+(lock?' FOR SHARE':''),[text(data,'table_id',1,40)],c))[0];if(!table)throw new Problem('Please scan an active table QR code.',409);
  if(!Array.isArray(data.items)||data.items.length<1||data.items.length>30)throw new Problem('Select between 1 and 30 dishes.');
  const lines=[];let subtotal=0;
  for(const item of data.items){const qty=integer(item.quantity,1,20),notes=text(item,'notes',0,300),mid=text(item,'id',1,100);const product=(await rows('SELECT id,name,price FROM aw_menu WHERE id=$1 AND available=true'+(lock?' FOR SHARE':''),[mid],c))[0];if(!product)throw new Problem('A dish is no longer available. Refresh your menu.',409);if(lock&&item.unit_price!==product.price)throw new Problem('A price changed. Review the updated total before ordering.',409);lines.push({id:mid,name:product.name,quantity:qty,unit_price:product.price,notes});subtotal+=qty*product.price;}
  const tax=Math.round(subtotal*settings.tax_basis_points/10000);return {table,items:lines,subtotal,tax,total:subtotal+tax,payment_status:'unpaid',payment_method:'pay_at_counter',currency:'USD'};
 }
 return {route,session,config,orders,rate};
}
