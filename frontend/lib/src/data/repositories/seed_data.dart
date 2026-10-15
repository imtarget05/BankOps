part of 'fake_repository.dart';

/// Seed data cho demo — tạo dữ liệu mẫu trong bộ nhớ.
/// Các hàm này được fake_repository.dart gọi qua part directive.

List<AppUser> _seedUsers() => const [
      AppUser(
          id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
          username: 'demo_maker',
          displayName: 'Nguyễn Hoàng An (GDV)',
          roles: ['staff']),
      AppUser(
          id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2',
          username: 'demo_checker',
          displayName: 'Trần Tuấn Bình (KSV)',
          roles: ['approver']),
      AppUser(
          id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3',
          username: 'demo_auditor',
          displayName: 'Lê Khánh Chi (KTNB)',
          roles: ['auditor']),
    ];

List<InventoryLocation> _seedLocations() => const [
      InventoryLocation(
          id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
          code: 'DEMO-HN',
          name: 'Kho Ấn Chỉ Trung Tâm - Hội Sở Chính'),
      InventoryLocation(
          id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2',
          code: 'DEMO-HCM',
          name: 'Kho Quỹ Chi Nhánh Sở Giao Dịch TP.HCM'),
      InventoryLocation(
          id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb3',
          code: 'KHO-DNG-01',
          name: 'Kho Ấn Chỉ Chi Nhánh Đà Nẵng'),
    ];

List<InventoryItem> _seedItems() => const [
      InventoryItem(
          id: 'cccccccc-cccc-4ccc-8ccc-ccccccccccc1',
          sku: 'TRA-OLONG-500G',
          name: 'Trà ô long',
          unit: 'gói',
          category: 'Nhóm Trà',
          packaging: '500 g/gói',
          trackedSerial: false),
      InventoryItem(
          id: 'cccccccc-cccc-4ccc-8ccc-ccccccccccc2',
          sku: 'SUA-DAC-1KG',
          name: 'Sữa đặc',
          unit: 'túi',
          category: 'Nhóm Bột & Sữa',
          packaging: '1 kg/túi',
          trackedSerial: false),
      InventoryItem(
          id: 'cccccccc-cccc-4ccc-8ccc-ccccccccccc3',
          sku: 'TRAN-CHAU-1KG',
          name: 'Trân châu đen',
          unit: 'túi',
          category: 'Topping',
          packaging: '1 kg/túi',
          trackedSerial: false),
      InventoryItem(
          id: 'cccccccc-cccc-4ccc-8ccc-ccccccccccc4',
          sku: 'LY-700ML',
          name: 'Ly nhựa 700 ml',
          unit: 'cái',
          category: 'Bao bì',
          packaging: '50 cái/lốc',
          trackedSerial: false),
    ];

List<StockBalance> _seedBalances() => const [
      StockBalance(
          locationId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
          itemId: 'cccccccc-cccc-4ccc-8ccc-ccccccccccc1',
          quantity: '250.000'),
      StockBalance(
          locationId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
          itemId: 'cccccccc-cccc-4ccc-8ccc-ccccccccccc2',
          quantity: '1000.000'),
      StockBalance(
          locationId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
          itemId: 'cccccccc-cccc-4ccc-8ccc-ccccccccccc3',
          quantity: '500.000'),
      StockBalance(
          locationId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2',
          itemId: 'cccccccc-cccc-4ccc-8ccc-ccccccccccc1',
          quantity: '120.000'),
    ];

List<AssetRecord> _seedAssets() => const [
      AssetRecord(
          id: 'asset-001',
          serial: 'EMV-VISA-2026-000101',
          itemId: 'cccccccc-cccc-4ccc-8ccc-ccccccccccc2',
          locationId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
          status: AssetStatus.available,
          assignee: 'Nguyễn Hoàng An'),
      AssetRecord(
          id: 'asset-002',
          serial: 'EMV-VISA-2026-000102',
          itemId: 'cccccccc-cccc-4ccc-8ccc-ccccccccccc2',
          locationId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
          status: AssetStatus.available),
      AssetRecord(
          id: 'asset-003',
          serial: 'STK-QR-2026-880001',
          itemId: 'cccccccc-cccc-4ccc-8ccc-ccccccccccc3',
          locationId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
          status: AssetStatus.available),
    ];

List<AssetLogItem> _seedAssetLogs() => [
      AssetLogItem(
        id: 'log-001',
        serial: 'EMV-VISA-2026-000101',
        fromLocationId: null,
        fromLocationName: 'NCC Thẻ Thông Minh',
        toLocationId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
        toLocationName: 'Kho Ấn Chỉ Trung Tâm - Hội Sở Chính',
        statusBefore: null,
        statusAfter: 'in_stock',
        actorName: 'Trần Tuấn Bình (KSV)',
        notes: 'Nhập kho lô phôi thẻ chip bảo mật mới',
        createdAt: DateTime.utc(2026, 10, 1, 9, 0),
      ),
      AssetLogItem(
        id: 'log-002',
        serial: 'EMV-VISA-2026-000101',
        fromLocationId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
        fromLocationName: 'Kho Ấn Chỉ Trung Tâm - Hội Sở Chính',
        toLocationId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
        toLocationName: 'Kho Ấn Chỉ Trung Tâm - Hội Sở Chính',
        fromAssignee: null,
        toAssignee: 'Nguyễn Hoàng An (GDV)',
        statusBefore: 'in_stock',
        statusAfter: 'assigned',
        actorName: 'Trần Tuấn Bình (KSV)',
        notes: 'Bàn giao phôi thẻ cho GDV phục vụ phát hành tại quầy',
        createdAt: DateTime.utc(2026, 10, 5, 14, 30),
      ),
    ];

List<StockMovement> _seedMovements() => [
      StockMovement(
          id: 'mmmmmmmm-0001',
          itemId: 'cccccccc-cccc-4ccc-8ccc-ccccccccccc1',
          locationId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
          quantity: '100.000',
          kind: 'receipt',
          createdAt: DateTime.utc(2026, 10, 1)),
    ];

List<StockRequest> _seedStockRequests() => [
      StockRequest(
          id: 'sr-0001',
          kind: RequestKind.receipt,
          status: RequestStatus.draft,
          version: 1,
          createdBy: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
          createdByName: 'Nguyễn Hoàng An (GDV)',
          locationId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
          items: const [
            StockRequestLine(
                itemId: 'cccccccc-cccc-4ccc-8ccc-ccccccccccc1',
                quantity: '10.000')
          ],
          reason: 'Nhập kho bổ sung séc bảo chi quý 4',
          createdAt: DateTime.utc(2026, 10, 5)),
      StockRequest(
          id: 'sr-0002',
          kind: RequestKind.payment,
          status: RequestStatus.pending,
          version: 1,
          createdBy: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2',
          createdByName: 'Trần Tuấn Bình (KSV)',
          locationId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2',
          items: const [
            StockRequestLine(
                itemId: 'cccccccc-cccc-4ccc-8ccc-ccccccccccc2',
                quantity: '1.000')
          ],
          reason: 'Xuất phôi thẻ Visa cấp mới cho KH VIP',
          createdAt: DateTime.utc(2026, 10, 6)),
    ];

List<Cashbox> _seedCashboxes() => const [
      Cashbox(
          id: '11111111-1111-4111-8111-111111111111',
          code: 'DEMO-CASH-01',
          name: 'Két Sắt Đại Quỹ Hội Sở Chính (Main Vault)',
          openingBalance: '25000000000.00'),
      Cashbox(
          id: '11111111-1111-4111-8111-111111111112',
          code: 'TELLER-BOX-01',
          name: 'Két Quầy Giao Dịch Số 01 - Hội Sở',
          openingBalance: '500000000.00'),
      Cashbox(
          id: '11111111-1111-4111-8111-111111111113',
          code: 'ATM-VAULT-01',
          name: 'Hộp Tiền Cây ATM Trung Tâm Hội Sở',
          openingBalance: '1200000000.00'),
    ];

List<CashBalance> _seedCashBalances() => const [
      CashBalance(
          cashboxId: '11111111-1111-4111-8111-111111111111',
          amount: '25850000000.00',
          currency: 'VND'),
      CashBalance(
          cashboxId: '11111111-1111-4111-8111-111111111112',
          amount: '480000000.00',
          currency: 'VND'),
      CashBalance(
          cashboxId: '11111111-1111-4111-8111-111111111113',
          amount: '1150000000.00',
          currency: 'VND'),
    ];

List<JournalEntry> _seedJournals() => [
      JournalEntry(
          id: 'je-0001',
          cashboxId: '11111111-1111-4111-8111-111111111111',
          kind: 'receipt',
          amount: '850000000.00',
          currency: 'VND',
          reason: 'Nộp tiền tiếp quỹ từ Ngân hàng Nhà nước',
          createdAt: DateTime.utc(2026, 10, 1)),
      JournalEntry(
          id: 'je-0002',
          cashboxId: '11111111-1111-4111-8111-111111111112',
          kind: 'payment',
          amount: '20000000.00',
          currency: 'VND',
          reason: 'Chi tiền mặt giải ngân khoản vay cá nhân',
          createdAt: DateTime.utc(2026, 10, 3)),
    ];

List<CashRequest> _seedCashRequests() => [
      CashRequest(
          id: 'cr-0001',
          kind: RequestKind.receipt,
          status: RequestStatus.draft,
          version: 1,
          cashboxId: '11111111-1111-4111-8111-111111111111',
          amount: '50000000.00',
          currency: 'VND',
          reason: 'Nộp điều chuyển tiền mặt từ chi nhánh',
          createdBy: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
          createdByName: 'Nguyễn Hoàng An (GDV)',
          createdAt: DateTime.utc(2026, 10, 5)),
      CashRequest(
          id: 'cr-0002',
          kind: RequestKind.payment,
          status: RequestStatus.pending,
          version: 1,
          cashboxId: '11111111-1111-4111-8111-111111111111',
          amount: '35000000.00',
          currency: 'VND',
          reason: 'Tiếp quỹ đầu ngày cho Quầy số 01',
          createdBy: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2',
          createdByName: 'Trần Tuấn Bình (KSV)',
          createdAt: DateTime.utc(2026, 10, 6)),
    ];

List<ActivityEvent> _seedActivity() => [
      ActivityEvent(
          id: 'ae-0001',
          occurredAt: DateTime.utc(2026, 10, 8, 9, 0),
          subjectId: 'sr-0001',
          status: 'created',
          messageKey: 'stock_request_created',
          processed: 1,
          total: 1),
      ActivityEvent(
          id: 'ae-0002',
          occurredAt: DateTime.utc(2026, 10, 8, 10, 30),
          subjectId: 'cr-0002',
          status: 'pending',
          messageKey: 'cash_request_pending'),
    ];

List<IntegrationConnection> _seedConnections() => const [
      IntegrationConnection(
          id: 'ic-0001',
          name: 'Core Banking T24 Gateway (ISO 8583)',
          endpoint: 'https://core.bankops.internal/api/v2',
          status: 'connected',
          lastTestedAt: null,
          lastError: null),
      IntegrationConnection(
          id: 'ic-0002',
          name: 'Cổng Chuyển Mạch Tài Chính Quốc Gia NAPAS',
          endpoint: 'https://napas.gateway.vn/switch/v1',
          status: 'connected',
          lastTestedAt: null,
          lastError: null),
      IntegrationConnection(
          id: 'ic-0003',
          name: 'Sổ Cái Kế Toán Tổng Hợp Oracle GL ERP',
          endpoint: 'https://gl.erp.internal/soap/v1',
          status: 'connected',
          lastTestedAt: null,
          lastError: null),
    ];

List<IntegrationRun> _seedRuns() => [
      IntegrationRun(
          id: 'ir-0001',
          connectionId: 'ic-0001',
          status: 'succeeded',
          phase: 'completed',
          startedAt: DateTime.utc(2026, 10, 8, 8, 0),
          processed: 1250,
          errorCount: 0,
          total: 1250,
          endedAt: DateTime.utc(2026, 10, 8, 8, 2)),
      IntegrationRun(
          id: 'ir-0002',
          connectionId: 'ic-0002',
          status: 'succeeded',
          phase: 'completed',
          startedAt: DateTime.utc(2026, 10, 8, 12, 0),
          processed: 840,
          errorCount: 0,
          total: 840,
          endedAt: DateTime.utc(2026, 10, 8, 12, 1)),
    ];

List<ReconciliationRun> _seedReconciliations() => [
      ReconciliationRun(
          id: 'rr-0001',
          status: 'completed',
          startedAt: DateTime.utc(2026, 10, 8, 7, 0),
          exceptions: const ['DEMO-ASSET-0001']),
    ];

List<InventoryBucket> _seedInventoryDaily() => const [
      InventoryBucket(
          bucket: '2026-10-01',
          inboundQty: '100',
          outboundQty: '15',
          netQty: '85',
          receiptCount: 2,
          issueCount: 1),
      InventoryBucket(
          bucket: '2026-10-03',
          inboundQty: '40',
          outboundQty: '25',
          netQty: '15',
          receiptCount: 1,
          issueCount: 2),
      InventoryBucket(
          bucket: '2026-10-05',
          inboundQty: '60',
          outboundQty: '10',
          netQty: '50',
          receiptCount: 2,
          issueCount: 1),
      InventoryBucket(
          bucket: '2026-10-08',
          inboundQty: '30',
          outboundQty: '20',
          netQty: '10',
          receiptCount: 1,
          issueCount: 1),
    ];

List<InventoryBucket> _seedInventoryMonthly() => const [
      InventoryBucket(
          bucket: '2026-08',
          inboundQty: '180',
          outboundQty: '95',
          netQty: '85',
          receiptCount: 5,
          issueCount: 4),
      InventoryBucket(
          bucket: '2026-09',
          inboundQty: '210',
          outboundQty: '130',
          netQty: '80',
          receiptCount: 6,
          issueCount: 5),
      InventoryBucket(
          bucket: '2026-10',
          inboundQty: '230',
          outboundQty: '70',
          netQty: '160',
          receiptCount: 6,
          issueCount: 5),
    ];

List<CashflowBucket> _seedCashflowDaily() => const [
      CashflowBucket(
          bucket: '2026-10-01',
          totalIn: '1000000.00',
          totalOut: '0.00',
          net: '1000000.00',
          journalCount: 1),
      CashflowBucket(
          bucket: '2026-10-03',
          totalIn: '0.00',
          totalOut: '250000.00',
          net: '-250000.00',
          journalCount: 1),
      CashflowBucket(
          bucket: '2026-10-06',
          totalIn: '500000.00',
          totalOut: '120000.00',
          net: '380000.00',
          journalCount: 2),
      CashflowBucket(
          bucket: '2026-10-09',
          totalIn: '350000.00',
          totalOut: '150000.00',
          net: '200000.00',
          journalCount: 2),
    ];

List<CashflowBucket> _seedCashflowMonthly() => const [
      CashflowBucket(
          bucket: '2026-08',
          totalIn: '2400000.00',
          totalOut: '900000.00',
          net: '1500000.00',
          journalCount: 5),
      CashflowBucket(
          bucket: '2026-09',
          totalIn: '3100000.00',
          totalOut: '1450000.00',
          net: '1650000.00',
          journalCount: 7),
      CashflowBucket(
          bucket: '2026-10',
          totalIn: '1850000.00',
          totalOut: '520000.00',
          net: '1330000.00',
          journalCount: 6),
    ];

List<StagnationItem> _seedStagnation() => const [
      StagnationItem(
        itemId: 'cccccccc-cccc-4ccc-8ccc-ccccccccccc2',
        sku: 'DEMO-LAPTOP',
        name: 'Laptop mẫu',
        quantity: '4.000',
        daysSinceLastIssue: 98,
        severity: 'critical',
      ),
      StagnationItem(
        itemId: 'cccccccc-cccc-4ccc-8ccc-ccccccccccc1',
        sku: 'DEMO-PAPER-A4',
        name: 'Giấy A4 giả lập',
        quantity: '100.000',
        daysSinceLastIssue: 45,
        severity: 'watch',
      ),
    ];
