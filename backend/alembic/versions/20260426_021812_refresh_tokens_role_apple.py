"""refresh_tokens table + users.role + users.apple_user_id

Revision ID: 20260426_021812
Revises:
Create Date: 2026-04-26 02:18:12

Slice 9.4 — backend primitives for Slice 1 (auth) and Slice 10 (admin):

- Adds `refresh_tokens` table for refresh-token rotation (Slice 9.5).
- Adds `users.role` enum-like VARCHAR with CHECK ('user' | 'admin') for
  the `require_admin` dependency consumed by Slice 10.
- Adds `users.apple_user_id` (unique, nullable) for Sign in with Apple
  upsert-by-id flow used by `/api/v1/auth/apple` (Slice 9.6).
"""

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision = "20260426_021812"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    # --- refresh_tokens ---
    op.create_table(
        "refresh_tokens",
        sa.Column(
            "id",
            sa.dialects.postgresql.UUID(as_uuid=True),
            primary_key=True,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column(
            "user_id",
            sa.dialects.postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("token_hash", sa.String(length=255), nullable=False, unique=True),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("revoked_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("(NOW() AT TIME ZONE 'UTC')"),
        ),
    )
    op.create_index(
        "idx_refresh_tokens_user", "refresh_tokens", ["user_id"], unique=False
    )
    op.create_index(
        "idx_refresh_tokens_hash", "refresh_tokens", ["token_hash"], unique=False
    )

    # --- users.role + users.apple_user_id ---
    op.add_column(
        "users",
        sa.Column(
            "role",
            sa.String(length=20),
            nullable=False,
            server_default=sa.text("'user'"),
        ),
    )
    op.create_check_constraint(
        "users_role_check",
        "users",
        "role IN ('user', 'admin')",
    )

    op.add_column(
        "users",
        sa.Column("apple_user_id", sa.String(length=255), nullable=True),
    )
    op.create_unique_constraint(
        "users_apple_user_id_key", "users", ["apple_user_id"]
    )
    # Partial index speeds the lookup-by-apple_user_id upsert path while
    # tolerating the many NULLs we'll have for email-only accounts.
    op.create_index(
        "idx_users_apple",
        "users",
        ["apple_user_id"],
        unique=False,
        postgresql_where=sa.text("apple_user_id IS NOT NULL"),
    )


def downgrade() -> None:
    # Drop in reverse order; child indexes/constraints first.
    op.drop_index("idx_users_apple", table_name="users")
    op.drop_constraint("users_apple_user_id_key", "users", type_="unique")
    op.drop_column("users", "apple_user_id")

    op.drop_constraint("users_role_check", "users", type_="check")
    op.drop_column("users", "role")

    op.drop_index("idx_refresh_tokens_hash", table_name="refresh_tokens")
    op.drop_index("idx_refresh_tokens_user", table_name="refresh_tokens")
    op.drop_table("refresh_tokens")
