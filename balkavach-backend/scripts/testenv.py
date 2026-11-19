"""Disposable local test environment: private PostgreSQL cluster + Redis stand-in.

Nothing here ever touches a real database. The PostgreSQL cluster is created in
its own data directory (``initdb``), listens on 127.0.0.1 only, on a non-default
port, with trust authentication, and is safe to delete at any time. The Redis
service is ``fakeredis`` served over TCP so the real ``redis`` client (and its
Lua scripts) are exercised; CI uses a real Redis container instead.

Usage (from ``balkavach-backend`` with the virtualenv active)::

    python scripts/testenv.py start               # cluster + redis, create DB
    python scripts/testenv.py load-schema FILE    # load the baseline schema-only SQL
    python scripts/testenv.py migrate             # alembic upgrade head on the TEST DB
    python scripts/testenv.py test -- -q -rs      # run pytest with the right env
    python scripts/testenv.py env                 # print the variables (shell form)
    python scripts/testenv.py status | stop | reset

The baseline schema (users, families, tasks, ...) is NOT created by Alembic; it
must be loaded first with ``load-schema``. Default location the CI looks for it:
``tests/schema/baseline.sql``.
"""

from __future__ import annotations

import argparse
import os
import shutil
import signal
import subprocess
import sys
import time
from pathlib import Path

BACKEND = Path(__file__).resolve().parent.parent
PG_PORT = int(os.environ.get("BALKAVACH_TEST_PG_PORT", "55432"))
REDIS_PORT = int(os.environ.get("BALKAVACH_TEST_REDIS_PORT", "56379"))
DB_NAME = os.environ.get("BALKAVACH_TEST_DB_NAME", "balkavach_test")
HOST = "127.0.0.1"


def home() -> Path:
    custom = os.environ.get("BALKAVACH_TESTENV_DIR")
    if custom:
        return Path(custom)
    base = os.environ.get("LOCALAPPDATA") or str(Path.home())
    return Path(base) / "balkavach-testenv"


def data_dir() -> Path:
    return home() / "pgdata"


def pg_bin() -> Path:
    explicit = os.environ.get("PG_BIN")
    candidates: list[Path] = [Path(explicit)] if explicit else []
    for root in (Path("C:/Program Files/PostgreSQL"), Path("/usr/lib/postgresql")):
        if root.exists():
            candidates += sorted(root.glob("*/bin"), reverse=True)
    which = shutil.which("pg_ctl")
    if which:
        candidates.append(Path(which).parent)
    for candidate in candidates:
        if (candidate / ("pg_ctl.exe" if os.name == "nt" else "pg_ctl")).exists():
            return candidate
    raise SystemExit("PostgreSQL binaries not found. Install PostgreSQL or set PG_BIN.")


def exe(name: str) -> str:
    return str(pg_bin() / (name + (".exe" if os.name == "nt" else "")))


def test_url() -> str:
    return f"postgresql+psycopg://postgres@{HOST}:{PG_PORT}/{DB_NAME}"


def redis_url() -> str:
    return f"redis://{HOST}:{REDIS_PORT}/0"


def guard_test_target() -> None:
    """Refuse to run schema/migration commands against anything but the local test DB."""
    if "test" not in DB_NAME.casefold():
        raise SystemExit(f"Refusing: database name {DB_NAME!r} must contain 'test'.")


def run(cmd: list[str], **kwargs) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, check=True, **kwargs)


def pg_running() -> bool:
    return subprocess.run(
        [exe("pg_isready"), "-h", HOST, "-p", str(PG_PORT)], capture_output=True
    ).returncode == 0


def redis_pid_file() -> Path:
    return home() / "redis.pid"


def redis_running() -> bool:
    import socket

    try:
        with socket.create_connection((HOST, REDIS_PORT), timeout=0.5):
            return True
    except OSError:
        return False


def cmd_start(_: argparse.Namespace) -> None:
    guard_test_target()
    home().mkdir(parents=True, exist_ok=True)
    if not (data_dir() / "PG_VERSION").exists():
        run([exe("initdb"), "-D", str(data_dir()), "-U", "postgres", "-A", "trust",
             "--encoding=UTF8", "--locale=C"], stdout=subprocess.DEVNULL)
        print("initialised private cluster at", data_dir())
    if not pg_running():
        run([exe("pg_ctl"), "-D", str(data_dir()), "-l", str(home() / "postgres.log"),
             "-o", f"-p {PG_PORT} -c listen_addresses={HOST}", "-w", "start"],
            stdout=subprocess.DEVNULL)
    exists = subprocess.run(
        [exe("psql"), "-h", HOST, "-p", str(PG_PORT), "-U", "postgres", "-tAc",
         f"SELECT 1 FROM pg_database WHERE datname='{DB_NAME}'"],
        capture_output=True, text=True, check=True).stdout.strip()
    if not exists:
        run([exe("createdb"), "-h", HOST, "-p", str(PG_PORT), "-U", "postgres", DB_NAME])
    print(f"postgres: {HOST}:{PG_PORT}/{DB_NAME}")
    if not redis_running():
        creationflags = 0
        kwargs: dict = {}
        if os.name == "nt":
            kwargs["creationflags"] = 0x00000008 | 0x00000200  # DETACHED | NEW_GROUP
        else:
            kwargs["start_new_session"] = True
        proc = subprocess.Popen(
            [sys.executable, str(Path(__file__).resolve()), "_redis"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL, **kwargs)
        redis_pid_file().write_text(str(proc.pid))
        for _ in range(50):
            if redis_running():
                break
            time.sleep(0.1)
    print(f"redis (fakeredis stand-in): {redis_url()}" if redis_running() else "redis: FAILED to start")


def cmd_redis(_: argparse.Namespace) -> None:
    from fakeredis import TcpFakeServer

    server = TcpFakeServer((HOST, REDIS_PORT), server_type="redis")
    server.serve_forever()


def cmd_stop(_: argparse.Namespace) -> None:
    if pg_running():
        run([exe("pg_ctl"), "-D", str(data_dir()), "-m", "fast", "-w", "stop"], stdout=subprocess.DEVNULL)
    pid_file = redis_pid_file()
    if pid_file.exists():
        try:
            os.kill(int(pid_file.read_text()), signal.SIGTERM)
        except (OSError, ValueError):
            pass
        pid_file.unlink(missing_ok=True)
    print("stopped")


def cmd_status(_: argparse.Namespace) -> None:
    print("postgres:", "up" if pg_running() else "down", f"({HOST}:{PG_PORT}/{DB_NAME})")
    print("redis   :", "up" if redis_running() else "down", f"({redis_url()})")


def cmd_reset(_: argparse.Namespace) -> None:
    guard_test_target()
    base = [exe("psql"), "-h", HOST, "-p", str(PG_PORT), "-U", "postgres", "-v", "ON_ERROR_STOP=1", "-d", "postgres"]
    run(base + ["-c", f'DROP DATABASE IF EXISTS "{DB_NAME}" WITH (FORCE)'])
    run([exe("createdb"), "-h", HOST, "-p", str(PG_PORT), "-U", "postgres", DB_NAME])
    print("recreated", DB_NAME)


def cmd_load_schema(args: argparse.Namespace) -> None:
    guard_test_target()
    path = Path(args.file)
    if not path.is_file():
        raise SystemExit(f"Schema file not found: {path}")
    run([exe("psql"), "-h", HOST, "-p", str(PG_PORT), "-U", "postgres", "-d", DB_NAME,
         "-v", "ON_ERROR_STOP=1", "-q", "-f", str(path)])
    print("schema loaded from", path)


def test_env() -> dict[str, str]:
    env = dict(os.environ)
    env.pop("DATABASE_URL", None)  # the app URL must never be the test DB or production
    env.update({
        "TEST_DATABASE_URL": test_url(),
        "REDIS_URL": redis_url(),
        "REDIS_RATE_LIMIT_PREFIX": "balkavach-test",
        "JWT_SECRET_KEY": env.get("JWT_SECRET_KEY") or "test-only-secret-key-not-for-production-0123456789",
    })
    return env


def cmd_migrate(_: argparse.Namespace) -> None:
    guard_test_target()
    env = test_env()
    env["DATABASE_URL"] = test_url()
    env["ALLOW_SCHEMA_MIGRATIONS"] = "true"
    run([sys.executable, "-m", "alembic", "upgrade", "head"], cwd=BACKEND, env=env)


def cmd_test(args: argparse.Namespace) -> None:
    extra = [a for a in args.pytest_args if a != "--"] or ["-q", "-rs"]
    result = subprocess.run([sys.executable, "-m", "pytest", *extra], cwd=BACKEND, env=test_env())
    raise SystemExit(result.returncode)


def cmd_env(_: argparse.Namespace) -> None:
    print(f"export TEST_DATABASE_URL={test_url()}")
    print(f"export REDIS_URL={redis_url()}")
    print("export REDIS_RATE_LIMIT_PREFIX=balkavach-test")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    for name, fn in (("start", cmd_start), ("stop", cmd_stop), ("status", cmd_status),
                     ("reset", cmd_reset), ("migrate", cmd_migrate), ("env", cmd_env), ("_redis", cmd_redis)):
        sub.add_parser(name).set_defaults(fn=fn)
    load = sub.add_parser("load-schema")
    load.add_argument("file")
    load.set_defaults(fn=cmd_load_schema)
    test = sub.add_parser("test")
    test.add_argument("pytest_args", nargs=argparse.REMAINDER)
    test.set_defaults(fn=cmd_test)
    args = parser.parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()
