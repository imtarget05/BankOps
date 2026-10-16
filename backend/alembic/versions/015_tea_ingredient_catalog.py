"""Add tea-shop ingredient catalog attributes.

Revision ID: 015_tea_ingredient_catalog
Revises: 014_etl_pipeline_models
"""
import sqlalchemy as sa

from alembic import op

revision = "015_tea_ingredient_catalog"
down_revision = "014_etl_pipeline_models"
branch_labels = None
depends_on = None


def upgrade():
    bind = op.get_bind()
    columns = {column["name"] for column in sa.inspect(bind).get_columns("inv_items")}
    if "category" not in columns:
        op.add_column("inv_items", sa.Column("category", sa.String(length=128), nullable=True))
    if "packaging" not in columns:
        op.add_column("inv_items", sa.Column("packaging", sa.String(length=256), nullable=True))


def downgrade():
    bind = op.get_bind()
    columns = {column["name"] for column in sa.inspect(bind).get_columns("inv_items")}
    if "packaging" in columns:
        op.drop_column("inv_items", "packaging")
    if "category" in columns:
        op.drop_column("inv_items", "category")
