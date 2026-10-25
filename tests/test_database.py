#!/usr/bin/env python3
"""Integration checks. Run once against a fresh disposable build; tests retain their rows."""
import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone, timedelta
from decimal import Decimal
import getpass
import json
import os
from threading import Barrier
import uuid
import mysql.connector

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--disposable-db',required=True)
    args=parser.parse_args()
    db=args.disposable_db
    host=os.environ.get('DB_HOST','127.0.0.1')
    settings=dict(host=host,port=int(os.environ.get('DB_PORT','3306')),database=db,autocommit=True)
    if host not in ('127.0.0.1','localhost','::1'):
        settings.update(ssl_ca=os.environ['DB_SSL_CA'],ssl_verify_cert=True,ssl_verify_identity=True)
    adminpass=os.environ.get('DB_ADMIN_PASSWORD')
    if adminpass is None: adminpass=getpass.getpass('MySQL build account password: ')
    apppass=os.environ.get('DB_APP_PASSWORD') or getpass.getpass('MySQL application account password: ')
    def connect(admin=False):
        c=mysql.connector.connect(**settings,user=os.environ.get('DB_ADMIN_USER','root') if admin else db+'_app',password=adminpass if admin else apppass)
        q=c.cursor()
        q.execute("SET time_zone='+00:00'")
        q.execute("SET NAMES utf8mb4 COLLATE utf8mb4_0900_bin")
        q.close()
        return c
    owner=connect(True); app=connect()
    passed=0
    def query(sql,args=(),conn=app):
        c=conn.cursor(); c.execute(sql,args)
        rows=c.fetchall() if c.with_rows else []
        while c.nextset():
            if c.with_rows: c.fetchall()
        c.close(); return rows
    def one(sql,args=(),conn=app): return query(sql,args,conn)[0][0]
    def call(name,actor,*args,conn=app,when=None,context=None):
        values=(actor,when or datetime.now(timezone.utc).replace(tzinfo=None),context or str(uuid.uuid4()),*args)
        c=conn.cursor(dictionary=True)
        c.execute('CALL '+name+'('+','.join(['%s']*len(values))+')',values)
        rows=[]
        while True:
            if c.with_rows: rows.extend(c.fetchall())
            if not c.nextset(): break
        c.close(); return rows
    def check(name,condition):
        nonlocal passed
        if not condition: raise AssertionError(name)
        passed+=1; print('PASS '+name)
    def reject(name,action,codes=(1644,)):
        try: action()
        except mysql.connector.Error as exc:
            check(name,exc.errno in codes)
        else: raise AssertionError(name+' was accepted')
    def order(ref,lines,actor=4,**kwargs):
        return call('sp_place_order',actor,ref,'Recipient','1 Sample Street','Sample City',None,'00001','USA',json.dumps(lines),**kwargs)[0]
    def snapshot():
        return (query('SELECT OrderID,StatusCode FROM OrderHeader ORDER BY OrderID'),query('SELECT * FROM Inventory ORDER BY ProductID'),one('SELECT COUNT(*) FROM AuditLog'))
    try:
        check('Fresh seed: five accounts, two shipped orders, $95',one('SELECT COUNT(*) FROM UserAccount')==5 and one('SELECT COUNT(*) FROM OrderHeader')==2 and one('SELECT SUM(OrderValue) FROM v_shipped_order_value')==Decimal('95'))
        reject('T-31 runtime direct update denied',lambda:query('UPDATE Inventory SET AvailableQuantity=999 WHERE ProductID=1'),(1142,1143))
        reject('T-31 runtime audit deletion denied',lambda:query('DELETE FROM AuditLog'),(1142,1143))
        reject('T-31 private helper execute denied',lambda:query("CALL sp_append_audit(1,UTC_TIMESTAMP(6),'UPDATE','Product','1','ProductName','a','b',NULL,UUID(),NULL,NULL)"),(1370,))
        reject('T-07 administrator cannot adjust stock',lambda:call('sp_adjust_stock',1,1,'1','Invalid actor','forbidden'))
        reject('T-03 normalized duplicate product code',lambda:call('sp_create_product',2,' p020 ','Duplicate','1.00','3'),(1062,))
        reject('T-11 overprecision price',lambda:call('sp_create_product',2,'BADPRICE','Bad','1.001','3'))
        reject('T-11 fractional stock adjustment',lambda:call('sp_adjust_stock',2,1,'1.5','Fraction','fraction'))
        reject('T-05 invalid boolean',lambda:call('sp_update_product',2,1,'Lamp','20.00','3','2'))
        reject('T-04 blank product name',lambda:call('sp_create_product',2,'BLANK',' ','1','3'))
        reject('T-05 overlength text',lambda:call('sp_create_product',2,'LONG','x'*151,'1','3'))
        initial=one('SELECT AvailableQuantity FROM Inventory WHERE ProductID=1')
        a=call('sp_adjust_stock',2,1,'2','Count correction','test-adjust')[0]
        count=one('SELECT COUNT(*) FROM AuditLog')
        b=call('sp_adjust_stock',2,1,'2','Count correction','test-adjust')[0]
        check('T-17/T-33 adjustment replay is unchanged',a['BeforeQuantity']==initial and a['AfterQuantity']==initial+2 and b['Replayed']==1 and one('SELECT COUNT(*) FROM AuditLog')==count)
        reject('T-34 changed adjustment reference',lambda:call('sp_adjust_stock',2,1,'3','Count correction','test-adjust'))
        reject('T-34 NULL product cannot replay adjustment',lambda:call('sp_adjust_stock',2,None,'2','Count correction','test-adjust'))
        call('sp_adjust_stock',3,1,'1','Other staff','test-adjust')
        check('T-35 adjustment reference is scoped',one("SELECT COUNT(*) FROM AuditLog WHERE AdjustmentReference='test-adjust'")==2)
        reject('T-18 negative stock',lambda:call('sp_adjust_stock',2,1,'-9999','Invalid','negative'))
        before=snapshot()
        reject('T-12 empty order',lambda:order('empty',[]))
        reject('T-13 duplicate product',lambda:order('duplicate',[{'product_id':1,'quantity':1},{'product_id':1,'quantity':2}]))
        reject('T-11 fractional quantity',lambda:order('fractional',[{'product_id':1,'quantity':1.5}]))
        reject('T-14/T-19 later line failure',lambda:order('rollback',[{'product_id':1,'quantity':1},{'product_id':2,'quantity':9999}]))
        check('T-19 entire failed order and audits rolled back',snapshot()==before)
        r=order('retryable',[{'product_id':1,'quantity':2},{'product_id':2,'quantity':1}]); oid=r['OrderID']
        check('T-10 accepted $55 order',r['OrderValue']==Decimal('55') and r['InitialStatus']=='PENDING')
        call('sp_update_product',2,1,'Renamed Lamp','21.00','3','1')
        before=snapshot()
        replay=order('retryable',[{'product_id':2,'quantity':1},{'product_id':1,'quantity':2}])
        check('T-15/T-33 replay uses accepted price and unordered lines',replay['OrderID']==oid and replay['OrderValue']==Decimal('55') and replay['Replayed']==1 and snapshot()==before)
        reject('T-34 changed order reference',lambda:order('retryable',[{'product_id':1,'quantity':1}]))
        reject('T-22 skip readiness',lambda:call('sp_dispatch_order',2,oid,'Carrier','TRACK'))
        call('sp_mark_ready',2,oid)
        reject('T-25 early dispatch timestamp',lambda:call('sp_dispatch_order',2,oid,'Carrier','TRACK',when=datetime.now(timezone.utc).replace(tzinfo=None)-timedelta(days=1)))
        stock=query('SELECT * FROM Inventory ORDER BY ProductID')
        call('sp_dispatch_order',2,oid,'Carrier','TRACK')
        check('T-23 trigger ships without stock change',one('SELECT StatusCode FROM OrderHeader WHERE OrderID=%s',(oid,))=='SHIPPED' and query('SELECT * FROM Inventory ORDER BY ProductID')==stock)
        reject('T-24 duplicate shipment',lambda:call('sp_dispatch_order',2,oid,'Carrier','TRACK'))
        reject('T-28 shipped cancellation',lambda:call('sp_cancel_order',2,oid,'Invalid'))
        dispatched=one('SELECT DispatchedAt FROM Shipment WHERE OrderID=%s',(oid,))
        call('sp_correct_tracking',2,oid,'Carrier','CORRECTED','Tracking typo')
        check('T-29 tracking correction retains dispatch time',one('SELECT DispatchedAt FROM Shipment WHERE OrderID=%s',(oid,))==dispatched and one("SELECT COUNT(*) FROM AuditLog WHERE OrderID=%s AND EventType='TRACKING_CORRECTED'",(oid,))==1)
        stock=query('SELECT * FROM Inventory ORDER BY ProductID')
        cancel=order('cancel',[{'product_id':1,'quantity':2}])['OrderID']
        call('sp_cancel_order',2,cancel,'Customer requested correction')
        check('T-26 cancellation restores stock',query('SELECT * FROM Inventory ORDER BY ProductID')==stock)
        before=snapshot()
        reject('T-27 repeat cancellation',lambda:call('sp_cancel_order',2,cancel,'Again'))
        check('T-27 no repeated stock/audit change',snapshot()==before)
        # An injected audit error must undo all related business changes.
        query("CREATE TRIGGER test_audit_failure BEFORE INSERT ON AuditLog FOR EACH ROW SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='test:audit_failure'",conn=owner)
        before=snapshot()
        try: reject('T-20 audit failure',lambda:order('audit-fail',[{'product_id':1,'quantity':1}]))
        finally: query('DROP TRIGGER test_audit_failure',conn=owner)
        check('T-20 audit failure rolls back business data',snapshot()==before)
        success=order('audit-fail',[{'product_id':1,'quantity':1}])
        check('T-36 failed reference can be retried',success['Replayed']==0)
        # Two different customers compete for a new product with one unit.
        prod=call('sp_create_product',2,'LAST','Last unit','1.00','0')[0]['ProductID']
        call('sp_adjust_stock',2,prod,'1','Concurrency fixture','last-stock')
        barrier=Barrier(2)
        def compete(actor):
            c=connect()
            try:
                barrier.wait(timeout=10)
                try: order('same-reference',[{'product_id':prod,'quantity':1}],actor=actor,conn=c); return 'accepted'
                except mysql.connector.Error as e:
                    if e.errno==1644 and 'insufficient_stock' in e.msg: return 'rejected'
                    raise
            finally: c.close()
        with ThreadPoolExecutor(max_workers=2) as pool:
            results=list(pool.map(compete,[4,5]))
        check('T-37 competing orders cannot oversell',sorted(results)==['accepted','rejected'] and one('SELECT AvailableQuantity FROM Inventory WHERE ProductID=%s',(prod,))==0)
        raced=order('terminal-race',[{'product_id':1,'quantity':1}])['OrderID']
        call('sp_mark_ready',2,raced)
        barrier=Barrier(2)
        def terminal(action):
            c=connect()
            try:
                barrier.wait(timeout=10)
                try:
                    if action=='dispatch': call('sp_dispatch_order',2,raced,'Carrier','RACE',conn=c)
                    else: call('sp_cancel_order',3,raced,'Race fixture',conn=c)
                    return 'accepted'
                except mysql.connector.Error as e:
                    if e.errno==1644 and 'conflict:status' in e.msg: return 'rejected'
                    raise
            finally: c.close()
        with ThreadPoolExecutor(max_workers=2) as pool:
            results=list(pool.map(terminal,['dispatch','cancel']))
        check('T-39 dispatch and cancellation serialize',sorted(results)==['accepted','rejected'])
        # Terminating a session must roll back its business and audit writes together.
        victim=connect(True)
        context=str(uuid.uuid4())
        before=snapshot()
        victim.start_transaction()
        old=one('SELECT AvailableQuantity FROM Inventory WHERE ProductID=1 FOR UPDATE',conn=victim)
        query('UPDATE Inventory SET AvailableQuantity=AvailableQuantity+1 WHERE ProductID=1',conn=victim)
        query("CALL sp_append_audit(2,UTC_TIMESTAMP(6),'STOCK_ADJUSTED','Inventory','1','AvailableQuantity',%s,%s,'Kill fixture',%s,NULL,%s)",(str(old),str(old+1),context,context),conn=victim)
        # Consume the CALL status result before terminating the connection.
        ident=victim.connection_id
        query('KILL CONNECTION '+str(ident),conn=owner)
        try: victim.close()
        except mysql.connector.Error: pass
        query('START TRANSACTION',conn=owner)
        query('SELECT AvailableQuantity FROM Inventory WHERE ProductID=1 FOR UPDATE',conn=owner)
        query('COMMIT',conn=owner)
        check('T-32 session termination rolls back stock and audit',snapshot()==before)
        # Direct constraint probes use the build identity only in this disposable database.
        reject('T-01 primary key',lambda:query("INSERT INTO Role VALUES('CUSTOMER','Duplicate')",conn=owner),(1062,))
        reject('T-02 foreign key',lambda:query('INSERT INTO Inventory VALUES(4294967295,0,0)',conn=owner),(1452,))
        reject('T-04 NOT NULL',lambda:query('UPDATE Product SET ProductName=NULL WHERE ProductID=1',conn=owner),(1048,))
        reject('T-05 CHECK',lambda:query('UPDATE Inventory SET AvailableQuantity=-1 WHERE ProductID=1',conn=owner),(3819,))
        call('sp_update_account',1,3,'Second Staff','staff2@example.invalid','0',None)
        reject('T-08 inactive staff cannot mutate',lambda:call('sp_adjust_stock',3,1,'1','Inactive','inactive'))
        call('sp_update_account',1,3,'Second Staff','staff2@example.invalid','01',None)
        check('Activation audit uses normalized boolean',one("SELECT EventType FROM AuditLog WHERE EntityName='UserAccount' AND RecordKey='3' AND FieldName='IsActive' ORDER BY AuditID DESC LIMIT 1")=='ACTIVATE')
        check('Final required-child and shipment consistency',one("SELECT COUNT(*) FROM OrderHeader h LEFT JOIN Shipment s ON s.OrderID=h.OrderID WHERE (h.StatusCode='SHIPPED')<>(s.OrderID IS NOT NULL)")==0 and one('SELECT COUNT(*) FROM OrderHeader h WHERE NOT EXISTS(SELECT 1 FROM OrderLine l WHERE l.OrderID=h.OrderID)')==0)
        print(f'{passed} checks passed on MySQL '+one('SELECT VERSION()'))
    finally:
        app.close(); owner.close()

if __name__=='__main__': main()
