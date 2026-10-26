import {createServer} from 'node:http';
import {database} from './db.mjs';
import {initialize} from './schema.mjs';
import {httpHandler} from './http.mjs';
const db=database();await initialize(db);
createServer(httpHandler(db,{production:false})).listen(Number(process.env.PORT??8788),'127.0.0.1',()=>console.log('After Work ordering API is listening on http://127.0.0.1:8788/api'));
