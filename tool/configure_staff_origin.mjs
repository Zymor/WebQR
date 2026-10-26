import {database} from '../backend/db.mjs';
const db=database();await db.query('UPDATE aw_settings SET staff_url=$1 WHERE id=1',['https://afterwork-admin.vercel.app']);console.log('Public staff origin configured.');process.exit(0);
