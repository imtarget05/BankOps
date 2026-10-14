# Dashboard data-trust evidence

## User journey

As an operations user, I need dashboard indicators to show only verified progress, so I can distinguish an empty or incomplete data feed from a healthy operation.

## RED → GREEN

The initial test was run before the new metrics module existed:

```text
flutter test test/dashboard_trust_metrics_test.dart
Error: Error when reading ... dashboard_trust_metrics.dart
```

The implementation then introduced data-coverage and reconciliation states.

| Guarantee | Test | Result |
| --- | --- | --- |
| An empty cash/inventory dataset is labelled as unavailable and has no percentage score. | `dashboard_trust_metrics_test.dart` | PASS |
| Cash and inventory coverage use actual known-record ratios. | `dashboard_trust_metrics_test.dart` | PASS |
| A completed reconciliation with exceptions is shown as an exception, not as a matched ledger. | `dashboard_trust_metrics_test.dart`, `widget_test.dart` | PASS |

## Validation

- `flutter test test/dashboard_trust_metrics_test.dart test/widget_test.dart` — 6 tests passed.
- `flutter analyze lib/src/features/dashboard/dashboard_screen.dart lib/src/features/dashboard/dashboard_trust_metrics.dart` — no issues.
- `flutter build web --release --dart-define=API_BASE_URL=https://bankops-api.tanmainguyenbinh.workers.dev` — successful.
- Focused coverage: `dashboard_trust_metrics.dart` is 23/26 executable lines hit (88.5%). The three unhit lines are the valid completed/no-exception and in-progress reconciliation variants; they do not affect the empty-data or exception scenarios addressed in this change.

No Git checkpoint was created because the working tree already contained unrelated user changes.
