import concurrent.futures
import datetime as dt
import json
import tempfile
import threading
import unittest
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen
import app

class ServiceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp=tempfile.TemporaryDirectory(); app.DB=str(Path(cls.temp.name)/'test.sqlite3'); app.init()
        with app.connect() as con:
            con.execute("INSERT INTO users(id,email,name,password,role) VALUES(?,?,?,?,?)",('admin-test','admin@example.com','Admin',app.password_hash('admin-test-password'),'super_admin'))
        cls.server=app.ThreadingHTTPServer(('127.0.0.1',0),app.Handler)
        cls.url=f'http://127.0.0.1:{cls.server.server_port}/api'
        threading.Thread(target=cls.server.serve_forever,daemon=True).start()
    @classmethod
    def tearDownClass(cls): cls.server.shutdown(); cls.server.server_close(); cls.temp.cleanup()
    def call(self,path,data=None,method=None,token=None):
        headers={'Content-Type':'application/json'}
        if token: headers['Authorization']='Bearer '+token
        req=Request(self.url+path,data=json.dumps(data).encode() if data is not None else None,headers=headers,method=method or ('POST' if data is not None else 'GET'))
        try:
            with urlopen(req) as response: return response.status,json.load(response)
        except HTTPError as ex: return ex.code,json.load(ex)
    def booking(self,day=1):
        return {'experience':'Restaurant','date':(dt.datetime.now(app.TZ).date()+dt.timedelta(days=day)).isoformat(),'party':8,'area':'Indoor','time':'12:00','name':'Test Guest','email':'guest@example.com','phone':'012345678','notes':''}
    def test_atomic_booking_prevents_conflict(self):
        booking=self.booking()
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            results=list(pool.map(lambda _:self.call('/reservations',booking),range(2)))
        self.assertEqual(sorted(r[0] for r in results),[200,409])
        record=next(r[1] for r in results if r[0]==200)
        status,_=self.call('/reservations/'+record['id']);self.assertEqual(status,403)
        status,value=self.call('/reservations/'+record['id']+'?access_token='+record['access_token']);self.assertEqual(status,200);self.assertEqual(value['party'],8)
        self.assertEqual(self.call('/reservations/'+record['id'],{'access_token':record['access_token'],'status':'cancelled'},'PATCH')[0],200)
    def test_past_rejected(self):
        b=self.booking(-1);self.assertEqual(self.call('/reservations',b)[0],400)
    def test_closed_date(self):
        b=self.booking(3)
        with app.connect() as con: con.execute('INSERT INTO blocked_dates VALUES(?)',(b['date'],))
        self.assertEqual(self.call('/availability',b)[1]['slots'],[])
    def test_server_prices_and_unpaid_status(self):
        order={'table_id':'T03','request_key':'test-checkout-123','name':'Test Guest','email':'order@example.com','notes':'','items':[{'id':'berry','quantity':2,'unit_price':1}]}
        self.assertEqual(self.call('/orders',order)[0],409)
        order['items'][0]['unit_price']=1200
        status,value=self.call('/orders',order);self.assertEqual(status,200);self.assertEqual(value['total'],2400);self.assertEqual(value['payment_status'],'unpaid')
        self.assertEqual(self.call('/orders',order)[1]['id'],value['id'])
        self.assertEqual(self.call('/orders/'+value['id'])[0],403)
        saved=self.call('/orders/'+value['id']+'?access_token='+value['access_token'])[1]
        self.assertEqual(saved['order']['table_id'],'T03')
    def test_accounts_and_admin_authorization(self):
        data={'name':'Test Customer','email':'customer@example.com','password':'a-long-test-password'}
        self.assertEqual(self.call('/auth/register',data)[0],200)
        status,login=self.call('/auth/login',data);self.assertEqual(status,200)
        self.assertEqual(self.call('/me',token=login['token'])[0],200)
        self.assertEqual(self.call('/admin/overview',token=login['token'])[0],403)
        self.assertEqual(self.call('/admin/overview')[0],401)
        self.call('/auth/logout',{},token=login['token'])
        self.assertEqual(self.call('/me',token=login['token'])[0],401)
    def test_admin_edit_updates_public_menu(self):
        login=self.call('/auth/login',{'email':'admin@example.com','password':'admin-test-password'})[1]
        token=login['token']
        status,overview=self.call('/admin/overview',token=token);self.assertEqual(status,200)
        item=next(i for i in overview['menu'] if i['id']=='coffee');item['price']=525
        self.assertEqual(self.call('/admin/menu',item,token=token)[0],200)
        public=self.call('/menu')[1]['items']
        self.assertEqual(next(i for i in public if i['id']=='coffee')['price'],525)
        with app.connect() as con:
            self.assertGreater(con.execute("SELECT COUNT(*) FROM audit WHERE action='menu.saved'").fetchone()[0],0)

    def test_event_capacity(self):
        day=(dt.datetime.now(app.TZ).date()+dt.timedelta(days=7)).isoformat()
        with app.connect() as con: con.execute('INSERT INTO events VALUES(?,?,?,?,?,?,?,?)',('test-event','Workshop','Test','coffee',day,'12:00',1,'published'))
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            results=list(pool.map(lambda i:self.call('/events/register',{'event_id':'test-event','name':'Test Guest','email':f'event{i}@example.com'}),range(2)))
        self.assertEqual(sorted(r[0] for r in results),[200,409])
    def test_newsletter_consent(self):
        self.assertEqual(self.call('/newsletter',{'email':'news@example.com','consent':False})[0],400)
        status,value=self.call('/newsletter',{'email':'news@example.com','consent':True});self.assertEqual(status,200)
        self.assertEqual(self.call('/newsletter/unsubscribe',{'token':value['unsubscribe_token']})[0],200)
    def test_five_distinct_qr_tables_and_add_more(self):
        response=self.call('/tables')[1]
        self.assertEqual([t['id'] for t in response['tables']],['T01','T02','T03','T04','T05'])
        for i in range(1,6):
            table=self.call(f'/tables/T{i:02}')[1]
            self.assertEqual(table['name'],f'Table {i:02}')
        self.assertEqual(self.call('/tables/not-a-table')[0],404)
        payload={'id':'T06','name':'Table 06','seats':4,'experience':'Restaurant','area':'Indoor','active':True}
        self.assertEqual(self.call('/admin/tables',payload)[0],401)
        login=self.call('/auth/login',{'email':'admin@example.com','password':'admin-test-password'})[1]
        token=login['token']
        self.assertEqual(self.call('/admin/tables',payload,token=token)[0],200)
        self.assertEqual(self.call('/admin/tables',payload,token=token)[0],409)
        self.assertEqual(self.call('/tables/T06')[1]['name'],'Table 06')
        payload['active']=False
        self.assertEqual(self.call('/admin/tables',payload,'PATCH',token=token)[0],200)
        self.assertEqual(self.call('/tables/T06')[0],404)
        # Additional tables survive initialization and are not silently removed.
        app.init()
        with app.connect() as con:
            self.assertEqual(con.execute("SELECT COUNT(*) FROM tables_config WHERE id='T06'").fetchone()[0],1)
            con.execute("DELETE FROM tables_config WHERE id='T06'")

    def test_persistence(self):
        with app.connect() as con: count=con.execute('SELECT COUNT(*) FROM menu').fetchone()[0]
        app.init()
        with app.connect() as con: self.assertEqual(con.execute('SELECT COUNT(*) FROM menu').fetchone()[0],count)

if __name__=='__main__': unittest.main()
