import 'package:bankops/src/app/app_shell.dart';
import 'package:bankops/src/core/theme/app_theme.dart';
import 'package:bankops/src/data/models/dtos.dart';
import 'package:bankops/src/data/repositories/fake_repository.dart';
import 'package:bankops/src/features/admin/employee_management_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'EmployeeManagementScreen denies access when user lacks IAM admin capability',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final repo = FakeBankOpsRepository(latency: Duration.zero);
      const regularUser = AppUser(
        id: 'usr_staff',
        username: 'staff_user',
        displayName: 'Nhân viên',
        roles: ['staff'],
        capabilities: ['inventory:create_request'],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: SessionScope(
            user: regularUser,
            child: RepositoryScope(
              repository: repo,
              child: const Scaffold(body: EmployeeManagementScreen()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Từ chối quyền truy cập'), findsOneWidget);
      expect(
        find.textContaining('capability iam:admin'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'EmployeeManagementScreen displays employees, stats, and creates new employee',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final repo = FakeBankOpsRepository(latency: Duration.zero);
      const adminUser = AppUser(
        id: 'emp_1',
        username: 'demo_admin',
        displayName: 'Phạm Minh Trị (Admin)',
        roles: ['admin'],
        capabilities: ['iam:admin', 'etl:admin'],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: SessionScope(
            user: adminUser,
            child: RepositoryScope(
              repository: repo,
              child: const Scaffold(body: EmployeeManagementScreen()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify header and stats
      expect(find.text('Quản trị Nhân viên & Cấp phát IAM'), findsOneWidget);
      expect(find.text('Tổng nhân sự'), findsOneWidget);
      expect(find.text('Đang hoạt động'), findsOneWidget);

      // Verify seeded employees appear
      expect(find.text('Phạm Minh Trị (Admin)'), findsOneWidget);
      expect(find.text('Nguyễn Hoàng An (GDV)'), findsOneWidget);
      expect(find.text('Trần Tuấn Bình (KSV)'), findsOneWidget);

      // Test create employee dialog
      await tester.tap(find.byKey(const Key('admin-create-employee-btn')));
      await tester.pumpAndSettle();

      expect(find.text('Tạo tài khoản nhân viên mới'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('admin-create-username-input')),
        'le.thi.c',
      );
      await tester.enterText(
        find.byKey(const Key('admin-create-display-name-input')),
        'Lê Thị C',
      );
      await tester.enterText(
        find.byKey(const Key('admin-create-email-input')),
        'c.le@bankops.internal',
      );

      await tester.tap(find.byKey(const Key('admin-create-employee-confirm-btn')));
      await tester.pumpAndSettle();

      // Verify success dialog appears for temporary password
      expect(find.text('Tạo nhân viên thành công'), findsOneWidget);
      expect(find.textContaining('Đã khởi tạo tài khoản "le.thi.c"'), findsOneWidget);

      await tester.tap(find.text('Hoàn tất'));
      await tester.pumpAndSettle();

      // Verify the new employee appears in list
      expect(find.text('Lê Thị C'), findsOneWidget);
    },
  );
}
