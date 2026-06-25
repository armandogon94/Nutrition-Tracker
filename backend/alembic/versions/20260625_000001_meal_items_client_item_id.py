"""meal_items.client_item_id for idempotent meal logging

Revision ID: 20260625_000001
Revises: 20260426_021812
Create Date: 2026-06-25 00:00:01

Backend hardening — adds a nullable client-generated identifier to
``meal_items`` so ``POST /api/v1/meals/log`` (the iOS MealService contract)
can dedupe retried offline writes idempotently on (meal_id, client_item_id).
Indexed for the per-meal lookup; nullable because items added through the
legacy ``POST /meals/{id}/items`` route do not carry one.
"""

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision = "20260625_000001"
down_revision = "20260426_021812"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "meal_items",
        sa.Column("client_item_id", sa.String(length=64), nullable=True),
    )
    op.create_index(
        "idx_meal_items_client_item_id",
        "meal_items",
        ["client_item_id"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index("idx_meal_items_client_item_id", table_name="meal_items")
    op.drop_column("meal_items", "client_item_id")
