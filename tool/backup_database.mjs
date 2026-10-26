import {database} from '../backend/db.mjs';
import {writeFileSync} from 'node:fs';
const db=database();const tables=['aw_staff','aw_tables','aw_categories','aw_menu','aw_settings','aw_orders','aw_order_items','aw_order_history','aw_audit','aw_idempotency'];
const backup=await db.transaction(async c=>{await c.query('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ');const result={version:1,created_at:new Date().toISOString(),tables:{}};for(const name of tables)result.tables[name]=(await c.query('SELECT * FROM '+name)).rows;return result;});
const path=`afterwork-${new Date().toISOString().replaceAll(':','-')}.backup.json`;
writeFileSync(path,JSON.stringify(backup),{mode:0o600});console.log('Private database backup created:',path);process.exit(0);
