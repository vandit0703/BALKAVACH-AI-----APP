
import os

from dotenv import load_dotenv
from sqlalchemy import create_engine, text

# Load environment variables from .env
load_dotenv()

DATABASE_URL = os.getenv("DATABASE_URL")

if not DATABASE_URL:
    print("ERROR: DATABASE_URL not found in .env")
    raise SystemExit(1)

engine = create_engine(
    DATABASE_URL,
    pool_pre_ping=True,
    connect_args={"connect_timeout": 10},
)

try:
    print("Connecting to Neon PostgreSQL...")

    with engine.connect() as connection:
        result = connection.execute(
            text("""
                SELECT
                    current_database(),
                    current_user,
                    version()
            """)
        ).fetchone()

        print("\nSUCCESS: Database connected!")
        print("Database:", result[0])
        print("User:", result[1])
        print("Version:", result[2].split(",")[0])

        tables = connection.execute(
            text("""
                SELECT table_name
                FROM information_schema.tables
                WHERE table_schema = 'public'
                  AND table_type = 'BASE TABLE'
                ORDER BY table_name
            """)
        ).scalars().all()

        print(f"\nTotal tables found: {len(tables)}")

        if tables:
            for table in tables:
                print("  -", table)
        else:
            print("No tables found in the public schema.")

except Exception as error:
    print("\nFAILED: Database connection error.")
    print("Error:", str(error))

finally:
    engine.dispose()
