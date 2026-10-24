# Phase G4 Evidence: Multimodal Document Intake & Verification Pipeline

**Product:** Multimodal Document Intelligence (`QuanLyKho`)  
**Capability:** Document Ingestion (Vendor Invoices / Stock Receipts) → Schema Extraction → Mathematical Reconciliation → Maker-Checker Draft Creation  
**Branch:** `feature/option-b-multimodal-intake`  
**Date:** 2026-10-24  
**Evidence Status:** `UNIT_VERIFIED` + `INTEGRATION_VERIFIED`  

---

## 1. Business Problem & Integrity Architecture

In wholesale and retail warehousing, supplier delivery invoices frequently arrive as physical paper documents, scan PDFs, or photos.
Attempting to connect an OCR/VLM directly to an inventory ledger introduces catastrophic operational risks:
1. **OCR / Vision Hallucinations:** Character misrecognitions (e.g., misreading 10 kg as 100 kg, or swapping digits).
2. **Pricing Discrepancies:** Arithmetic errors where unit price $\times$ quantity does not equal stated line total, or tax and subtotal do not reconcile with the invoice total.
3. **Bypassing Separation of Duties:** Direct auto-posting creates inventory from untrusted external documents without human warehouse receiving and supervisor authorization.

### Core Architectural Invariants:
- **Three-Tier Mathematical Verification:**
  1. $\text{Line Total}_i = \text{Quantity}_i \times \text{Unit Price}_i$ (tolerance $\le 0.05$).
  2. $\text{Subtotal} = \sum_{i} \text{Line Total}_i$ (tolerance $\le 0.05$).
  3. $\text{Total Payment} = \text{Subtotal} + \text{VAT Amount}$ (tolerance $\le 0.05$).
- **Catalog Grounding:** Extracted item names and SKUs are resolved against canonical `inv_items`.
- **Strict Maker-Checker Preservation:** The pipeline **never** writes to `inv_balances` or `inv_movements`. It creates an `InventoryRequest` with `status="draft"`. The warehouse receiver (Maker) inspects the physical goods and submits the request, and the supervisor (Checker) verifies and approves it before stock balances are updated.

---

## 2. Pipeline Flow Diagram

```
[Invoice PDF / Image / Text]
             │
             ▼
┌─────────────────────────────┐
│  Multimodal Ingestion       │
│  - parse_invoice_bytes/text │
└────────────┬────────────────┘
             │ Extracted Schema
             ▼
┌────────────────────────────────────────────────────────┐
│  Mathematical Reconciliation                           │
│  - Line Math: Qty * Price == Line Total                │
│  - Subtotal: Sum(Lines) == Subtotal                    │
│  - Total: Subtotal + VAT == Total Payment              │
└────────────┬───────────────────────────────────────────┘
             │
      Pass? ─┴────────────────────────────┐
             │ YES                        │ NO
             ▼                            ▼
┌─────────────────────────────┐  ┌────────────────────────────────────┐
│  Catalog SKU Matching       │  │ Rejection Report                   │
│  - Matches against inv_items│  │ is_valid=False, error details      │
└────────────┬────────────────┘  └────────────────────────────────────┘
             │
             ▼
┌────────────────────────────────────────────────────────┐
│  Draft Creation (Maker-Checker Preserved)              │
│  - POST /inventory/intake/create-draft                 │
│  - Creates InventoryRequest(status="draft")            │
│  - Balances unchanged (0 stock change)                 │
└────────────┬───────────────────────────────────────────┘
             │
             │ [Maker inspects goods & submits]
             ▼
┌────────────────────────────────────────────────────────┐
│  POST /inventory/requests/{id}/submit                  │
│  - Request status -> "submitted"                       │
└────────────┬───────────────────────────────────────────┘
             │
             │ [Checker verifies & approves]
             ▼
┌────────────────────────────────────────────────────────┐
│  POST /inventory/requests/{id}/approve                 │
│  - Request status -> "posted"                          │
│  - Atomically updates inv_balances & inv_movements     │
└────────────────────────────────────────────────────────┘
```

---

## 3. Measured Test Evidence

### A. Dedicated Intake & Reconciliation Test Suite
Command:
```bash
DATABASE_URL="postgresql+asyncpg://mainguyenbinhtan@localhost:5432/bankops_clean_test" poetry run pytest tests/test_multimodal_intake.py -v
```
Output:
```text
============================= test session starts ==============================
tests/test_multimodal_intake.py::TestInvoiceMathValidation::test_valid_invoice_math_reconciliation PASSED [ 16%]
tests/test_multimodal_intake.py::TestInvoiceMathValidation::test_line_math_mismatch_detected PASSED [ 33%]
tests/test_multimodal_intake.py::TestInvoiceMathValidation::test_subtotal_mismatch_detected PASSED [ 50%]
tests/test_multimodal_intake.py::TestInvoiceMathValidation::test_total_amount_mismatch_detected PASSED [ 66%]
tests/test_multimodal_intake.py::TestMultimodalIntakeAPI::test_extract_endpoint PASSED [ 83%]
tests/test_multimodal_intake.py::TestMultimodalIntakeAPI::test_intake_process_creates_draft_and_executes_maker_checker PASSED [100%]

======================== 6 passed, 3 warnings in 2.26s =========================
```

### B. Full QuanLyKho Regression Test Suite
Command:
```bash
DATABASE_URL="postgresql+asyncpg://mainguyenbinhtan@localhost:5432/bankops_clean_test" poetry run pytest tests/ -q
```
Output:
```text
714 passed, 8 skipped, 1 xfailed in 254.66s (0:04:14)
```
Zero regressions across all existing core banking operations, inventory journals, FEFO lot accounting, stocktakes, and IAM scopes.

---

## 4. Key Interview Explanations (Backend / AI Engineer)

1. **Why not let the VLM / OCR auto-post stock receipts?**
   - In production banking and inventory platforms, an external document is an unverified input. Giving an AI model direct write capability to a stock ledger violates dual-control / separation-of-duties and allows poisoned or misread invoices to corrupt financial books.
2. **How does the system guard against arithmetic hallucinations?**
   - We enforce a strict deterministic verification layer between model extraction and database persistence. Even if an upstream VLM extracts numbers, our validation function reconciles line items, subtotal, and tax mathematically. Any mismatch halts draft creation with structured rejection messages.
3. **Maker-Checker Integration:**
   - The document intake output is simply a pre-filled draft request (`InventoryRequest(status="draft")`). The human storekeeper (Maker) still must verify the delivered physical inventory and submit the request, and the warehouse supervisor (Checker) must approve it.
