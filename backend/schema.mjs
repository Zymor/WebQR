export const schema=`
CREATE TABLE IF NOT EXISTS aw_staff(id text PRIMARY KEY,email text NOT NULL UNIQUE,name text NOT NULL,password_hash text NOT NULL,role text NOT NULL CHECK(role IN ('owner','manager','staff')),active boolean NOT NULL DEFAULT true,created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE IF NOT EXISTS aw_sessions(token_hash text PRIMARY KEY,staff_id text NOT NULL REFERENCES aw_staff(id),expires_at timestamptz NOT NULL,created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE IF NOT EXISTS aw_tables(id text PRIMARY KEY,name text NOT NULL,seats integer NOT NULL CHECK(seats BETWEEN 1 AND 30),area text NOT NULL DEFAULT 'Indoor',experience text NOT NULL DEFAULT 'Restaurant',active boolean NOT NULL DEFAULT true,updated_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE IF NOT EXISTS aw_categories(id text PRIMARY KEY,name text NOT NULL,experience text NOT NULL);
CREATE TABLE IF NOT EXISTS aw_menu(id text PRIMARY KEY,category_id text NOT NULL REFERENCES aw_categories(id),name text NOT NULL,description text NOT NULL,price integer NOT NULL CHECK(price>=0),image text NOT NULL,allergens text NOT NULL DEFAULT '',vegetarian boolean NOT NULL DEFAULT false,available boolean NOT NULL DEFAULT true,updated_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE IF NOT EXISTS aw_settings(id integer PRIMARY KEY CHECK(id=1),ordering_enabled boolean NOT NULL DEFAULT true,tax_basis_points integer NOT NULL DEFAULT 0 CHECK(tax_basis_points BETWEEN 0 AND 10000),customer_url text NOT NULL DEFAULT 'https://afterwork-livid.vercel.app',staff_url text NOT NULL DEFAULT '',revision bigint NOT NULL DEFAULT 0);
CREATE TABLE IF NOT EXISTS aw_orders(id text PRIMARY KEY,access_hash text NOT NULL,table_id text NOT NULL REFERENCES aw_tables(id),table_name text NOT NULL,name text NOT NULL DEFAULT 'Guest',notes text NOT NULL DEFAULT '',subtotal integer NOT NULL CHECK(subtotal>=0),tax integer NOT NULL CHECK(tax>=0),total integer NOT NULL CHECK(total>=0),status text NOT NULL DEFAULT 'new' CHECK(status IN ('new','accepted','preparing','ready','served','completed','rejected','cancelled')),payment_status text NOT NULL DEFAULT 'unpaid' CHECK(payment_status IN ('unpaid','paid')),created_at timestamptz NOT NULL DEFAULT now(),updated_at timestamptz NOT NULL DEFAULT now());
CREATE INDEX IF NOT EXISTS aw_orders_queue ON aw_orders(status,created_at DESC);
CREATE INDEX IF NOT EXISTS aw_orders_table ON aw_orders(table_id,created_at DESC);
CREATE TABLE IF NOT EXISTS aw_order_items(id text PRIMARY KEY,order_id text NOT NULL REFERENCES aw_orders(id),menu_id text NOT NULL REFERENCES aw_menu(id),name text NOT NULL,unit_price integer NOT NULL CHECK(unit_price>=0),quantity integer NOT NULL CHECK(quantity BETWEEN 1 AND 20),notes text NOT NULL DEFAULT '');
CREATE TABLE IF NOT EXISTS aw_order_history(id bigserial PRIMARY KEY,order_id text NOT NULL REFERENCES aw_orders(id),status text NOT NULL,actor_id text REFERENCES aw_staff(id),reason text NOT NULL DEFAULT '',created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE IF NOT EXISTS aw_idempotency(key text PRIMARY KEY,fingerprint text NOT NULL,order_id text NOT NULL REFERENCES aw_orders(id));
CREATE TABLE IF NOT EXISTS aw_audit(id bigserial PRIMARY KEY,actor_id text REFERENCES aw_staff(id),action text NOT NULL,record_id text NOT NULL,details jsonb NOT NULL DEFAULT '{}',created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE IF NOT EXISTS aw_rate_limits(key text PRIMARY KEY,hits integer NOT NULL,window_start timestamptz NOT NULL);
ALTER TABLE aw_menu ADD COLUMN IF NOT EXISTS ingredients text NOT NULL DEFAULT '';
ALTER TABLE aw_menu ADD COLUMN IF NOT EXISTS archived boolean NOT NULL DEFAULT false;
CREATE TABLE IF NOT EXISTS aw_media(id text PRIMARY KEY,mime text NOT NULL,data bytea NOT NULL,created_at timestamptz NOT NULL DEFAULT now());
INSERT INTO aw_settings(id) VALUES(1) ON CONFLICT DO NOTHING;
`;
const menu=[
 ['berry','desserts','Desserts','Café','Berry & Vanilla Cream Pot',1200,'Silky vanilla cream meets bright seasonal berries in a little pot of happiness.','dessert','Milk, eggs',true],
 ['sandwich','breakfast','Breakfast','Café','The Golden Grilled Cheese',1400,'Golden sourdough with melted cheddar and mozzarella.','sandwich','Wheat, milk',true],
 ['chicken','mains','Main Courses','Restaurant','Crispy Chicken Platter',1800,'Crispy golden chicken, seasoned fries and creamy herb dip.','chicken','Wheat, eggs, milk',false],
 ['sushi','seafood','Seafood','Restaurant','Salmon Nigiri',2200,'Salmon over delicately seasoned sushi rice.','sushi','Fish, soy',false],
 ['coffee','coffee','Hot Coffee','Café','Signature Cappuccino',450,'House espresso with silky steamed milk.','coffee','Milk',true],
 ['dinner','sets','Set Meals','Restaurant','Chef’s Tasting Experience',4800,'A seasonal journey through the kitchen.','restaurant','Ask staff about seasonal allergens',false]
];
export async function initialize(db){
 await db.transaction(async(c)=>{
  await c.query('SELECT pg_advisory_xact_lock(71402627)');
  for(const statement of schema.split(';').map(s=>s.trim()).filter(Boolean)) await c.query(statement);
  for(let i=1;i<=5;i++)await c.query('INSERT INTO aw_tables(id,name,seats) VALUES($1,$2,$3) ON CONFLICT DO NOTHING',[`T0${i}`,`Table 0${i}`,[2,2,4,4,8][i-1]]);
  if(/^https:\/\/[^/]+$/.test(process.env.STAFF_ORIGIN??''))await c.query("UPDATE aw_settings SET staff_url=$1 WHERE id=1 AND staff_url=''",[process.env.STAFF_ORIGIN]);
  for(const m of menu){await c.query('INSERT INTO aw_categories(id,name,experience) VALUES($1,$2,$3) ON CONFLICT DO NOTHING',[m[1],m[2],m[3]]);await c.query('INSERT INTO aw_menu(id,category_id,name,price,description,image,allergens,vegetarian) VALUES($1,$2,$3,$4,$5,$6,$7,$8) ON CONFLICT DO NOTHING',[m[0],m[1],m[4],m[5],m[6],m[7],m[8],m[9]]);}
 });
}
