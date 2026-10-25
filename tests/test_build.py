#!/usr/bin/env python3
"""Check failed builds against a local release tag and an existing disposable database."""
import argparse
import getpass
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import uuid
import mysql.connector

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--source',required=True)
    p.add_argument('--tag',required=True)
    p.add_argument('--disposable-db',required=True)
    a=p.parse_args()
    env=os.environ.copy()
    for key,prompt in [('DB_ADMIN_PASSWORD','MySQL build password'),('DB_APP_PASSWORD','MySQL application password'),('APP_ADMIN_PASSWORD','Dashboard administrator password'),('DEMO_PASSWORD','Fictional account password')]:
        if key not in env: env[key]=getpass.getpass(prompt+': ')
    host=env.get('DB_HOST','127.0.0.1')
    settings=dict(host=host,port=int(env.get('DB_PORT','3306')),user=env.get('DB_ADMIN_USER','root'),password=env['DB_ADMIN_PASSWORD'],autocommit=True)
    if host not in ('127.0.0.1','localhost','::1'):
        settings.update(ssl_ca=env['DB_SSL_CA'],ssl_verify_cert=True,ssl_verify_identity=True)
    cn=mysql.connector.connect(**settings)
    def scalar(sql,params=()):
        c=cn.cursor();c.execute(sql,params);v=c.fetchone()[0];c.close();return v
    if scalar('SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name=%s',(a.disposable_db,))!=1:
        raise RuntimeError('Build the disposable database first.')
    if not a.disposable_db.replace('_','').isalnum(): raise ValueError('Invalid database name')
    builder=Path(__file__).resolve().parents[1]/'build/build_database.py'
    passed=0
    with tempfile.TemporaryDirectory(prefix='build-check-') as temp:
        repo=Path(temp)/'repo'
        def git(*args):
            r=subprocess.run(['git','-C',str(repo),*args],text=True,capture_output=True)
            if r.returncode: raise RuntimeError('Local Git fixture failed')
            return r.stdout.strip()
        subprocess.run(['git','clone','--quiet',str(Path(a.source).resolve()),str(repo)],check=True)
        git('checkout','--quiet','--detach','refs/tags/'+a.tag)
        git('config','user.name','Build Test');git('config','user.email','build-test@example.invalid')
        env['BUILD_WORK_DIR']=str(Path(temp)/'runs')
        def expect_failure(tag,db,label,needle):
            nonlocal passed
            old_logs=set(Path(env['BUILD_WORK_DIR']).glob('*/build.log'))
            r=subprocess.run([sys.executable,str(builder),'local','fixture',tag,db,'--source',str(repo)],env=env,text=True,capture_output=True)
            if r.returncode==0 or needle not in r.stdout: raise AssertionError(label+' did not fail as expected')
            new_logs=set(Path(env['BUILD_WORK_DIR']).glob('*/build.log'))-old_logs
            if len(new_logs)!=1: raise AssertionError('Expected one build log')
            log_text=new_logs.pop().read_text()
            if needle not in log_text: raise AssertionError('Failure diagnostic missing from file log')
            for key in ('DB_ADMIN_PASSWORD','DB_APP_PASSWORD','APP_ADMIN_PASSWORD','DEMO_PASSWORD'):
                if env[key] and env[key] in r.stdout+r.stderr+log_text: raise AssertionError('Secret appeared in build output')
            passed+=1;print('PASS '+label)
        def fresh(): return 'bt_'+uuid.uuid4().hex[:12]
        def absent(db):
            if scalar('SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name=%s',(db,)):
                raise AssertionError('Invalid build changed the database')
        before=scalar(f'SELECT COUNT(*) FROM `{a.disposable_db}`.AuditLog')
        expect_failure(a.tag,a.disposable_db,'T-48 existing database protected','Database already exists')
        if scalar(f'SELECT COUNT(*) FROM `{a.disposable_db}`.AuditLog')!=before:
            raise AssertionError('Existing database changed')
        git('tag','-am','Additional label on the same commit','alias-'+uuid.uuid4().hex[:8])
        expect_failure(a.tag,a.disposable_db,'T-48 requested tag accepted among aliases','Database already exists')
        db=fresh();expect_failure('missing-'+uuid.uuid4().hex[:8],db,'T-48 missing tag','tag verification failed');absent(db)
        manifest=repo/'database/manifest.txt';original=manifest.read_text()
        mutations=[('empty',''),('duplicate',original+original),('order','\n'.join(reversed(original.splitlines()))),('traversal',original+'\n../outside.sql\n')]
        for label,text in mutations:
            git('checkout','--quiet','--detach','refs/tags/'+a.tag)
            manifest.write_text(text);git('add','.');git('commit','-qm','Invalid manifest fixture')
            tag='bad-'+label;git('tag',tag)
            db=fresh();expect_failure(tag,db,'T-48 '+label+' manifest','Manifest is');absent(db)
        git('checkout','--quiet','--detach','refs/tags/'+a.tag)
        (repo/'database/01_schema/010_reference_tables.sql').unlink()
        git('add','.');git('commit','-qm','Missing script fixture');git('tag','bad-missing-script')
        db=fresh();expect_failure('bad-missing-script',db,'T-48 missing script','Invalid or missing manifest file');absent(db)
        git('checkout','--quiet','--detach','refs/tags/'+a.tag)
        script=repo/'database/01_schema/010_reference_tables.sql'
        script.write_text(script.read_text()+"\nSIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='validation:test_failure';\n")
        git('add','.');git('commit','-qm','SQL failure fixture');git('tag','bad-sql')
        db=fresh();expect_failure('bad-sql',db,'T-48 SQL failure stops build with diagnostic','validation:test_failure')
        if scalar(f"SELECT COUNT(*) FROM `{db}`.BuildLog WHERE Outcome='FAILED' AND ErrorMessage LIKE '%validation:test_failure%'")!=1:
            raise AssertionError('Failed script diagnostic was not logged')
        if scalar('SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=%s AND table_name=%s',(db,'Product')):
            raise AssertionError('A later script ran after failure')
        print('Partial failed build retained for inspection: '+db)
        git('checkout','--quiet','--detach','refs/tags/'+a.tag)
        script=repo/'database/00_create_database.sql'
        script.write_text(script.read_text().replace("CREATE USER '{{DEFINER}}'", "SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='validation:setup_failure';\nCREATE USER '{{DEFINER}}'",1))
        git('add','.');git('commit','-qm','Initial setup failure fixture');git('tag','bad-setup')
        db=fresh();expect_failure('bad-setup',db,'T-48 initial setup failure logged','validation:setup_failure')
        if scalar(f"SELECT COUNT(*) FROM `{db}`.BuildLog WHERE ScriptPath='database/00_create_database.sql' AND Outcome='FAILED' AND ErrorMessage LIKE '%validation:setup_failure%'")!=1:
            raise AssertionError('Initial setup failure was not logged')
        if scalar('SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=%s AND table_name=%s',(db,'Role')):
            raise AssertionError('A later script ran after setup failure')
        print('Partial failed build retained for inspection: '+db)
    cn.close()
    print(f'{passed} build safety checks passed')

if __name__=='__main__': main()
