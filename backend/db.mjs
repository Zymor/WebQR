import pg from 'pg';
let pool;
export function database() {
  if (!pool) {
    const url=process.env.DATABASE_URL || process.env.POSTGRES_URL;
    if(!url) throw Object.assign(new Error('The ordering database is not connected yet.'),{status:503});
    const connection=new URL(url); if(connection.searchParams.get('sslmode')==='require')connection.searchParams.set('sslmode','verify-full');
    pool=new pg.Pool({connectionString:connection.toString(),max:4,idleTimeoutMillis:10000,connectionTimeoutMillis:12000});
    pool.on('error',()=>console.error('Database pool connection lost'));
  }
  return {query:(...a)=>pool.query(...a),transaction:async(fn)=>{const c=await pool.connect();try{await c.query('BEGIN');const value=await fn(c);await c.query('COMMIT');return value;}catch(e){await c.query('ROLLBACK');throw e;}finally{c.release();}}};
}
