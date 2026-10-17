part of 'fake_repository.dart';

/// Seed data cho demo — tạo dữ liệu mẫu trong bộ nhớ.
/// Các hàm này được fake_repository.dart gọi qua part directive.

List<AppUser> _seedUsers() => const [
      AppUser(
          id: '00000000-0000-4000-8000-000000000001',
          username: 'tanmainguyenbinh',
          email: 'tanmainguyenbinh@gmail.com',
          displayName: 'Bình Tân',
          roles: ['admin', 'inventory_manager', 'approver', 'system_admin']),
      AppUser(
          id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2',
          username: 'admin',
          displayName: 'Trần Văn Quản Lý',
          roles: ['admin', 'inventory_manager', 'approver']),
      AppUser(
          id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
          username: 'staff',
          displayName: 'Nguyễn Thị Mai',
          roles: ['staff']),
      AppUser(
          id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2',
          username: 'demo_checker',
          displayName: 'Trần Văn Quản Lý',
          roles: ['approver', 'inventory_manager', 'admin']),
      AppUser(
          id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
          username: 'demo_maker',
          displayName: 'Nguyễn Thị Mai',
          roles: ['staff']),
      AppUser(
          id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3',
          username: 'demo_auditor',
          displayName: 'Lê Khánh Chi',
          roles: ['auditor']),
      AppUser(
          id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa7',
          username: 'manager_demo',
          displayName: 'Lê Hoàng Nam',
          roles: ['admin', 'inventory_manager']),
    ];

List<InventoryLocation> _seedLocations() => const [
      InventoryLocation(
          id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
          code: 'BAR-MAIN',
          name: 'Quầy Pha Chế Chính (Bar Counter)'),
      InventoryLocation(
          id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2',
          code: 'STORAGE-COOL',
          name: 'Kho Mát & Tủ Bảo Quản Nguyên Liệu'),
      InventoryLocation(
          id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb3',
          code: 'STORAGE-DRY',
          name: 'Kho Khô & Vật Tư Sau Quầy'),
      InventoryLocation(
          id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbc1',
          code: 'KHO-TT',
          name: 'Kho Trung Tâm Cung Ứng'),
    ];

List<InventoryItem> _seedItems() => const [
      InventoryItem(
          id: 'cccccccc-cccc-4ccc-8ccc-ccccccccccc1',
          sku: 'TRA-DEN-SO9',
          name: 'Trà Đen Lộc Phát Số 9',
          unit: 'gói',
          category: 'Nhóm Trà',
          packaging: '500g/gói (Thùng 20 gói)',
          costPrice: 65000,
          sellingPrice: 95000,
          minStock: 10,
          trackedSerial: false),
      InventoryItem(
          id: 'cccccccc-cccc-4ccc-8ccc-ccccccccccc2',
          sku: 'TRA-LAI-500G',
          name: 'Trà Xanh Hoa Lài Thượng Hạng',
          unit: 'gói',
          category: 'Nhóm Trà',
          packaging: '500g/gói (Thùng 20 gói)',
          costPrice: 70000,
          sellingPrice: 105000,
          minStock: 10,
          trackedSerial: false),
      InventoryItem(
          id: 'cccccccc-cccc-4ccc-8ccc-ccccccccccc3',
          sku: 'TRA-OLONG-500G',
          name: 'Trà Ô Long Nướng Đặc Biệt',
          unit: 'gói',
          category: 'Nhóm Trà',
          packaging: '500g/gói (Thùng 20 gói)',
          costPrice: 85000,
          sellingPrice: 125000,
          minStock: 8,
          trackedSerial: false),
      InventoryItem(
          id: 'cccccccc-cccc-4ccc-8ccc-ccccccccccc4',
          sku: 'TRA-THIET-QUAN-AM',
          name: 'Trà Thiết Quan Âm Rang',
          unit: 'gói',
          category: 'Nhóm Trà',
          packaging: '500g/gói (Thùng 20 gói)',
          costPrice: 90000,
          sellingPrice: 135000,
          minStock: 5,
          trackedSerial: false),
      InventoryItem(
          id: 'cccccccc-cccc-4ccc-8ccc-ccccccccccc5',
          sku: 'TRA-EARL-GREY',
          name: 'Trà Earl Grey Bá Tước Anh Quốc',
          unit: 'gói',
          category: 'Nhóm Trà',
          packaging: '500g/gói (Thùng 20 gói)',
          costPrice: 95000,
          sellingPrice: 140000,
          minStock: 5,
          trackedSerial: false),
      InventoryItem(
          id: 'cccccccc-cccc-4ccc-8ccc-ccccccccccc6',
          sku: 'BOT-BEO-BONE',
          name: 'Bột Kem Béo B-One Thái Lan',
          unit: 'túi',
          category: 'Nhóm Bột & Sữa',
          packaging: '1kg/túi (Thùng 12 túi)',
          costPrice: 75000,
          sellingPrice: 110000,
          minStock: 15,
          trackedSerial: false),
      InventoryItem(
          id: 'cccccccc-cccc-4ccc-8ccc-ccccccccccc7',
          sku: 'SUA-TUOI-1L',
          name: 'Sữa Tươi Tiệt Trùng Barista Milk',
          unit: 'hộp',
          category: 'Nhóm Bột & Sữa',
          packaging: '1 Lít/hộp (Thùng 12 hộp)',
          costPrice: 32000,
          sellingPrice: 45000,
          minStock: 24,
          trackedSerial: false),
      InventoryItem(
          id: 'cccccccc-cccc-4ccc-8ccc-ccccccccccc8',
          sku: 'SUA-DAC-1KG',
          name: 'Sữa Đặc Ngọt Larosee',
          unit: 'túi',
          category: 'Nhóm Bột & Sữa',
          packaging: '1kg/túi (Thùng 12 túi)',
          costPrice: 42000,
          sellingPrice: 60000,
          minStock: 12,
          trackedSerial: false),
      InventoryItem(
          id: 'cccccccc-cccc-4ccc-8ccc-ccccccccccc9',
          sku: 'BOT-MATCHA-500G',
          name: 'Bột Matcha Uji Nhật Bản',
          unit: 'gói',
          category: 'Nhóm Bột & Sữa',
          packaging: '500g/gói',
          costPrice: 180000,
          sellingPrice: 250000,
          minStock: 5,
          trackedSerial: false),
      InventoryItem(
          id: 'cccccccc-cccc-4ccc-8ccc-cccccccccc10',
          sku: 'BOT-CACAO-500G',
          name: 'Bột Cacao Nguyên Chất Malaysia',
          unit: 'túi',
          category: 'Nhóm Bột & Sữa',
          packaging: '500g/túi',
          costPrice: 80000,
          sellingPrice: 115000,
          minStock: 5,
          trackedSerial: false),
      InventoryItem(
          id: 'cccccccc-cccc-4ccc-8ccc-cccccccccc11',
          sku: 'BOT-KHOAI-MON',
          name: 'Bột Khoai Môn Dẻo Thơm',
          unit: 'túi',
          category: 'Nhóm Bột & Sữa',
          packaging: '1kg/túi',
          costPrice: 70000,
          sellingPrice: 100000,
          minStock: 6,
          trackedSerial: false),
      InventoryItem(
          id: 'cccccccc-cccc-4ccc-8ccc-cccccccccc12',
          sku: 'KEM-RICHS-LUN',
          name: 'Kem Béo Thực Vật Rich\'s Lùn',
          unit: 'hộp',
          category: 'Nhóm Bột & Sữa',
          packaging: '454ml/hộp (Thùng 24 hộp)',
          costPrice: 28000,
          sellingPrice: 40000,
          minStock: 12,
          trackedSerial: false),
      InventoryItem(
          id: 'cccccccc-cccc-4ccc-8ccc-cccccccccc13',
          sku: 'TRAN-CHAU-DEN',
          name: 'Trân Châu Đen Gia Uy',
          unit: 'gói',
          category: 'Topping',
          packaging: '1kg/gói (Thùng 20 gói)',
          costPrice: 38000,
          sellingPrice: 55000,
          minStock: 15,
          trackedSerial: false),
      InventoryItem(
          id: 'cccccccc-cccc-4ccc-8ccc-cccccccccc14',
          sku: 'TRAN-CHAU-3Q',
          name: 'Trân Châu Trắng 3Q Sea Jelly',
          unit: 'túi',
          category: 'Topping',
          packaging: '2kg/túi',
          costPrice: 55000,
          sellingPrice: 80000,
          minStock: 8,
          trackedSerial: false),
      InventoryItem(
          id: 'cccccccc-cccc-4ccc-8ccc-cccccccccc15',
          sku: 'TRAN-CHAU-HOANG-KIM',
          name: 'Trân Châu Hoàng Kim Caramel',
          unit: 'gói',
          category: 'Topping',
          packaging: '1kg/gói',
          costPrice: 45000,
          sellingPrice: 65000,
          minStock: 8,
          trackedSerial: false),
      InventoryItem(
          id: 'cccccccc-cccc-4ccc-8ccc-cccccccccc16',
          sku: 'THACH-NHA-DAM',
          name: 'Thạch Nha Đam Giòn Aloka',
          unit: 'túi',
          category: 'Topping',
          packaging: '1kg/túi',
          costPrice: 35000,
          sellingPrice: 50000,
          minStock: 10,
          trackedSerial: false),
      InventoryItem(
          id: 'cccccccc-cccc-4ccc-8ccc-cccccccccc17',
          sku: 'THACH-CU-NANG',
          name: 'Thạch Củ Năng Giòn Hạt Lựu',
          unit: 'túi',
          category: 'Topping',
          packaging: '1kg/túi',
          costPrice: 48000,
          sellingPrice: 70000,
          minStock: 6,
          trackedSerial: false),
      InventoryItem(
          id: 'cccccccc-cccc-4ccc-8ccc-cccccccccc18',
          sku: 'THACH-DUA-BEN-TRE',
          name: 'Thạch Dừa Giòn Bến Tre',
          unit: 'túi',
          category: 'Topping',
          packaging: '1kg/túi',
          costPrice: 32000,
          sellingPrice: 48000,
          minStock: 8,
          trackedSerial: false),
      InventoryItem(
          id: 'cccccccc-cccc-4ccc-8ccc-cccccccccc19',
          sku: 'PUDDING-TRUNG',
          name: 'Bột Pudding Trứng Mau Lin',
          unit: 'gói',
          category: 'Topping',
          packaging: '1kg/gói',
          costPrice: 110000,
          sellingPrice: 155000,
          minStock: 5,
          trackedSerial: false),
      InventoryItem(
          id: 'cccccccc-cccc-4ccc-8ccc-cccccccccc20',
          sku: 'SYRUP-DAO-700ML',
          name: 'Syrup Đào Monin Chai Thủy Tinh',
          unit: 'chai',
          category: 'Syrup & Mứt',
          packaging: '700ml/chai',
          costPrice: 165000,
          sellingPrice: 220000,
          minStock: 5,
          trackedSerial: false),
      InventoryItem(
          id: 'cccccccc-cccc-4ccc-8ccc-cccccccccc21',
          sku: 'SYRUP-VAI-700ML',
          name: 'Syrup Vải Golden Farm',
          unit: 'chai',
          category: 'Syrup & Mứt',
          packaging: '700ml/chai',
          costPrice: 85000,
          sellingPrice: 120000,
          minStock: 5,
          trackedSerial: false),
      InventoryItem(
          id: 'cccccccc-cccc-4ccc-8ccc-cccccccccc22',
          sku: 'SYRUP-DAU-BERRINO',
          name: 'Syrup Dâu Berrino',
          unit: 'chai',
          category: 'Syrup & Mứt',
          packaging: '1 Lít/chai',
          costPrice: 95000,
          sellingPrice: 135000,
          minStock: 4,
          trackedSerial: false),
      InventoryItem(
          id: 'cccccccc-cccc-4ccc-8ccc-cccccccccc23',
          sku: 'MUT-CHANH-LEO',
          name: 'Mứt Chanh Leo Tươi Osterberg',
          unit: 'hộp',
          category: 'Syrup & Mứt',
          packaging: '1kg/hộp',
          costPrice: 115000,
          sellingPrice: 160000,
          minStock: 4,
          trackedSerial: false),
      InventoryItem(
          id: 'cccccccc-cccc-4ccc-8ccc-cccccccccc24',
          sku: 'DUONG-NUOC-5L',
          name: 'Nước Đường Bắp Đậm Đặc',
          unit: 'can',
          category: 'Đường & Gia vị',
          packaging: '5 Lít/can',
          costPrice: 280000,
          sellingPrice: 360000,
          minStock: 4,
          trackedSerial: false),
      InventoryItem(
          id: 'cccccccc-cccc-4ccc-8ccc-cccccccccc25',
          sku: 'DUONG-DEN-HQ',
          name: 'Đường Đen Nấu Hàn Quốc Beksul',
          unit: 'gói',
          category: 'Đường & Gia vị',
          packaging: '1kg/gói',
          costPrice: 52000,
          sellingPrice: 75000,
          minStock: 6,
          trackedSerial: false),
      InventoryItem(
          id: 'cccccccc-cccc-4ccc-8ccc-cccccccccc26',
          sku: 'LY-PP-700ML',
          name: 'Ly Nhựa PP Trong 700ml',
          unit: 'cái',
          category: 'Bao bì',
          packaging: '50 cái/cây',
          costPrice: 850,
          sellingPrice: 1500,
          minStock: 200,
          trackedSerial: false),
      InventoryItem(
          id: 'cccccccc-cccc-4ccc-8ccc-cccccccccc27',
          sku: 'LY-GIAY-500ML',
          name: 'Ly Giấy Nóng Tráng PE 500ml',
          unit: 'cái',
          category: 'Bao bì',
          packaging: '50 cái/cây',
          costPrice: 950,
          sellingPrice: 1600,
          minStock: 100,
          trackedSerial: false),
      InventoryItem(
          id: 'cccccccc-cccc-4ccc-8ccc-cccccccccc28',
          sku: 'NAP-CAU-PHI95',
          name: 'Nắp Cầu Nhựa PET Phi 95',
          unit: 'cái',
          category: 'Bao bì',
          packaging: '100 cái/cây',
          costPrice: 400,
          sellingPrice: 800,
          minStock: 200,
          trackedSerial: false),
      InventoryItem(
          id: 'cccccccc-cccc-4ccc-8ccc-cccccccccc29',
          sku: 'CUON-MANG-EP',
          name: 'Cuộn Màng Ép Miệng Ly Trà Sữa',
          unit: 'cuộn',
          category: 'Bao bì',
          packaging: '3000 nắp/cuộn',
          costPrice: 120000,
          sellingPrice: 180000,
          minStock: 2,
          trackedSerial: false),
      InventoryItem(
          id: 'cccccccc-cccc-4ccc-8ccc-cccccccccc30',
          sku: 'ONG-HUT-PP',
          name: 'Ống Hút Phi 12 Trà Sữa Bọc Màng',
          unit: 'gói',
          category: 'Bao bì',
          packaging: '100 cái/gói',
          costPrice: 15000,
          sellingPrice: 25000,
          minStock: 10,
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
          quantity: '180.000'),
      StockBalance(
          locationId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
          itemId: 'cccccccc-cccc-4ccc-8ccc-ccccccccccc3',
          quantity: '120.000'),
      StockBalance(
          locationId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
          itemId: 'cccccccc-cccc-4ccc-8ccc-ccccccccccc4',
          quantity: '45.000'),
      StockBalance(
          locationId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
          itemId: 'cccccccc-cccc-4ccc-8ccc-ccccccccccc5',
          quantity: '35.000'),
      StockBalance(
          locationId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
          itemId: 'cccccccc-cccc-4ccc-8ccc-ccccccccccc6',
          quantity: '160.000'),
      StockBalance(
          locationId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
          itemId: 'cccccccc-cccc-4ccc-8ccc-ccccccccccc7',
          quantity: '85.000'),
      StockBalance(
          locationId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
          itemId: 'cccccccc-cccc-4ccc-8ccc-ccccccccccc8',
          quantity: '70.000'),
      StockBalance(
          locationId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2',
          itemId: 'cccccccc-cccc-4ccc-8ccc-ccccccccccc9',
          quantity: '3.000'),
      StockBalance(
          locationId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
          itemId: 'cccccccc-cccc-4ccc-8ccc-cccccccccc10',
          quantity: '22.000'),
      StockBalance(
          locationId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
          itemId: 'cccccccc-cccc-4ccc-8ccc-cccccccccc11',
          quantity: '30.000'),
      StockBalance(
          locationId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2',
          itemId: 'cccccccc-cccc-4ccc-8ccc-cccccccccc12',
          quantity: '40.000'),
      StockBalance(
          locationId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
          itemId: 'cccccccc-cccc-4ccc-8ccc-cccccccccc13',
          quantity: '110.000'),
      StockBalance(
          locationId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
          itemId: 'cccccccc-cccc-4ccc-8ccc-cccccccccc14',
          quantity: '50.000'),
      StockBalance(
          locationId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
          itemId: 'cccccccc-cccc-4ccc-8ccc-cccccccccc15',
          quantity: '42.000'),
      StockBalance(
          locationId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
          itemId: 'cccccccc-cccc-4ccc-8ccc-cccccccccc16',
          quantity: '65.000'),
      StockBalance(
          locationId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
          itemId: 'cccccccc-cccc-4ccc-8ccc-cccccccccc17',
          quantity: '28.000'),
      StockBalance(
          locationId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
          itemId: 'cccccccc-cccc-4ccc-8ccc-cccccccccc18',
          quantity: '38.000'),
      StockBalance(
          locationId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
          itemId: 'cccccccc-cccc-4ccc-8ccc-cccccccccc19',
          quantity: '25.000'),
      StockBalance(
          locationId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
          itemId: 'cccccccc-cccc-4ccc-8ccc-cccccccccc20',
          quantity: '16.000'),
      StockBalance(
          locationId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
          itemId: 'cccccccc-cccc-4ccc-8ccc-cccccccccc21',
          quantity: '19.000'),
      StockBalance(
          locationId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
          itemId: 'cccccccc-cccc-4ccc-8ccc-cccccccccc22',
          quantity: '14.000'),
      StockBalance(
          locationId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2',
          itemId: 'cccccccc-cccc-4ccc-8ccc-cccccccccc23',
          quantity: '2.000'),
      StockBalance(
          locationId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
          itemId: 'cccccccc-cccc-4ccc-8ccc-cccccccccc24',
          quantity: '15.000'),
      StockBalance(
          locationId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
          itemId: 'cccccccc-cccc-4ccc-8ccc-cccccccccc25',
          quantity: '32.000'),
      StockBalance(
          locationId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb3',
          itemId: 'cccccccc-cccc-4ccc-8ccc-cccccccccc26',
          quantity: '1200.000'),
      StockBalance(
          locationId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb3',
          itemId: 'cccccccc-cccc-4ccc-8ccc-cccccccccc27',
          quantity: '650.000'),
      StockBalance(
          locationId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb3',
          itemId: 'cccccccc-cccc-4ccc-8ccc-cccccccccc28',
          quantity: '1500.000'),
      StockBalance(
          locationId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb3',
          itemId: 'cccccccc-cccc-4ccc-8ccc-cccccccccc29',
          quantity: '8.000'),
      StockBalance(
          locationId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb3',
          itemId: 'cccccccc-cccc-4ccc-8ccc-cccccccccc30',
          quantity: '75.000'),
    ];

List<AssetRecord> _seedAssets() => const [];

List<AssetLogItem> _seedAssetLogs() => const [];

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
          createdByName: 'Nguyễn Thị Mai',
          locationId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
          items: const [
            StockRequestLine(
                itemId: 'cccccccc-cccc-4ccc-8ccc-ccccccccccc1',
                quantity: '10.000')
          ],
          reason: 'Nhập bổ sung trà đen cho ca sáng cuối tuần',
          createdAt: DateTime.utc(2026, 10, 5)),
      StockRequest(
          id: 'sr-0002',
          kind: RequestKind.payment,
          status: RequestStatus.pending,
          version: 1,
          createdBy: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2',
          createdByName: 'Trần Văn Quản Lý',
          locationId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2',
          items: const [
            StockRequestLine(
                itemId: 'cccccccc-cccc-4ccc-8ccc-ccccccccccc2',
                quantity: '1.000')
          ],
          reason: 'Xuất trà lài bổ sung quầy pha chế ca chiều',
          createdAt: DateTime.utc(2026, 10, 6)),
    ];

List<Cashbox> _seedCashboxes() => const [
      Cashbox(
          id: '11111111-1111-4111-8111-111111111111',
          code: 'CASH-POS-01',
          name: 'Quầy Thu Ngân 01 (POS-01)',
          openingBalance: '4250000.00'),
      Cashbox(
          id: '11111111-1111-4111-8111-111111111112',
          code: 'CASH-POS-02',
          name: 'Quầy Thu Ngân 02 (POS-02)',
          openingBalance: '1000000.00'),
      Cashbox(
          id: '11111111-1111-4111-8111-111111111113',
          code: 'CASH-SAFE-01',
          name: 'Két Sắt Trung Tâm Chi Nhánh',
          openingBalance: '50000000.00'),
    ];

List<CashBalance> _seedCashBalances() => const [
      CashBalance(
          cashboxId: '11111111-1111-4111-8111-111111111111',
          amount: '4250000.00',
          currency: 'VND'),
      CashBalance(
          cashboxId: '11111111-1111-4111-8111-111111111112',
          amount: '1000000.00',
          currency: 'VND'),
      CashBalance(
          cashboxId: '11111111-1111-4111-8111-111111111113',
          amount: '50000000.00',
          currency: 'VND'),
    ];

List<JournalEntry> _seedJournals() => [
      JournalEntry(
          id: 'je-0001',
          cashboxId: '11111111-1111-4111-8111-111111111111',
          kind: 'receipt',
          amount: '5000000.00',
          currency: 'VND',
          reason: 'Tiền mặt đầu ca trực quầy thu ngân',
          createdAt: DateTime.utc(2026, 10, 1)),
    ];

List<CashRequest> _seedCashRequests() => [
      CashRequest(
          id: 'cr-0001',
          kind: RequestKind.receipt,
          status: RequestStatus.draft,
          version: 1,
          cashboxId: '11111111-1111-4111-8111-111111111111',
          amount: '2000000.00',
          currency: 'VND',
          reason: 'Nộp tiền mặt bán lẻ ca tối hôm trước',
          createdBy: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
          createdByName: 'Nguyễn Thị Mai (Pha Chế)',
          createdAt: DateTime.utc(2026, 10, 5)),
      CashRequest(
          id: 'cr-0002',
          kind: RequestKind.payment,
          status: RequestStatus.pending,
          version: 1,
          cashboxId: '11111111-1111-4111-8111-111111111111',
          amount: '150000.00',
          currency: 'VND',
          reason: 'Rút tiền mặt thanh toán đá viên ca sáng',
          createdBy: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
          createdByName: 'Nguyễn Thị Mai (Pha Chế)',
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
    ];

List<IntegrationConnection> _seedConnections() => const [];

List<IntegrationRun> _seedRuns() => const [];

List<ReconciliationRun> _seedReconciliations() => [
      ReconciliationRun(
          id: 'rr-0001',
          status: 'completed',
          startedAt: DateTime.utc(2026, 10, 8, 7, 0),
          exceptions: const ['CHENH-LECH-CA-01']),
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
        sku: 'TRA-LAI-500G',
        name: 'Trà Xanh Hoa Lài Thượng Hạng',
        quantity: '4.000',
        daysSinceLastIssue: 98,
        severity: 'critical',
      ),
      StagnationItem(
        itemId: 'cccccccc-cccc-4ccc-8ccc-ccccccccccc1',
        sku: 'TRA-DEN-SO9',
        name: 'Trà Đen Lộc Phát Số 9',
        quantity: '100.000',
        daysSinceLastIssue: 45,
        severity: 'watch',
      ),
    ];
