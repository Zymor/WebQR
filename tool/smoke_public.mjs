import assert from 'node:assert/strict';
import {database} from '../backend/db.mjs';
import {secret,uuid,passwordHash} from '../backend/security.mjs';
const origin=process.env.AFTERWORK_TEST_ORIGIN??'https://afterwork-livid.vercel.app';
const db=database(),staffId='check-'+uuid(),email=staffId+'@afterwork.invalid',password=secret(),customerToken=secret(),requestKey=secret();
let staffToken,orderId;const streams=[];
async function call(path,{method='GET',body,staff=false,customer=false,expected=200}={}){
 const headers={'Content-Type':'application/json','Origin':staff?'https://afterwork-admin.vercel.app':'https://afterwork-livid.vercel.app'};
 if(staff)headers.Authorization='Bearer '+staffToken;if(customer)headers['X-Order-Token']=customerToken;
 const r=await fetch(origin+'/api'+path,{method,headers,body:body===undefined?undefined:JSON.stringify(body)});const data=await r.json();assert.equal(r.status,expected,`${path}: ${data.error??''}`);return data;
}
async function live(){const controller=new AbortController();streams.push(controller);const response=await fetch(origin+'/api/staff/stream',{headers:{Authorization:'Bearer '+staffToken,Origin:'https://afterwork-admin.vercel.app'},signal:controller.signal});assert.equal(response.status,200);assert.match(response.headers.get('content-type'),/text\/event-stream/);return {controller,reader:response.body.getReader(),buffer:''};}
async function observe(stream,reference,status){const until=Date.now()+20000;while(Date.now()<until){const read=await Promise.race([stream.reader.read(),new Promise((_,reject)=>setTimeout(()=>reject(new Error('Live update timed out')),15000))]);if(read.done)throw new Error('Live connection closed before expected order');stream.buffer+=new TextDecoder().decode(read.value);let split;while((split=stream.buffer.indexOf('\n\n'))>=0){const event=stream.buffer.slice(0,split);stream.buffer=stream.buffer.slice(split+2);const line=event.split('\n').find(l=>l.startsWith('data: '));if(line){const snapshot=JSON.parse(line.slice(6));const order=snapshot.orders?.find(o=>o.id===reference);if(order&&(!status||order.status===status))return order;}}}throw new Error('Order was not observed.');}
try{
 await call('/health');
 await db.query('INSERT INTO aw_staff(id,email,name,password_hash,role) VALUES($1,$2,$3,$4,$5)',[staffId,email,'AUTOMATED ACCEPTANCE CHECK',await passwordHash(password),'staff']);
 staffToken=(await call('/staff/auth/login',{method:'POST',body:{email,password}})).token;
 const feed=await live();
 const table=await call('/tables/T03');assert.equal(table.id,'T03');
 const menu=(await call('/menu')).items;
 const chicken=menu.find(i=>i.id==='chicken'),coffee=menu.find(i=>i.id==='coffee');
 const body={table_id:'T03',request_key:requestKey,access_token:customerToken,notes:'AUTOMATED ACCEPTANCE CHECK — NO FOOD PREPARATION',items:[{id:chicken.id,quantity:2,unit_price:chicken.price,notes:'Test item note'},{id:coffee.id,quantity:1,unit_price:coffee.price}]};
 const quote=await call('/orders/quote',{method:'POST',body});assert.equal(quote.total,chicken.price*2+coffee.price+quote.tax);body.expected_total=quote.total;
 const [first,duplicate]=await Promise.all([call('/orders',{method:'POST',body}),call('/orders',{method:'POST',body})]);orderId=first.order.id;assert.equal(duplicate.order.id,orderId);assert.equal(first.order.table_name,table.name);assert.equal(first.order.payment_status,'unpaid');
 const received=await observe(feed,orderId,'new');assert.equal(received.items.length,2);assert.equal(received.items.find(i=>i.menu_id==='chicken').quantity,2);
 console.log('PASS: Table 03 guest order appears in authenticated live staff feed with correct dishes and quantities.');
 await call('/staff/orders',{expected:401});await call('/orders/'+orderId,{expected:404});
 await call('/staff/menu',{method:'PATCH',staff:true,body:{},expected:403});
 for(const status of ['accepted','preparing'])await call(`/staff/orders/${orderId}/status`,{method:'PATCH',staff:true,body:{status}});
 assert.equal((await observe(feed,orderId,'preparing')).status,'preparing');
 assert.equal((await call('/orders/'+orderId,{customer:true})).order.status,'preparing');
 feed.controller.abort();const recovered=await live();assert.equal((await observe(recovered,orderId,'preparing')).id,orderId);recovered.controller.abort();
 for(const status of ['ready','served','completed'])await call(`/staff/orders/${orderId}/status`,{method:'PATCH',staff:true,body:{status}});
 const final=(await call('/orders/'+orderId,{customer:true})).order;assert.equal(final.status,'completed');assert.equal(final.payment_status,'unpaid');assert.equal(final.history.length,6);
 console.log('PASS: Customer observes staff updates; reconnect reloads saved orders; workflow completes while payment stays unpaid.');
 console.log('PASS: Duplicate requests create one record; anonymous staff access and wrong customer tokens are rejected.');
}catch(e){console.error('PUBLIC ACCEPTANCE FAILED:',e.message);process.exitCode=1;}
finally{
 for(const controller of streams)controller.abort();
 await db.transaction(async c=>{
  if(orderId){await c.query('DELETE FROM aw_order_history WHERE order_id=$1',[orderId]);await c.query('DELETE FROM aw_order_items WHERE order_id=$1',[orderId]);await c.query('DELETE FROM aw_idempotency WHERE order_id=$1',[orderId]);await c.query('DELETE FROM aw_audit WHERE record_id=$1',[orderId]);await c.query('DELETE FROM aw_orders WHERE id=$1',[orderId]);}
  await c.query('DELETE FROM aw_sessions WHERE staff_id=$1',[staffId]);await c.query('DELETE FROM aw_audit WHERE actor_id=$1',[staffId]);await c.query('DELETE FROM aw_staff WHERE id=$1',[staffId]);await c.query('UPDATE aw_settings SET revision=revision+1 WHERE id=1');
 });
 console.log('Temporary acceptance-check account and order removed; no test order remains in the operational queue.');
 setTimeout(()=>process.exit(process.exitCode??0),100);
}
