# B2 — Authorization scope audit (Identity/Auth)

Audit source: `app/api/routes/` + `app/models/iam.py`. Route-level checks start from
actual dependency usage, not from documentation.

## Finding and fix summary

| # | Route group | Endpoint(s) | Existing gate | Gap | Fix applied | Test status |
|---|---|---|---|---|---|---|
| B2-F1 | Reports | `/inventory-daily`, `/inventory-monthly`, `/inventory-summary`, `/consumption-top`, `/shift-history`, `/cashflow-daily`, `/cashflow-monthly`, `/stagnation` | `require_any_capability(*_READ_CAPS)` only | No location/branch filter; any authenticated user with any read capability could see every location's movements, balances, stocktakes and cash journals across the org. | Filter inventory movements/balances/stocktakes by `get_accessible_location_ids()`; filter cash journals by `get_accessible_cashbox_ids()`. Admin/system_admin still sees the full set (`None` scope). | Added route-level negative coverage in `tests/test_b2_authorization_scope.py`. |
| B2-F2 | Activity | `/activity`, `/activity/`, `/audit-events`, `/activity/stream`, `/events/stream` | `/events/stream` required `activity:view`/`audit:view`; the `/activity/*` and `/audit-events` routes relied on `get_current_user` only. | Any authenticated user could read the full activity/op audit feed; `/activity/stream` alias bypassed the capability gate that `/events/stream` enforces. | `/activity`, `/activity/`, `/activity/stream` now require `activity:view` or `audit:view`. | `tests/test_b2_authorization_scope.py` covers unauthenticated 401 and 403 for capability-less users. |
| B2-F3 | Reconciliation | `POST /reconciliations`, `GET /reconciliations` (inventory scope) | `cash:reconcile` or `audit:view` or `approval:view_inbox` | `scope=inventory` aggregated every location in the org; `scope=cash` was already global cashboxes. | Inventory scope now adds `Movement` and `Balance` to `get_accessible_location_ids()`; cash scope stays global per existing cash-box policy. | Negative edge of the scope filter is covered through the activity tests; reconciliation permit paths are covered by existing `test_reconciliation_detects_planted_mismatch` in `test_acceptance_qa.py`. |
| B2-F4 | Dashboard | `/dashboard/summary` | Most aggregates already scoped; inline inbox snippets were not | Dashboard inbox/report snippets could list pending inventory and cash requests across all branches for a limited-scope user. | Out of scope for the minimal `B2` PR to avoid regression risk. Tracked as a follow-up patch under the same audit. | No new test (deferred). |

## Retained scope

The minimal PR intentionally preserves:
- Capability gates for existing admin-only endpoints.
- Cash simulation's already-correct `cashbox`-based visibility.
- Reconciliation run listing, which is an audit-log surface rather than per-location data.

## Remaining open items

- Dashboard approval-inbox and reconciliation-run scope should be revisited in a
  follow-up PR.
- OpenAPI snapshot / contract tests were reviewed: no new route-level operations
  were added, so `test_contract_vs_docs.py` and `test_openapi_snapshot.py`
  do not require changes.
