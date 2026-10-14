#!/usr/bin/env python3
"""
scripts/create_admin.py - Create or upgrade Admin account directly in DB.
Environment variables:
  NEON_DATABASE_URL   - PostgreSQL URL for Neon (required if --neon)
  LOCAL_DATABASE_URL  - PostgreSQL URL for local (optional, has default)
"""

import argparse
import asyncio
import os
import uuid

import asyncpg
import bcrypt

NEON_DEFAULT_URL = os.environ.get("NEON_DATABASE_URL")
LOCAL_DEFAULT_URL = os.environ.get(
    "LOCAL_DATABASE_URL",
    "postgresql://bankops:bankops@localhost:5432/bankops",
)

ROLES_TO_GRANT = ["admin", "system_admin", "approver", "staff", "auditor"]


def hash_secret(secret: str) -> str:
    return bcrypt.hashpw(secret.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")


async def create_or_update_admin(
    db_url: str,
    username: str,
    password: str,
    display_name: str,
    email: str,
    pin: str = "888888",
):
    print(f"DB: {db_url.split('@')[-1]}")
    conn = await asyncpg.connect(db_url)
    try:
        password_hash = hash_secret(password)
        pin_hash = hash_secret(pin) if pin else None

        # Find existing user by username
        row = await conn.fetchrow(
            "SELECT id FROM iam_users WHERE LOWER(username) = LOWER($1::varchar)",
            username,
        )

        if row:
            user_id = row["id"]
            print(f"Updating [id={user_id}]")
            await conn.execute(
                "UPDATE iam_users SET password_hash=$1, pin_hash=$2, display_name_demo=$3, email=$4, status='active', updated_at=NOW() WHERE id=$5",
                password_hash, pin_hash, display_name, email, user_id,
            )
        else:
            user_id = uuid.uuid4()
            print(f"Creating new user [{user_id}]")
            await conn.execute(
                "INSERT INTO iam_users (id, username, password_hash, pin_hash, status, display_name_demo, email, created_at, updated_at) VALUES ($1, $2, $3, $4, 'active', $5, $6, NOW(), NOW())",
                user_id, username, password_hash, pin_hash, display_name, email,
            )

        for role in ROLES_TO_GRANT:
            await conn.execute(
                "INSERT INTO iam_user_roles (user_id, role_code) VALUES ($1, $2) ON CONFLICT DO NOTHING",
                user_id, role,
            )
    finally:
        await conn.close()

    print("Done.")
    return user_id


def main():
    parser = argparse.ArgumentParser(description="Create/update Admin account in DB")
    parser.add_argument("--username", default="admin")
    parser.add_argument("--password", required=True, help="No default password")
    parser.add_argument("--display-name", default="System Administrator")
    parser.add_argument("--email", default="admin@bankops.local")
    parser.add_argument("--pin", default="888888")
    parser.add_argument("--neon", action="store_true")
    parser.add_argument("--local", action="store_true")

    args = parser.parse_args()

    targets = []
    if args.neon:
        if not NEON_DEFAULT_URL:
            print("ERROR: --neon specified but NEON_DATABASE_URL is not set.")
            exit(1)
        targets.append(NEON_DEFAULT_URL)
    elif args.local:
        targets.append(LOCAL_DEFAULT_URL)
    else:
        if NEON_DEFAULT_URL:
            targets.append(NEON_DEFAULT_URL)
        else:
            print("NOTE: NEON_DATABASE_URL not set, using local only.")
        targets.append(LOCAL_DEFAULT_URL)

    for db_url in targets:
        try:
            asyncio.run(create_or_update_admin(
                db_url=db_url, username=args.username, password=args.password,
                display_name=args.display_name, email=args.email, pin=args.pin,
            ))
            print(f"Success: {db_url.split('@')[-1]}")
        except Exception as e:
            print(f"Failed: {e}")


if __name__ == "__main__":
    main()