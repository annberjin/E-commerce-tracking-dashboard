#!/usr/bin/env python3
"""Build an exact Git tag into a fresh MySQL database. Never drops a database."""
import argparse
import datetime as dt
import getpass
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import uuid

SESSION = "SET NAMES utf8mb4 COLLATE utf8mb4_0900_bin; SET time_zone='+00:00'; SET SESSION sql_mode='STRICT_TRANS_TABLES,ONLY_FULL_GROUP_BY,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION'; SET autocommit=1;\n"
EXPECTED = [
    'database/00_create_database.sql',
    'database/01_schema/010_reference_tables.sql',
    'database/01_schema/020_core_tables.sql',
    'database/01_schema/030_relationship_tables.sql',
    'database/02_programmability/010_views.sql',
    'database/02_programmability/030_procedures.sql',
    'database/02_programmability/040_triggers.sql',
    'database/03_security/010_grants.sql',
    'database/04_seed/010_reference_data.sql',
    'database/04_seed/020_sample_data.sql',
    'database/05_validation/010_object_validation.sql',
    'database/05_validation/020_data_validation.sql',
    'database/05_validation/030_smoke_tests.sql',
]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('owner')
    parser.add_argument('repository')
    parser.add_argument('tag')
    parser.add_argument('database')
    parser.add_argument('--source', help='Existing local Git repository containing the release tag.')
    args = parser.parse_args()
    os.umask(0o077)
    run = dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%SZ')+'-'+uuid.uuid4().hex[:8]
    work = Path(os.environ.get('BUILD_WORK_DIR', '.build-work')).resolve()/run
    work.mkdir(parents=True)
    logfile = work/'build.log'
    secrets = []

    def redact(message):
        for secret in secrets:
            if secret:
                message = message.replace(secret, '[redacted]')
        return message

    def log(message):
        message = redact(message)
        line = dt.datetime.now(dt.timezone.utc).isoformat()+' | '+message
        with logfile.open('a') as f:
            f.write(line+'\n')
        print(line)

    def command(cmd):
        result = subprocess.run(cmd, text=True, capture_output=True)
        if result.returncode:
            raise RuntimeError('Source retrieval or tag verification failed; check repository access and the exact tag.')
        return result.stdout.strip()

    try:
        log('START tag='+args.tag+' database='+args.database)
        if not re.fullmatch(r'[A-Za-z][A-Za-z0-9_]{0,19}', args.database):
            raise ValueError('Database name must start with a letter and use at most 20 letters, digits or underscores.')
        if not all(re.fullmatch(r'[A-Za-z0-9_.-]+', x) and not x.startswith('-') for x in (args.owner,args.repository,args.tag)):
            raise ValueError('Invalid owner, repository or tag.')
        if len(args.tag)>100:
            raise ValueError('Tag is too long.')
        for tool in ('git','mysql'):
            if not shutil.which(tool):
                raise RuntimeError('Required tool missing: '+tool)
        from werkzeug.security import generate_password_hash
        client = command(['mysql','--version'])
        if not re.search(r'\b8\.4\.', client):
            raise RuntimeError('Use the MySQL 8.4 client.')
        host = os.environ.get('DB_HOST','127.0.0.1')
        port = int(os.environ.get('DB_PORT','3306'))
        admin = os.environ.get('DB_ADMIN_USER','root')
        admin_password = os.environ.get('DB_ADMIN_PASSWORD')
        if admin_password is None:
            admin_password = getpass.getpass('MySQL build account password: ')
        app_password = os.environ.get('DB_APP_PASSWORD') or getpass.getpass('New MySQL application account password: ')
        admin_login_password = os.environ.get('APP_ADMIN_PASSWORD') or getpass.getpass('Initial dashboard administrator password: ')
        demo_password = os.environ.get('DEMO_PASSWORD') or getpass.getpass('Fictional staff/customer password: ')
        if not all((app_password,admin_login_password,demo_password)):
            raise ValueError('New account passwords must not be empty.')
        secrets.extend([admin_password,app_password,admin_login_password,demo_password])
        apphost = os.environ.get('DB_APP_HOST','localhost')
        if not re.fullmatch(r'[A-Za-z0-9_.:-]+', apphost):
            raise ValueError('DB_APP_HOST must be a specific hostname or IP address.')
        db = args.database
        definer,appuser,role = db+'_definer',db+'_app',db+'_app_runtime'
        # A private MySQL option file keeps credentials out of command arguments.
        def option(value):
            return '"'+str(value).replace('\\','\\\\').replace('"','\\"').replace('\n','\\n').replace('\r','\\r')+'"'
        with tempfile.TemporaryDirectory(prefix='mysql-build-') as private:
            cfg = Path(private)/'client.cnf'
            cfg.write_text('[client]\nuser='+option(admin)+'\npassword='+option(admin_password)+'\nhost='+option(host)+'\nport='+str(port)+'\nprotocol=TCP\n')
            cfg.chmod(0o600)
            tls = []
            if host not in ('127.0.0.1','localhost','::1'):
                ca = os.environ.get('DB_SSL_CA')
                if not ca:
                    raise ValueError('Set DB_SSL_CA for a non-local MySQL connection.')
                tls = ['--ssl-mode=VERIFY_IDENTITY','--ssl-ca='+ca]

            def sql(statement, use_db=True, record=False):
                cmd = ['mysql','--defaults-file='+str(cfg),'--no-login-paths','--batch','--raw','--skip-column-names','--binary-mode','--connect-timeout=10']+tls
                if use_db:
                    cmd.append('--database='+db)
                result = subprocess.run(cmd,input=SESSION+statement,text=True,capture_output=True)
                if result.returncode:
                    # Keep the diagnostic line, redact secrets, and omit echoed SQL.
                    match = re.search(r'^ERROR \d+ \([A-Z0-9]+\)(?: at line \d+)?:[^\r\n]*',redact(result.stderr),re.MULTILINE)
                    category = match.group(0) if match else 'MySQL client/connection error'
                    raise RuntimeError(category)
                if record and result.stdout.strip():
                    log(result.stdout.strip())
                return result.stdout.strip()

            version = sql('SELECT VERSION();',False)
            if not version.startswith('8.4.'):
                raise RuntimeError('Use MySQL 8.4; found '+version)
            log('MySQL server='+version+'; client='+client)
            if sql("SELECT @@innodb_flush_log_at_trx_commit;",False)!='1':
                raise RuntimeError('Set innodb_flush_log_at_trx_commit=1.')
            if sql('SELECT IF(@@log_bin=1,@@sync_binlog=1,1);',False)!='1':
                raise RuntimeError('Set sync_binlog=1 when binary logging is enabled.')
            origin = str(Path(args.source).resolve()) if args.source else f'https://github.com/{args.owner}/{args.repository}.git'
            repo = work/'repo'
            command(['git','clone','--quiet','--no-checkout',origin,str(repo)])
            command(['git','-C',str(repo),'checkout','--quiet','--detach','refs/tags/'+args.tag])
            resolved = command(['git','-C',str(repo),'describe','--exact-match','--tags','--match',args.tag,'HEAD'])
            if resolved!=args.tag:
                raise RuntimeError('Checkout does not match the requested tag.')
            sha = command(['git','-C',str(repo),'rev-parse','HEAD'])
            log('Verified tag='+resolved+' commit='+sha)
            manifest = repo/'database/manifest.txt'
            entries = [x.strip() for x in manifest.read_text().splitlines() if x.strip() and not x.lstrip().startswith('#')]
            if entries!=EXPECTED:
                raise RuntimeError('Manifest is empty, duplicated, unsafe, missing entries or out of dependency order.')
            for entry in entries:
                path = repo/entry
                if not path.is_file() or path.is_symlink() or not path.resolve().is_relative_to(repo.resolve()):
                    raise RuntimeError('Invalid or missing manifest file: '+entry)
            if sql(f"SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name='{db}';",False)!='0':
                raise RuntimeError('Database already exists. Choose a fresh database name; existing data was not changed.')
            if sql(f"SELECT COUNT(*) FROM mysql.user WHERE User IN ('{definer}','{appuser}','{role}');",False)!='0':
                raise RuntimeError('A generated MySQL identity already exists. Choose a fresh database name.')
            password_sql=app_password.replace('\\','\\\\').replace("'","''")
            values={'DB':db,'DEFINER':definer,'APP_USER':appuser,'APP_HOST':apphost,'RUNTIME_ROLE':role,
                    'APP_PASSWORD_SQL':password_sql,
                    'ADMIN_HASH':generate_password_hash(admin_login_password,method='scrypt'),
                    'DEMO_HASH':generate_password_hash(demo_password,method='scrypt')}
            secrets.extend([password_sql,values['ADMIN_HASH'],values['DEMO_HASH']])
            def render(text):
                def token(match):
                    if match.group(1) not in values:
                        raise RuntimeError('Unknown SQL template token.')
                    return values[match.group(1)]
                return re.sub(r'\{\{([A-Z_]+)\}\}',token,text)
            # Resolve every template before the first database mutation.
            scripts=[render((repo/x).read_text()) for x in entries]
            build_ready=False
            for index,(entry,script) in enumerate(zip(entries,scripts)):
                log('START '+entry)
                started=dt.datetime.now(dt.timezone.utc).strftime('%Y-%m-%d %H:%M:%S.%f')
                build_id=None
                start_log=f"INSERT INTO BuildLog(RunID,VersionTag,CommitSHA,ScriptPath,StartedAt,Outcome) VALUES('{run}','{args.tag}','{sha}','{entry}','{started}','STARTED'); SELECT LAST_INSERT_ID();"
                if build_ready:
                    build_id=sql(start_log)
                try:
                    sql(script,use_db=index!=0,record=True)
                    if index==0:
                        build_ready=True
                        build_id=sql(start_log)
                    sql(f"UPDATE BuildLog SET FinishedAt=UTC_TIMESTAMP(6),Outcome='SUCCEEDED' WHERE BuildID={int(build_id)};")
                    log('PASS '+entry)
                except Exception as exc:
                    try:
                        if build_id is None:
                            build_id=sql(start_log)
                        safe=redact(str(exc))[:255].replace('\\','\\\\').replace("'","''")
                        sql(f"UPDATE BuildLog SET FinishedAt=UTC_TIMESTAMP(6),Outcome='FAILED',ErrorMessage='{safe}' WHERE BuildID={int(build_id)};")
                    except Exception:
                        log('Database build logging unavailable; file log retained.')
                    raise
            log('BUILD SUCCEEDED; application database user='+appuser+'; role='+role)
            log('Log file: '+str(logfile))
    except Exception as exc:
        log('BUILD FAILED: '+str(exc))
        log('Log file: '+str(logfile))
        return 1
    return 0

if __name__=='__main__':
    raise SystemExit(main())
