"""atomic meal-log idempotency: unique constraints on meals + meal_items

Revision ID: 20260625_000002
Revises: 20260625_000001
Create Date: 2026-06-25 00:00:02

Backend hardening (Codex review-4 #4) — make ``POST /api/v1/meals/log``
idempotency DATABASE-enforced instead of select-then-insert, which races under
concurrent offline-retry traffic:

  - ``meals``      gets UNIQUE (user_id, meal_type, meal_date) so concurrent
                   first logs for the same slot cannot create duplicate parent
                   meals.
  - ``meal_items`` gets a PARTIAL UNIQUE index on (meal_id, client_item_id)
                   WHERE client_item_id IS NOT NULL so a retried client write
                   cannot double-insert the same item, while the legacy
                   POST /meals/{id}/items route (NULL client_item_id) can still
                   add many rows.

The new partial unique index also serves the (meal_id, client_item_id)
existence lookup, so the prior non-unique single-column index
``idx_meal_items_client_item_id`` is dropped as redundant.
"""

from alembic import op

# revision identifiers, used by Alembic.
revision = "20260625_000002"
down_revision = "20260625_000001"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # meal_items: replace the non-unique single-column index with a partial
    # unique composite index that enforces per-meal client_item_id uniqueness.
    op.drop_index("idx_meal_items_client_item_id", table_name="meal_items")
    op.create_index(
        "uq_meal_items_meal_client_item",
        "meal_items",
        ["meal_id", "client_item_id"],
        unique=True,
        postgresql_where="client_item_id IS NOT NULL",
    )

    # meals: one parent meal per (user, type, day).
    op.create_unique_constraint(
        "uq_meals_user_type_date",
        "meals",
        ["user_id", "meal_type", "meal_date"],
    )


def downgrade() -> None:
    op.drop_constraint("uq_meals_user_type_date", "meals", type_="unique")
    op.drop_index("uq_meal_items_meal_client_item", table_name="meal_items")
    op.create_index(
        "idx_meal_items_client_item_id",
        "meal_items",
        ["client_item_id"],
        unique=False,
    )
