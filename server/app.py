"""After Work local API. Python 3.12+, no third-party dependencies.
All operational seed records are explicitly demonstration configuration.
Run: python server/app.py; provision admin: python server/app.py --create-admin EMAIL
"""
import argparse
import datetime as dt
import getpass
import hashlib
import hmac
import json
import os
import re
import secrets
import sqlite3
import threading
import time
from collections import defaultdict, deque
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

ROOT = Path(__file__).resolve().parent
DB = os.environ.get('SOCIAL_DB', str(ROOT / 'social.sqlite3'))
TZ = dt.timezone(dt.timedelta(hours=7))
LIMITS = defaultdict(deque)
LIMIT_LOCK = threading.Lock()
EXPERIENCES = ['Café', 'Restaurant', 'Pub & Lounge']

class Problem(Exception):
    def __init__(self, message, status=400):
        self.message, self.status = message, status

class ManagedConnection(sqlite3.Connection):
    def __exit__(self, *args):
        try:
            return super().__exit__(*args)
        finally:
            self.close()

def connect():
    con = sqlite3.connect(DB, timeout=15, factory=ManagedConnection)
    con.row_factory = sqlite3.Row
    con.execute('PRAGMA foreign_keys=ON')
    return con

def password_hash(password, salt=None):
    salt = salt or secrets.token_hex(16)
    return salt + ':' + hashlib.scrypt(password.encode(), salt=salt.encode(), n=16384, r=8, p=1).hex()

def rows(con, sql, args=()):
    return [dict(r) for r in con.execute(sql, args)]

def init():
    with connect() as con:
        con.executescript('''
        PRAGMA journal_mode=WAL;
        CREATE TABLE IF NOT EXISTS users(id TEXT PRIMARY KEY,email TEXT UNIQUE NOT NULL,name TEXT NOT NULL,password TEXT NOT NULL,role TEXT NOT NULL DEFAULT 'customer',verified INTEGER NOT NULL DEFAULT 0,created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP);
        CREATE TABLE IF NOT EXISTS sessions(token TEXT PRIMARY KEY,user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,expires INTEGER NOT NULL);
        CREATE TABLE IF NOT EXISTS action_tokens(token TEXT PRIMARY KEY,user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,kind TEXT NOT NULL,expires INTEGER NOT NULL);
        CREATE TABLE IF NOT EXISTS menu(id TEXT PRIMARY KEY,name TEXT NOT NULL,category TEXT NOT NULL,experience TEXT NOT NULL,image TEXT NOT NULL,price INTEGER NOT NULL CHECK(price>=0),description TEXT NOT NULL,allergens TEXT NOT NULL,vegetarian INTEGER NOT NULL DEFAULT 0,available INTEGER NOT NULL DEFAULT 1);
        CREATE TABLE IF NOT EXISTS tables_config(id TEXT PRIMARY KEY,experience TEXT NOT NULL,area TEXT NOT NULL,seats INTEGER NOT NULL CHECK(seats>0));
        CREATE TABLE IF NOT EXISTS blocked_dates(date TEXT PRIMARY KEY);
        CREATE TABLE IF NOT EXISTS reservations(id TEXT PRIMARY KEY,access_token TEXT UNIQUE NOT NULL,user_id TEXT REFERENCES users(id) ON DELETE SET NULL,table_id TEXT NOT NULL REFERENCES tables_config(id),date TEXT NOT NULL,time TEXT NOT NULL,end_time TEXT NOT NULL,party INTEGER NOT NULL,name TEXT NOT NULL,email TEXT NOT NULL,phone TEXT NOT NULL,notes TEXT NOT NULL,status TEXT NOT NULL DEFAULT 'confirmed',created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP);
        CREATE INDEX IF NOT EXISTS reservation_slots ON reservations(table_id,date,time,end_time,status);
        CREATE TABLE IF NOT EXISTS orders(id TEXT PRIMARY KEY,access_token TEXT UNIQUE NOT NULL,user_id TEXT REFERENCES users(id) ON DELETE SET NULL,name TEXT NOT NULL,email TEXT NOT NULL,notes TEXT NOT NULL,subtotal INTEGER NOT NULL,tax INTEGER NOT NULL,total INTEGER NOT NULL,status TEXT NOT NULL DEFAULT 'submitted',payment_status TEXT NOT NULL DEFAULT 'unpaid',created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP);
        CREATE TABLE IF NOT EXISTS order_requests(key TEXT PRIMARY KEY,order_id TEXT NOT NULL REFERENCES orders(id),fingerprint TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS order_items(id INTEGER PRIMARY KEY,order_id TEXT NOT NULL REFERENCES orders(id) ON DELETE CASCADE,menu_id TEXT NOT NULL REFERENCES menu(id),name TEXT NOT NULL,quantity INTEGER NOT NULL CHECK(quantity>0),unit_price INTEGER NOT NULL);
        CREATE TABLE IF NOT EXISTS favorites(user_id TEXT REFERENCES users(id) ON DELETE CASCADE,menu_id TEXT REFERENCES menu(id),PRIMARY KEY(user_id,menu_id));
        CREATE TABLE IF NOT EXISTS events(id TEXT PRIMARY KEY,title TEXT NOT NULL,description TEXT NOT NULL,image TEXT NOT NULL,date TEXT NOT NULL,time TEXT NOT NULL,capacity INTEGER NOT NULL CHECK(capacity>0),status TEXT NOT NULL DEFAULT 'draft');
        CREATE TABLE IF NOT EXISTS registrations(id TEXT PRIMARY KEY,event_id TEXT NOT NULL REFERENCES events(id),email TEXT NOT NULL,name TEXT NOT NULL,UNIQUE(event_id,email));
        CREATE TABLE IF NOT EXISTS newsletter(email TEXT PRIMARY KEY,consented_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,token TEXT UNIQUE NOT NULL);
        CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY,value TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS audit(id INTEGER PRIMARY KEY,actor TEXT,action TEXT NOT NULL,record_id TEXT,created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP);
        ''')
        menu = [
          ('berry','Berry & Vanilla Cream Pot','Desserts','Café','dessert',1200,'Silky vanilla cream meets bright seasonal berries in a little pot of happiness. Fresh, gently sweet, and made for one more spoonful.','Milk, eggs',1),
          ('sandwich','The Golden Grilled Cheese','Breakfast','Café','sandwich',1400,'Golden sourdough, a generous blend of melted cheddar and mozzarella, and a little comfort in every bite.','Wheat, milk',1),
          ('chicken','Crispy Chicken Platter','Main Courses','Restaurant','chicken',1800,'Crispy golden chicken, seasoned fries and our house-made creamy herb dip. A feel-good favorite.','Wheat, eggs, milk',0),
          ('sushi','Salmon Nigiri','Seafood','Restaurant','sushi',2200,'Beautifully cut salmon over delicately seasoned sushi rice, with pickled ginger and wasabi.','Fish, soy',0),
          ('coffee','Signature Cappuccino','Hot Coffee','Café','coffee',450,'Our house espresso with silky steamed milk. Rich, balanced, and made for slow mornings.','Milk',1),
          ('dinner','Chef’s Tasting Experience','Set Meals','Restaurant','restaurant',4800,'A seasonal journey through the kitchen, thoughtfully plated and made for memorable evenings.','Ask our team for the seasonal allergen list',0),
        ]
        con.executemany('INSERT OR IGNORE INTO menu(id,name,category,experience,image,price,description,allergens,vegetarian) VALUES(?,?,?,?,?,?,?,?,?)',menu)
        con.execute("UPDATE menu SET name=?,description=? WHERE id='berry' AND name='Berry Cream Pavlova'", (menu[0][1], menu[0][6]))
        # Migrate only untouched original demo tables; referenced table records are retained.
        if not con.execute("SELECT 1 FROM settings WHERE key='tables_initialized'").fetchone():
            for legacy_experience in EXPERIENCES:
                for i in range(6):
                    con.execute('DELETE FROM tables_config WHERE id=? AND NOT EXISTS (SELECT 1 FROM reservations r WHERE r.table_id=tables_config.id)',(f'{legacy_experience}-{i}',))
        table_columns={r[1] for r in con.execute('PRAGMA table_info(tables_config)')}
        if 'name' not in table_columns: con.execute("ALTER TABLE tables_config ADD COLUMN name TEXT NOT NULL DEFAULT ''")
        if 'active' not in table_columns: con.execute('ALTER TABLE tables_config ADD COLUMN active INTEGER NOT NULL DEFAULT 1')
        if 'table_id' not in {r[1] for r in con.execute('PRAGMA table_info(orders)')}: con.execute('ALTER TABLE orders ADD COLUMN table_id TEXT REFERENCES tables_config(id)')
        if not con.execute("SELECT 1 FROM settings WHERE key='tables_initialized'").fetchone():
            for i,seats in enumerate([2,2,4,4,8],1):
                con.execute('INSERT OR IGNORE INTO tables_config(id,experience,area,seats,name) VALUES(?,?,?,?,?)',(f'T{i:02}','Restaurant','Indoor',seats,f'Table {i:02}'))
            con.execute("INSERT INTO settings VALUES('tables_initialized','true')")
        for key, value in {'demo':True,'venue_name':'After Work','address':'','phone':'','email':'','hours':{'Café':[8,17],'Restaurant':[11,22],'Pub & Lounge':[17,23]},'booking_minutes':90,'tax_basis_points':0,'ordering_enabled':True,'max_party':8,'website_url':''}.items():
            con.execute('INSERT OR IGNORE INTO settings VALUES(?,?)',(key,json.dumps(value)))

def settings(con):
    return {r['key']:json.loads(r['value']) for r in con.execute('SELECT * FROM settings') if r['key']!='tables_initialized'}

def email(value):
    value = str(value).strip().lower()
    if len(value)>254 or not re.fullmatch(r'[^\s@]+@[^\s@]+\.[^\s@]+',value):
        raise Problem('Enter a valid email address.')
    return value

def text(data, key, minimum=1, maximum=500):
    value = str(data.get(key,'')).strip()
    if not minimum <= len(value) <= maximum:
        raise Problem(f'{key}: enter between {minimum} and {maximum} characters.')
    return value

def integer(data, key, lo, hi):
    value = data.get(key)
    if isinstance(value,bool) or not isinstance(value,int) or not lo <= value <= hi:
        raise Problem(f'{key}: expected a whole number from {lo} to {hi}.')
    return value

def validate_slot(con, data):
    config = settings(con)
    exp = data.get('experience')
    if exp not in EXPERIENCES: raise Problem('Select a valid experience.')
    party = integer(data,'party',1,config['max_party'])
    try: date = dt.date.fromisoformat(str(data.get('date','')))
    except ValueError: raise Problem('Select a valid date.')
    now = dt.datetime.now(TZ)
    if date < now.date() or date > now.date()+dt.timedelta(days=180): raise Problem('Bookings must be within the next 180 days.')
    if con.execute('SELECT 1 FROM blocked_dates WHERE date=?',(date.isoformat(),)).fetchone(): return exp,party,date,[],config
    return exp,party,date,rows(con,'SELECT * FROM tables_config WHERE experience=? AND seats>=? AND area=? AND active=1 ORDER BY seats',(exp,party,data.get('area','Lounge' if exp=='Pub & Lounge' else 'Indoor'))),config

def availability(con, data):
    exp,party,date,tables,config = validate_slot(con,data)
    opening,closing = config['hours'][exp]
    duration = config['booking_minutes']
    now = dt.datetime.now(TZ)
    result=[]
    for minute in range(opening*60,closing*60-duration+1,30):
        start=f'{minute//60:02}:{minute%60:02}'
        end=f'{(minute+duration)//60:02}:{(minute+duration)%60:02}'
        if dt.datetime.combine(date,dt.time(minute//60,minute%60),TZ) <= now: continue
        free=[t for t in tables if not con.execute("SELECT 1 FROM reservations WHERE table_id=? AND date=? AND status IN ('confirmed','pending') AND time<? AND end_time>?",(t['id'],date.isoformat(),end,start)).fetchone()]
        if free: result.append({'time':start,'end_time':end,'table_id':free[0]['id']})
    return result

class Handler(BaseHTTPRequestHandler):
    server_version='SocialHouse/1'
    def allowed_origin(self,origin):
        if re.fullmatch(r'https?://(localhost|127\.0\.0\.1)(:\d+)?',origin): return True
        with connect() as con:
            site=urlparse(settings(con).get('website_url',''))
        return bool(site.netloc and origin==site.scheme+'://'+site.netloc)
    def log_message(self, format, *args):
        # Do not log URLs, access tokens, credentials, or personal data.
        pass
    def reply(self, data, status=200):
        encoded=json.dumps(data,ensure_ascii=False).encode()
        self.send_response(status)
        origin=self.headers.get('Origin','')
        if self.allowed_origin(origin):
            self.send_header('Access-Control-Allow-Origin',origin)
            self.send_header('Vary','Origin')
        self.send_header('Content-Type','application/json; charset=utf-8')
        self.send_header('Cache-Control','no-store')
        self.send_header('X-Content-Type-Options','nosniff')
        self.send_header('Content-Length',str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)
    def do_OPTIONS(self):
        self.send_response(204)
        origin=self.headers.get('Origin','')
        if self.allowed_origin(origin): self.send_header('Access-Control-Allow-Origin',origin)
        self.send_header('Access-Control-Allow-Headers','Content-Type, Authorization')
        self.send_header('Access-Control-Allow-Methods','GET, POST, PATCH, DELETE, OPTIONS')
        self.end_headers()
    def do_GET(self): self.handle_api('GET')
    def do_POST(self): self.handle_api('POST')
    def do_PATCH(self): self.handle_api('PATCH')
    def do_DELETE(self): self.handle_api('DELETE')
    def handle_api(self,method):
        try:
            length=int(self.headers.get('Content-Length','0'))
            if length > 32768: raise Problem('Request too large.',413)
            data=json.loads(self.rfile.read(length)) if length else {}
            if not isinstance(data,dict): raise Problem('Expected a JSON object.')
            parsed=urlparse(self.path)
            path=parsed.path.removeprefix('/api')
            query={k:v[0] for k,v in parse_qs(parsed.query).items()}
            if method!='GET':
                now=time.time()
                with LIMIT_LOCK:
                    if len(LIMITS)>10000: LIMITS.clear()
                    queue=LIMITS[(self.client_address[0],path)]
                    while queue and queue[0]<now-60: queue.popleft()
                    if len(queue)>=30: raise Problem('Too many requests. Try again in a minute.',429)
                    queue.append(now)
            with connect() as con:
                self.user=None
                token=self.headers.get('Authorization','').removeprefix('Bearer ')
                if token:
                    self.user=con.execute('SELECT u.* FROM users u JOIN sessions s ON u.id=s.user_id WHERE s.token=? AND s.expires>?',(hashlib.sha256(token.encode()).hexdigest(),int(time.time()))).fetchone()
                result=self.route(con,method,path,data,query)
            self.reply(result)
        except Problem as ex: self.reply({'error':ex.message},ex.status)
        except (ValueError,TypeError,KeyError): self.reply({'error':'Invalid request data.'},400)
        except sqlite3.IntegrityError: self.reply({'error':'This record already exists or conflicts with another record.'},409)
        except Exception:
            self.reply({'error':'The service could not complete this request. Please retry.'},500)
    def require(self,roles=None):
        if not self.user: raise Problem('Please sign in.',401)
        if roles and self.user['role'] not in roles: raise Problem('You do not have permission for this action.',403)
        return self.user['id']
    def audit(self,con,action,record):
        con.execute('INSERT INTO audit(actor,action,record_id) VALUES(?,?,?)',(self.user['id'] if self.user else None,action,record))
    def route(self,con,method,path,data,q):
        if path=='/health': return {'status':'ok','mode':'local development'}
        if path=='/tables' and method=='GET': return {'tables':rows(con,'SELECT id,name,experience,area,seats,active FROM tables_config ORDER BY id'),'website_url':settings(con).get('website_url','')}
        if path.startswith('/tables/') and method=='GET':
            table=con.execute('SELECT id,name,experience,area,seats FROM tables_config WHERE id=? AND active=1',(path.split('/')[-1],)).fetchone()
            if not table: raise Problem('This table is inactive or does not exist. Please ask a staff member.',404)
            return dict(table)
        if path=='/settings' and method=='GET': return settings(con)
        if path=='/menu' and method=='GET': return {'items':rows(con,'SELECT * FROM menu WHERE available=1')}
        if path=='/availability' and method=='POST': return {'slots':[{'time':s['time']} for s in availability(con,data)],'demo':settings(con)['demo']}
        if path=='/auth/register' and method=='POST':
            name=text(data,'name',2,100); address=email(data.get('email')); password=text(data,'password',12,200)
            uid=secrets.token_hex(12)
            con.execute('INSERT INTO users(id,email,name,password) VALUES(?,?,?,?)',(uid,address,name,password_hash(password)))
            return {'message':'Account created. Sign in to manage your demonstration bookings. Email delivery is not configured.'}
        if path=='/auth/login' and method=='POST':
            user=con.execute('SELECT * FROM users WHERE email=?',(email(data.get('email')),)).fetchone()
            if not user or not hmac.compare_digest(password_hash(str(data.get('password','')),user['password'].split(':')[0]),user['password']): raise Problem('Email or password is incorrect.',401)
            token=secrets.token_urlsafe(40)
            con.execute('INSERT INTO sessions VALUES(?,?,?)',(hashlib.sha256(token.encode()).hexdigest(),user['id'],int(time.time())+86400))
            return {'token':token,'user':{k:user[k] for k in ['id','name','email','role','verified']}}
        if path=='/auth/logout' and method=='POST':
            self.require()
            con.execute('DELETE FROM sessions WHERE token=?',(hashlib.sha256(self.headers.get('Authorization','').removeprefix('Bearer ').encode()).hexdigest(),))
            return {'message':'Signed out.'}
        if path=='/auth/reset' and method=='POST':
            email(data.get('email'))
            raise Problem('Password reset email is not configured. Contact the server operator.',503)
        if path=='/me':
            uid=self.require()
            if method=='GET': return {'user':{k:self.user[k] for k in ['id','name','email','role','verified']},'reservations':rows(con,'SELECT r.id,r.date,r.time,r.party,r.status,t.experience,t.area FROM reservations r JOIN tables_config t ON t.id=r.table_id WHERE user_id=? ORDER BY r.date DESC',(uid,)),'orders':rows(con,'SELECT id,total,status,payment_status,created_at,table_id FROM orders WHERE user_id=? ORDER BY created_at DESC',(uid,)),'favorites':[r[0] for r in con.execute('SELECT menu_id FROM favorites WHERE user_id=?',(uid,))]}
            if method=='PATCH':
                con.execute('UPDATE users SET name=? WHERE id=?',(text(data,'name',2,100),uid)); return {'message':'Profile saved.'}
            if method=='DELETE':
                if not hmac.compare_digest(password_hash(text(data,'password',12,200),self.user['password'].split(':')[0]),self.user['password']): raise Problem('Password incorrect.',401)
                con.execute('DELETE FROM users WHERE id=?',(uid,)); return {'message':'Account deleted. Transaction records remain for operational recordkeeping.'}
        if path=='/favorites' and method=='POST':
            uid=self.require(); item=text(data,'id',1,100)
            if data.get('saved'): con.execute('INSERT OR IGNORE INTO favorites VALUES(?,?)',(uid,item))
            else: con.execute('DELETE FROM favorites WHERE user_id=? AND menu_id=?',(uid,item))
            return {'message':'Favorites saved.'}
        if path=='/reservations' and method=='POST':
            name=text(data,'name',2,100); address=email(data.get('email')); phone=text(data,'phone',6,30); notes=text(data,'notes',0,1000)
            con.execute('BEGIN IMMEDIATE')
            slot=next((s for s in availability(con,data) if s['time']==data.get('time')),None)
            if not slot: raise Problem('This time is no longer available. Choose another slot.',409)
            uid=self.user['id'] if self.user else None
            # Same email and slot cannot create a duplicate on a client retry.
            duplicate=con.execute("SELECT * FROM reservations WHERE email=? AND date=? AND time=? AND status IN ('confirmed','pending')",(address,data['date'],slot['time'])).fetchone()
            if duplicate: raise Problem('You already have a reservation at this time.',409)
            rid='SH-'+secrets.token_hex(4).upper(); access=secrets.token_urlsafe(32)
            con.execute('INSERT INTO reservations(id,access_token,user_id,table_id,date,time,end_time,party,name,email,phone,notes) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)',(rid,access,uid,slot['table_id'],data['date'],slot['time'],slot['end_time'],data['party'],name,address,phone,notes))
            self.audit(con,'reservation.created',rid)
            return {'id':rid,'access_token':access,'status':'confirmed','date':data['date'],'time':slot['time'],'demo':settings(con)['demo'],'message':'Saved to the local demonstration database. This is not a reservation at a real venue. Save your reference and access token.'}
        if path.startswith('/reservations/'):
            rid=path.split('/')[-1]
            r=con.execute('SELECT r.*,t.experience,t.area FROM reservations r JOIN tables_config t ON t.id=r.table_id WHERE r.id=?',(rid,)).fetchone()
            if not r: raise Problem('Reservation not found.',404)
            authorized=(self.user and (r['user_id']==self.user['id'] or self.user['role'] in ['super_admin','manager','staff'])) or hmac.compare_digest(str(data.get('access_token',q.get('access_token',''))),r['access_token'])
            if not authorized: raise Problem('Your booking access token or account is required.',403)
            if method=='GET': return {k:r[k] for k in ['id','date','time','party','status','experience','area','name','notes']}
            if method=='PATCH':
                status=data.get('status','cancelled')
                if status!='cancelled': self.require(['super_admin','manager','staff'])
                if status not in ['pending','confirmed','cancelled','completed','no-show']: raise Problem('Invalid reservation status.')
                if status in ['pending','confirmed'] and r['status'] not in ['pending','confirmed']: raise Problem('Cancelled or completed bookings cannot be reopened. Create a new booking.')
                if status=='cancelled' and not (self.user and self.user['role'] in ['super_admin','manager','staff']) and dt.datetime.fromisoformat(r['date']+'T'+r['time']).replace(tzinfo=TZ) <= dt.datetime.now(TZ)+dt.timedelta(hours=2): raise Problem('Online cancellation closes two hours before your booking.')
                con.execute('UPDATE reservations SET status=? WHERE id=?',(status,rid)); self.audit(con,'reservation.'+status,rid); return {'message':'Reservation updated.'}
        if path=='/orders' and method=='POST':
            if not settings(con)['ordering_enabled']: raise Problem('Ordering is currently closed.',409)
            name=text(data,'name',2,100); address=email(data.get('email')); notes=text(data,'notes',0,1000)
            items=data.get('items',[])
            if not isinstance(items,list) or not 1<=len(items)<=30: raise Problem('Add between 1 and 30 items.')
            con.execute('BEGIN IMMEDIATE')
            request_key=text(data,'request_key',10,120)
            fingerprint=hashlib.sha256(json.dumps(data,sort_keys=True).encode()).hexdigest()
            previous=con.execute('SELECT o.*,r.fingerprint FROM order_requests r JOIN orders o ON o.id=r.order_id WHERE r.key=?',(request_key,)).fetchone()
            if previous:
                if previous['fingerprint']!=fingerprint: raise Problem('This checkout key was already used with different details.',409)
                return {'id':previous['id'],'access_token':previous['access_token'],'status':previous['status'],'payment_status':previous['payment_status'],'total':previous['total'],'demo':settings(con)['demo'],'message':'Previously submitted demonstration order retrieved. No duplicate order was created.'}
            table_id=data.get('table_id')
            if table_id and not con.execute('SELECT 1 FROM tables_config WHERE id=? AND active=1',(table_id,)).fetchone(): raise Problem('This table is no longer active. Please scan a current QR code.',409)
            lines=[]; subtotal=0
            for item in items:
                qty=integer(item,'quantity',1,20)
                product=con.execute('SELECT * FROM menu WHERE id=? AND available=1',(item.get('id'),)).fetchone()
                if not product: raise Problem('A menu item is no longer available.',409)
                if item.get('unit_price')!=product['price']: raise Problem('A price has changed. Refresh the menu and review your bag.',409)
                lines.append((product,qty)); subtotal+=product['price']*qty
            tax=(subtotal*settings(con)['tax_basis_points']+5000)//10000
            oid='ORD-'+secrets.token_hex(4).upper(); access=secrets.token_urlsafe(32)
            con.execute('INSERT INTO orders(id,access_token,user_id,name,email,notes,subtotal,tax,total) VALUES(?,?,?,?,?,?,?,?,?)',(oid,access,self.user['id'] if self.user else None,name,address,notes,subtotal,tax,subtotal+tax))
            con.execute('UPDATE orders SET table_id=? WHERE id=?',(table_id or None,oid))
            for p,qty in lines: con.execute('INSERT INTO order_items(order_id,menu_id,name,quantity,unit_price) VALUES(?,?,?,?,?)',(oid,p['id'],p['name'],qty,p['price']))
            con.execute('INSERT INTO order_requests VALUES(?,?,?)',(request_key,oid,fingerprint))
            self.audit(con,'order.submitted',oid)
            return {'id':oid,'access_token':access,'status':'submitted','payment_status':'unpaid','total':subtotal+tax,'demo':settings(con)['demo'],'message':'Order saved to the demonstration database. No payment was taken and no real kitchen was notified.'}
        if path.startswith('/orders/'):
            oid=path.split('/')[-1]; order=con.execute('SELECT * FROM orders WHERE id=?',(oid,)).fetchone()
            if not order: raise Problem('Order not found.',404)
            if not ((self.user and (self.user['id']==order['user_id'] or self.user['role'] in ['super_admin','manager','staff'])) or hmac.compare_digest(str(data.get('access_token',q.get('access_token',''))),order['access_token'])): raise Problem('Order access token or account required.',403)
            if method=='GET': return {'order':{k:order[k] for k in ['id','status','total','payment_status','notes','created_at','table_id']},'items':rows(con,'SELECT name,quantity,unit_price FROM order_items WHERE order_id=?',(oid,))}
            if method=='PATCH':
                status=data.get('status')
                transitions={'submitted':['accepted','rejected','cancelled'],'accepted':['preparing','cancelled'],'preparing':['ready'],'ready':['completed']}
                if status!='cancelled': self.require(['super_admin','manager','staff'])
                elif not (self.user and self.user['role'] in ['super_admin','manager','staff']) and order['status']!='submitted': raise Problem('Only unaccepted orders can be cancelled online.',409)
                if status not in transitions.get(order['status'],[]): raise Problem('This status change is not allowed.',409)
                con.execute('UPDATE orders SET status=? WHERE id=?',(status,oid)); self.audit(con,'order.'+status,oid); return {'message':'Order updated.'}
        if path=='/events' and method=='GET':
            return {'events':rows(con,"SELECT e.*, (SELECT COUNT(*) FROM registrations r WHERE r.event_id=e.id) AS registered FROM events e WHERE status IN ('published','cancelled') AND date>=? ORDER BY date",(dt.datetime.now(TZ).date().isoformat(),))}
        if path=='/events/register' and method=='POST':
            name=text(data,'name',2,100); address=email(data.get('email'))
            con.execute('BEGIN IMMEDIATE')
            event=con.execute('SELECT * FROM events WHERE id=?',(data.get('event_id'),)).fetchone()
            if not event or event['status']!='published' or event['date']<dt.datetime.now(TZ).date().isoformat(): raise Problem('This event is not accepting registrations.',409)
            if con.execute('SELECT COUNT(*) FROM registrations WHERE event_id=?',(event['id'],)).fetchone()[0]>=event['capacity']: raise Problem('This event is sold out.',409)
            rid='EV-'+secrets.token_hex(4).upper()
            con.execute('INSERT INTO registrations VALUES(?,?,?,?)',(rid,event['id'],address,name))
            return {'id':rid,'message':'Registration saved to the local demonstration database.'}
        if path=='/newsletter' and method=='POST':
            if data.get('consent') is not True: raise Problem('Please explicitly consent to receive updates.')
            address=email(data.get('email')); token=secrets.token_urlsafe(32)
            con.execute('INSERT INTO newsletter(email,token) VALUES(?,?)',(address,token))
            return {'message':'Consent saved locally. Email delivery is not configured. Save this unsubscribe token.','unsubscribe_token':token}
        if path=='/newsletter/unsubscribe' and method=='POST':
            con.execute('DELETE FROM newsletter WHERE token=?',(text(data,'token',20,100),)); return {'message':'Unsubscribed.'}
        if path.startswith('/admin'):
            self.require(['super_admin','manager','staff'])
            if path=='/admin/overview' and method=='GET':
                today=dt.datetime.now(TZ).date().isoformat()
                return {'reservations':rows(con,'SELECT r.id,r.date,r.time,r.name,r.party,r.status,t.experience FROM reservations r JOIN tables_config t ON t.id=r.table_id ORDER BY r.date DESC LIMIT 200'),'orders':rows(con,'SELECT id,name,total,status,payment_status,created_at,table_id FROM orders ORDER BY created_at DESC LIMIT 200'),'today_reservations':con.execute("SELECT COUNT(*) FROM reservations WHERE date=? AND status='confirmed'",(today,)).fetchone()[0],'today_guests':con.execute("SELECT COALESCE(SUM(party),0) FROM reservations WHERE date=? AND status='confirmed'",(today,)).fetchone()[0],'verified_sales':0,'menu':rows(con,'SELECT * FROM menu'),'events':rows(con,'SELECT * FROM events'),'settings':settings(con),'tables':rows(con,'SELECT * FROM tables_config'),'blocked_dates':rows(con,'SELECT * FROM blocked_dates'),'audit':rows(con,'SELECT * FROM audit ORDER BY id DESC LIMIT 50') if self.user['role'] in ['super_admin','manager'] else []}
            self.require(['super_admin','manager'])
            if path=='/admin/tables' and method in ['POST','PATCH']:
                tid=text(data,'id',1,40)
                if not re.fullmatch(r'[A-Za-z0-9_-]+',tid): raise Problem('Table IDs can contain letters, numbers, underscores and hyphens.')
                name=text(data,'name',1,60); seats=integer(data,'seats',1,20)
                exp=data.get('experience','Restaurant'); area=text(data,'area',1,60)
                if exp not in EXPERIENCES: raise Problem('Select a valid experience.')
                existing=con.execute('SELECT * FROM tables_config WHERE id=?',(tid,)).fetchone()
                if method=='POST' and existing: raise Problem('This table ID already exists. Choose another ID.',409)
                if method=='PATCH' and not existing: raise Problem('Table not found.',404)
                con.execute('INSERT INTO tables_config(id,name,seats,experience,area,active) VALUES(?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET name=excluded.name,seats=excluded.seats,experience=excluded.experience,area=excluded.area,active=excluded.active',(tid,name,seats,exp,area,int(bool(data.get('active',True)))))
                self.audit(con,'table.saved',tid)
                return {'message':'Table saved. Its QR link remains stable.','id':tid}
            if path=='/admin/menu' and method in ['POST','PATCH']:
                item_id=text(data,'id',1,100)
                values=(text(data,'name',2,100),text(data,'category',1,60),text(data,'experience',1,40),text(data,'image',1,60),integer(data,'price',0,1000000),text(data,'description',1,2000),text(data,'allergens',0,300),int(bool(data.get('vegetarian'))),int(bool(data.get('available',True))))
                if values[2] not in EXPERIENCES or values[3] not in ['dessert','sandwich','chicken','sushi','coffee','restaurant']: raise Problem('Select a supported experience and image asset.')
                con.execute('INSERT INTO menu(id,name,category,experience,image,price,description,allergens,vegetarian,available) VALUES(?,?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET name=excluded.name,category=excluded.category,experience=excluded.experience,image=excluded.image,price=excluded.price,description=excluded.description,allergens=excluded.allergens,vegetarian=excluded.vegetarian,available=excluded.available',(item_id,*values)); self.audit(con,'menu.saved',item_id); return {'message':'Menu item saved.'}
            if path=='/admin/events' and method in ['POST','PATCH']:
                eid=text(data,'id',1,100); title=text(data,'title',2,150); description=text(data,'description',1,2000); date=dt.date.fromisoformat(text(data,'date',10,10)); start=dt.time.fromisoformat(text(data,'time',5,5)); cap=integer(data,'capacity',1,10000); status=data.get('status','draft')
                if status not in ['draft','published','cancelled']: raise Problem('Invalid event status.')
                if cap<con.execute('SELECT COUNT(*) FROM registrations WHERE event_id=?',(eid,)).fetchone()[0]: raise Problem('Capacity is below existing registrations.')
                con.execute('INSERT INTO events VALUES(?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET title=excluded.title,description=excluded.description,image=excluded.image,date=excluded.date,time=excluded.time,capacity=excluded.capacity,status=excluded.status',(eid,title,description,'restaurant',date.isoformat(),start.strftime('%H:%M'),cap,status)); self.audit(con,'event.saved',eid); return {'message':'Event saved.'}
            if path=='/admin/blocks' and method=='POST':
                date=dt.date.fromisoformat(text(data,'date',10,10)).isoformat()
                if data.get('blocked',True): con.execute('INSERT OR IGNORE INTO blocked_dates VALUES(?)',(date,))
                else: con.execute('DELETE FROM blocked_dates WHERE date=?',(date,))
                self.audit(con,'date.blocked',date); return {'message':'Closed dates updated.'}
            if path=='/admin/settings' and method=='PATCH':
                allowed={'venue_name','address','phone','email','booking_minutes','tax_basis_points','ordering_enabled','max_party','hours','website_url'}
                for key,value in data.items():
                    if key not in allowed: raise Problem('Unsupported setting: '+key)
                    if key=='website_url' and value and (urlparse(str(value)).scheme not in ['http','https'] or not urlparse(str(value)).netloc): raise Problem('Website URL must begin with http:// or https://.')
                    if key in ['booking_minutes','tax_basis_points','max_party']: integer(data,key,1 if key!='tax_basis_points' else 0,360 if key=='booking_minutes' else 10000 if key=='tax_basis_points' else 20)
                    elif key=='ordering_enabled' and not isinstance(value,bool): raise Problem('Expected true or false.')
                    elif key=='hours':
                        if not isinstance(value,dict) or set(value)!=set(EXPERIENCES): raise Problem('Configure hours for all three experiences.')
                        for hours in value.values():
                            if not isinstance(hours,list) or len(hours)!=2 or not all(isinstance(v,int) for v in hours) or not 0<=hours[0]<hours[1]<=24: raise Problem('Hours must be [opening, closing] between 0 and 24.')
                    elif not isinstance(value,(str,bool,int)) or len(str(value))>500: raise Problem('Invalid setting value.')
                    con.execute('UPDATE settings SET value=? WHERE key=?',(json.dumps(value),key))
                self.audit(con,'settings.updated','venue'); return {'message':'Settings saved.'}
        raise Problem('This endpoint does not exist.',404)

def main():
    parser=argparse.ArgumentParser(); parser.add_argument('--create-admin'); parser.add_argument('--port',type=int,default=8787); parser.add_argument('--host',default='127.0.0.1')
    args=parser.parse_args(); init()
    if args.create_admin:
        password=getpass.getpass('Admin password (12+ characters): ')
        if len(password)<12: raise SystemExit('Password must contain at least 12 characters.')
        with connect() as con:
            con.execute("INSERT INTO users(id,email,name,password,role,verified) VALUES(?,?,?,?,?,1)",(secrets.token_hex(12),email(args.create_admin),'Administrator',password_hash(password),'super_admin'))
        print('Administrator created.'); return
    print(f'After Work local development API: http://127.0.0.1:{args.port}/api/health')
    ThreadingHTTPServer((args.host,args.port),Handler).serve_forever()
if __name__=='__main__': main()
