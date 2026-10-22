# Gap register — Phase 0

Priority model: P0 broken correctness/CI/security/essential functionality → P1 high-value capability/verification gap → P2 reliability/observability/performance/integration → P3 optional.

## P0 — fix first (restore health)

| ID | Repo | Track | Gap | Evidence baseline | Required fix | Verification target |
|---|------|-------|-----|-------------------|--------------|---------------------|
| G1 | retail-finance-core-platform | A | CI `unit` and `integration` jobs run `mvn` at repo root but `pom.xml` is in `backend/` → `MissingProjectException`, every push red | `mvn -B test` at root fails; `mvn -B test` in backend/ = 26/26 PASS (LOCAL_VERIFIED) | FIXED: added job-level `defaults: run: working-directory: backend` to `unit` and `integration` jobs (branch `fix/ci-maven-backend-working-directory`, PR #1, not merged to main without approval) | CLOUD_CI_VERIFIED: GitHub Actions run 39630546625 — unit + integration + reconciliation-service all SUCCESS (https://github.com/imtarget05/retail-finance-core-platform/actions/runs/39630546625) |
| G2 | retail-finance-core-platform | A | Integration tests (Testcontainers MySQL) not runnable locally (Docker daemon unavailable); not confirmed on CI because G1 blocks the pipeline | N/A | Same CI fix as G1 unlocks runner-based Docker execution | CLOUD_CI_VERIFIED: Integration tests (real MySQL 8 via Testcontainers) SUCCESS on GitHub Actions run 39630546625 (https://github.com/imtarget05/retail-finance-core-platform/actions/runs/39630546625) |
| G3 | OpsBridge | A | Remote CI not rerun on current HEAD `bdaf246`; concurrency-harness (50 buyers / 10 units, `RESULT: PASS`) only locally verified | PR #2 pipeline run 39631053992: concurrency-harness ✅ SUCCESS, ci-gate ❌ FAILURE (aggregate), opsbridge-stack-smoke ❌ FAILURE, opsbridge-web-e2e ❌ FAILURE. Key: concurrency-harness zero-oversell gate passed (exact fill 10/10, 40 × 409 fast-fails). ci-gate failure likely due to stack-smoke/e2e downstream. | CLOUD_CI_VERIFIED: concurrency-harness job SUCCESS on run 39631053992 (https://github.com/imtarget05/OpsBridge/actions/runs/39631053992). Left open — not merged without review. |
| G4 | OpsBridge / QuanLyKho / AKS-SRE-Platform / SmartDocumentChatbot | A/B/C | Uncommitted working-tree changes present (6 / 8 / 28+ / 1 files) | git status recorded | Preserve: commit on feature branches or leave intact; never discard | Working trees intact |

## P1 — high-value capabilities and verification gaps

| ID | Repo | Track | Gap | Evidence needed |
|---|------|-------|-----|-----------------|
| G5 | OpsBridge | A | Optimistic-concurrency `Version` token declared, never exercised by any test (admitted in RECRUITER-EVIDENCE) | Add concurrency debit test proving `OptimisticLockingFailure` handling / no lost updates | PR #2 pipeline includes concurrency-harness test but Version token test path not explicitly verified; G5 remains open until dedicated test exercises the failure path | In-progress — concurrency-harness passed but Version token untested per gap admission |
| G6 | OpsBridge | A | Unresolved P1 from repo audit: `inventory.reserved` outbox row can commit while `inventory.released` compensation fails → 503 + orphan reservation; no durable repair evidence | Failure drill + idempotent reconciler repair; assert 503, released Redis, one committed reserved row, no release row, then repair | No durable repair evidence found in repo; P1 gap acknowledged; requires adding compensating transaction test + idempotent reconciler | Pending — no test evidence yet in repo |
| G7 | OpsBridge | A | Pod-level liveness/readiness probes absent (container healthcheck only); payment service is simulation | Document decision or add probes; label payment simulation | CI run 39631053992 shows stack-smoke failure possibly related to probe/healthcheck; payment service confirmed simulation per ADR-017. Gap: need to document healthcheck presence/absence decision and payment simulation labeling | In-progress — CI artifacts may provide evidence |
| G8 | retail-finance-core-platform | A | Concurrency: concurrent debits against same account not yet tested at service level; optimistic-lock failure path untested | JUnit concurrency test (Testcontainers MySQL) proving exactly-one success, no lost update | Service-level concurrency test not yet written; need Integration test with Testcontainers MySQL exercising concurrent debits + optimistic-lock failure path | Pending — test needs to be written |
| G9 | retail-finance-core-platform | A | Reconciliation workflow: mismatch → discrepancy human review path tested? (README: never auto-corrects) | Python service tests already exist (11); confirm CI `reconciliation-service` job green | Same CI run 39630546625 confirmed reconciliation-service ✅ SUCCESS. Human review path: README documents never auto-corrects. Gap: verify the 11 Python tests cover the mismatch → review path | VERIFIED: reconciliation-service job green on run 39630546625; 11 Python tests exist |
| G10 | retail-finance-core-platform | A | Flyway: new-migration addition pattern and `ddl-auto: validate` drift gate not exercised in CI | Add a migration in a feature branch; confirm validate passes | Need to add a test migration and run `flyway validate` in CI; currently no migration drift gate in pipeline | Pending — add flyway validate step |
| G11 | QuanLyKho | C | AI/airflow/MLflow components present (ai/, airflow/, test_ai_*, test_airflow_*) but C1: keep only use-case-justified, verified components | Review each; remove or justify; prioritize core business correctness | ai.py modified uncommitted; need to review AI components and decide what to keep/remove | In-progress — ai.py uncommitted, needs review |
| G12 | AKS-SRE-Platform | B | No ingress controller, no external-secrets in repo; no enforced Terraform lint/validation CI gate confirmed | Add terraform validate/lint as CI gate; document exclusions (ingress, external-secrets) as accepted risks | Terraform validate confirmed LOCAL_VERIFIED; no CI gate currently; need to add terraform fmt/validate as gate | In-progress — gate needs to be added to CI |
| G13 | AKS-SRE-Platform | B | Kind vs real-AKS tier separation must remain explicit in all evidence | Label every result PRE_AZURE_DRY_RUN or Azure; never conflate | Kind results = PRE_AZURE_DRY_RUN documented; need to ensure all evidence labels are explicit | Verified — kind results labeled per existing evidence |

## P2 — reliability, observability, integration

| ID | Repo | Track | Gap |
|---|------|-------|-----|
| G14 | OpsBridge | A | ADRs for key decisions (001–021 exist) — interview diagrams (request lifecycle, transaction boundary, message flow, recovery) to be authored | ADRs 001–021 exist in repo; interview diagrams need to be authored for request lifecycle, transaction boundary, message flow, recovery | Author the 4 interview diagrams (request lifecycle, transaction boundary, message flow, recovery) to accompany existing ADRs | In-progress — diagrams are the remaining work |
| G15 | OpsBridge | A | k6 load test `load-tests/k6/flash-sale.js` exists; results not current CI gate | Results not current CI gate; need to integrate k6 results into CI pipeline or document as periodic run | k6 test exists but results not integrated; gap: add CI step or schedule periodic run + analyze results against zero-oversell invariant | In-progress — need to integrate into CI or document run process |
| G16 | AKS-SRE-Platform | B | SLI/SLO baseline (docs/evidence/sli-slo-baseline-PASS.md), PDB drain drill, network-policy probe exist as evidence; convert to reusable runbooks/alerts with trigger/severity/impact/runbook/owner/verification | Evidence docs exist; need to convert each to reusable runbooks with trigger/severity/impact/runbook/owner/verification (Track B3) | 5 evidence docs exist (PDB drain, SLI/SLO baseline, network policy, disaster recovery, phase7a); gap: convert to runbooks with required fields | In-progress — converting evidence to runbooks |
| G17 | All | A/B/C | Portfolio asset registry + interview defense material (Vietnamese Q&A) | Collect and organize portfolio asset registry + Vietnamese Q&A for interview defense | Registry + Q&A material needs to be compiled from all repo assets | Pending — collect from all repos |

## P3 — optional

UI polish, speculative features, additional repositories, new AI capabilities in QuanLyKho.

| ID | Repo | Track | Gap | Evidence needed |
|---|------|-------|-----|-----------------|
| G18 | All | A/B/C | Additional repositories not yet audited for CI gaps | Run gap analysis across all repos in workspace |
| G19 | All | A/B/C | Interview defense Q&A compilation finalization | Consolidate Vietnamese Q&A from all asset registers |
