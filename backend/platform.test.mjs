import test,{before,after} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,rm} from 'node:fs/promises';import {tmpdir} from 'node:os';import {join} from 'node:path';import {createServer} from 'node:http';
import {PGlite} from '@electric-sql/pglite';
import {initialize} from './schema.mjs';import {createPlatform} from './platform.mjs';import {httpHandler} from './http.mjs';import {hash,secret} from './security.mjs';
let pg,db,app,owner,staff,folder;
const setup='local-integration-test-owner-key-12345';
const ctx=(token)=>({token,ip:secret()});
const body=(extra={})=>({table_id:'T03',expected_total:4050,items:[{id:'chicken',quantity:2,unit_price:1800,notes:'No spicy seasoning'},{id:'coffee',quantity:1,unit_price:450,notes:'No sugar'}],request_key:secret(),access_token:secret(),notes:'Bring water please',name:'Guest',...extra});
before(async()=>{
 folder=await mkdtemp(join(tmpdir(),'afterwork-pg-'));pg=new PGlite(folder);db={query:(...a)=>pg.query(...a),transaction:fn=>pg.transaction(fn)};await initialize(db);app=createPlatform(db,{setupHash:hash(setup)});
 await app.route('POST','/staff/setup',{setup_token:setup,name:'Owner',email:'owner@example.com',password:'a-long-owner-test-password'},{},ctx());
 owner=(await app.route('POST','/staff/auth/login',{email:'owner@example.com',password:'a-long-owner-test-password'},{},ctx())).token;
 await app.route('POST','/staff/users',{name:'Kitchen Staff',email:'staff@example.com',password:'a-long-staff-test-password',role:'staff'},{},ctx(owner));
 staff=(await app.route('POST','/staff/auth/login',{email:'staff@example.com',password:'a-long-staff-test-password'},{},ctx())).token;
});
after(async()=>{await pg.close();await rm(folder,{recursive:true,force:true});});
test('QR table is validated and five table records exist',async()=>{const tables=await app.route('GET','/tables');assert.equal(tables.tables.length,5);assert.equal((await app.route('GET','/tables/T03')).name,'Table 03');await assert.rejects(app.route('GET','/tables/T99'),{status:404});});
test('guest order preserves table, dish quantities, notes, prices and unpaid status',async()=>{const b=body();const saved=await app.route('POST','/orders',b,{},ctx());assert.equal(saved.order.table_id,'T03');assert.equal(saved.order.table_name,'Table 03');assert.equal(saved.order.total,4050);assert.equal(saved.order.payment_status,'unpaid');assert.equal(saved.order.status,'new');assert.equal(saved.order.items.length,2);assert.equal(saved.order.items.find(i=>i.menu_id==='chicken').quantity,2);assert.equal(saved.order.notes,b.notes);const queue=await app.route('GET','/staff/orders',{}, {},ctx(staff));assert(queue.orders.some(o=>o.id===saved.order.id));});
test('simultaneous retries save only one order and return the same reference',async()=>{const b=body();const values=await Promise.all([app.route('POST','/orders',b,{},ctx()),app.route('POST','/orders',b,{},ctx())]);assert.equal(values[0].order.id,values[1].order.id);assert.equal((await db.query('SELECT count(*)::int n FROM aw_idempotency WHERE key=$1',[b.request_key])).rows[0].n,1);await assert.rejects(app.route('POST','/orders',{...b,notes:'Different content'}, {},ctx()),{status:409});});
test('guest cannot read another order or the staff order list',async()=>{const b=body();const saved=await app.route('POST','/orders',b,{},ctx());await assert.rejects(app.route('GET','/orders/'+saved.order.id,{}, {},{orderToken:secret()}),{status:404});await assert.rejects(app.route('GET','/staff/orders'),{status:401});assert.equal((await app.route('GET','/orders/'+saved.order.id,{}, {},{orderToken:b.access_token})).order.id,saved.order.id);});
test('staff workflow reaches served/completed and is visible to customer',async()=>{const b=body(),saved=await app.route('POST','/orders',b,{},ctx());await assert.rejects(app.route('PATCH',`/staff/orders/${saved.order.id}/status`,{status:'completed'},{},ctx(staff)),{status:409});for(const status of ['accepted','preparing','ready','served','completed'])await app.route('PATCH',`/staff/orders/${saved.order.id}/status`,{status},{},ctx(staff));const fetched=await app.route('GET','/orders/'+saved.order.id,{}, {},{orderToken:b.access_token});assert.equal(fetched.order.status,'completed');assert.equal(fetched.order.history.length,6);assert.equal(fetched.order.payment_status,'unpaid');});
test('rejection requires a reason, and the reason is retained',async()=>{const saved=await app.route('POST','/orders',body(),{},ctx());await assert.rejects(app.route('PATCH',`/staff/orders/${saved.order.id}/status`,{status:'rejected'},{},ctx(staff)),{status:400});const result=await app.route('PATCH',`/staff/orders/${saved.order.id}/status`,{status:'rejected',reason:'Kitchen closing'},{},ctx(staff));assert.equal(result.order.history.at(-1).reason,'Kitchen closing');});
test('server rejects wrong prices, unavailable dishes and inactive tables',async()=>{const b=body();b.items[0].unit_price=1;await assert.rejects(app.route('POST','/orders',b,{},ctx()),{status:409});await db.query("UPDATE aw_menu SET available=false WHERE id='sushi'");await assert.rejects(app.route('POST','/orders',body({items:[{id:'sushi',quantity:1,unit_price:2200}]}),{},ctx()),{status:409});await db.query("UPDATE aw_tables SET active=false WHERE id='T05'");await assert.rejects(app.route('POST','/orders',body({table_id:'T05'}),{},ctx()),{status:409});await db.query("UPDATE aw_tables SET active=true WHERE id='T05'");});
test('menu and table edits do not rewrite historical snapshots',async()=>{const b=body();const saved=await app.route('POST','/orders',b,{},ctx());await db.query("UPDATE aw_menu SET name='New chicken name',price=1900 WHERE id='chicken'");await db.query("UPDATE aw_tables SET name='Renamed table' WHERE id='T03'");const record=(await app.route('GET','/orders/'+saved.order.id,{}, {},{orderToken:b.access_token})).order;assert.equal(record.table_name,'Table 03');assert.equal(record.items.find(i=>i.menu_id==='chicken').unit_price,1800);assert.equal(record.items.find(i=>i.menu_id==='chicken').name,'Crispy Chicken Platter');await db.query("UPDATE aw_menu SET name='Crispy Chicken Platter',price=1800 WHERE id='chicken'");await db.query("UPDATE aw_tables SET name='Table 03' WHERE id='T03'");});
test('staff cannot change prices or create staff accounts',async()=>{await assert.rejects(app.route('PATCH','/staff/menu',{}, {},ctx(staff)),{status:403});await assert.rejects(app.route('POST','/staff/users',{}, {},ctx(staff)),{status:403});await assert.rejects(app.route('POST','/staff/setup',{setup_token:setup,name:'Other',email:'other@example.com',password:'another-long-password'},{},ctx()),{status:409});});
test('closing ordering rejects new orders but retains existing queue',async()=>{const before=(await app.route('GET','/staff/orders',{}, {},ctx(staff))).orders.length;await db.query('UPDATE aw_settings SET ordering_enabled=false');await assert.rejects(app.route('POST','/orders',body(),{},ctx()),{status:409});assert.equal((await app.route('GET','/staff/orders',{}, {},ctx(staff))).orders.length,before);await db.query('UPDATE aw_settings SET ordering_enabled=true');});
test('SSE authenticates and sends the complete recoverable order snapshot',async()=>{const server=createServer(httpHandler(db,{streamMs:100,streamInterval:25}));await new Promise(r=>server.listen(0,'127.0.0.1',r));try{const response=await fetch(`http://127.0.0.1:${server.address().port}/api/staff/stream`,{headers:{Authorization:'Bearer '+staff}});assert.equal(response.status,200);assert.match(response.headers.get('content-type'),/text\/event-stream/);const data=await response.text();assert.match(data,/data:.*"table_id":"T03"/);assert.match(data,/"items":/);}finally{server.closeAllConnections();await new Promise(r=>server.close(r));}});
test('persisted orders survive reopening the database',async()=>{const saved=await app.route('POST','/orders',body(),{},ctx());await pg.close();pg=new PGlite(folder);await pg.waitReady;assert.equal((await db.query('SELECT table_id,payment_status FROM aw_orders WHERE id=$1',[saved.order.id])).rows[0].table_id,'T03');});

test('dish creation, uploaded photo, edits, archive and restore preserve orders',async()=>{
 const photo=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aD1cAAAAASUVORK5CYII=','base64');
 const uploaded=await app.route('POST','/staff/media',{mime:'image/png',base64:photo.toString('base64')},{},ctx(owner));
 const value={name:'New test dish',category_id:'mains',description:'Fresh test dish',ingredients:'Rice, vegetables',allergens:'Soy',price:1250,image:uploaded.image,vegetarian:true,available:true};
 const added=await app.route('POST','/staff/menu',value,{},ctx(owner));
 let menu=(await app.route('GET','/menu')).items;assert.equal(menu.find(m=>m.id===added.id).ingredients,value.ingredients);
 const b=body({items:[{id:added.id,quantity:1,unit_price:1250}],expected_total:1250});
 const saved=await app.route('POST','/orders',b,{},ctx());
 await app.route('PATCH','/staff/menu',{...value,id:added.id,name:'Updated test dish',price:1500,available:false},{},ctx(owner));
 menu=(await app.route('GET','/menu')).items;assert.equal(menu.find(m=>m.id===added.id).available,false);
 await assert.rejects(app.route('POST','/orders',body({items:b.items}),{},ctx()),{status:409});
 await app.route('PATCH',`/staff/menu/${added.id}/archive`,{archived:true},{},ctx(owner));
 assert(!(await app.route('GET','/menu')).items.some(m=>m.id===added.id));
 const old=(await app.route('GET','/orders/'+saved.order.id,{}, {},{orderToken:b.access_token})).order;
 assert.equal(old.items[0].name,value.name);assert.equal(old.items[0].unit_price,1250);
 await app.route('PATCH',`/staff/menu/${added.id}/archive`,{archived:false},{},ctx(owner));
 assert((await app.route('GET','/menu')).items.some(m=>m.id===added.id));
 const server=createServer(httpHandler(db));await new Promise(r=>server.listen(0,'127.0.0.1',r));
 try{const r=await fetch(`http://127.0.0.1:${server.address().port}`+uploaded.image);assert.equal(r.status,200);assert.equal(r.headers.get('content-type'),'image/png');assert.deepEqual(Buffer.from(await r.arrayBuffer()),photo);}finally{server.closeAllConnections();await new Promise(r=>server.close(r));}
 await pg.close();pg=new PGlite(folder);await pg.waitReady;assert.equal((await db.query('SELECT count(*)::int n FROM aw_media WHERE id=$1',[uploaded.image.slice(11)])).rows[0].n,1);
});
test('media and menu writes enforce roles and validate photo contents',async()=>{
 await assert.rejects(app.route('POST','/staff/media',{}, {},ctx()),{status:401});
 await assert.rejects(app.route('POST','/staff/media',{}, {},ctx(staff)),{status:403});
 await assert.rejects(app.route('POST','/staff/menu',{}, {},ctx(staff)),{status:403});
 await assert.rejects(app.route('PATCH','/staff/menu/coffee/archive',{archived:true}, {},ctx(staff)),{status:403});
 for(const mime of ['image/svg+xml','image/png'])await assert.rejects(app.route('POST','/staff/media',{mime,base64:Buffer.from('not an image').toString('base64')},{},ctx(owner)),{status:400});
 await assert.rejects(app.route('POST','/staff/media',{mime:'image/png',base64:Buffer.alloc(2097153).toString('base64')},{},ctx(owner)),{status:413});
});
test('a tax or price change requires a new reviewed quote before saving',async()=>{
 const b=body();await db.query('UPDATE aw_settings SET tax_basis_points=1000');
 await assert.rejects(app.route('POST','/orders',b,{},ctx()),{status:409});
 assert.equal((await db.query('SELECT count(*)::int n FROM aw_idempotency WHERE key=$1',[b.request_key])).rows[0].n,0);
 const q=await app.route('POST','/orders/quote',b);b.expected_total=q.total;
 const saved=await app.route('POST','/orders',b,{},ctx());assert.equal(saved.order.total,q.total);
 const replay=await app.route('POST','/orders',b,{},ctx());assert.equal(replay.order.id,saved.order.id);
 await db.query('UPDATE aw_settings SET tax_basis_points=0');
 const changed=body();await db.query("UPDATE aw_menu SET price=500 WHERE id='coffee'");
 await assert.rejects(app.route('POST','/orders',changed,{},ctx()),{status:409});
 await db.query("UPDATE aw_menu SET price=450 WHERE id='coffee'");
});
test('same admin credentials create independent sessions for both websites',async()=>{
 const credentials={email:'owner@example.com',password:'a-long-owner-test-password'};
 const a=await app.route('POST','/staff/auth/login',credentials,{},ctx());const b=await app.route('POST','/staff/auth/login',credentials,{},ctx());assert.notEqual(a.token,b.token);
 await app.route('POST','/staff/auth/logout',{}, {},ctx(a.token));assert.equal(await app.session(a.token),null);assert.equal((await app.session(b.token)).role,'owner');
});
