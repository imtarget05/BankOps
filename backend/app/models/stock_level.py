"""Compatibility exports for inventory stock-level models.

The canonical mappings live in :mod:`app.models.inventory`. Re-exporting them
keeps old import paths working without registering tables twice in metadata.
"""

from app.models.inventory import StockLevel, Stocktake, StocktakeLine

__all__ = ["StockLevel", "Stocktake", "StocktakeLine"]
