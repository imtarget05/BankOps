import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kho_tra_sua/src/app/app_shell.dart';
import 'package:kho_tra_sua/src/core/theme/app_theme.dart';
import 'package:kho_tra_sua/src/data/models/dtos.dart';
import 'package:kho_tra_sua/src/data/repositories/fake_repository.dart';
import 'package:kho_tra_sua/src/features/admin/employee_management_screen.dart';

void main() {
  testWidgets(
    'Admin provisions new Administrator with email mainguyenbinhtan2005@gmail.com via email invite flow',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final repo = FakeBankOpsRepository(latency: Duration.zero);
      const adminUser = AppUser(
        id: 'emp_current_admin',
        username: 'super_admin',
        displayName: 'Quản Trị Viên Trưởng',
        roles: ['admin'],
        capabilities: ['iam:admin', 'admin:user_management'],
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

      // 1. Verify screen renders header and initial employees
      expect(find.text('Quản trị Nhân viên & Cấp phát IAM'), findsOneWidget);
      expect(find.byKey(const Key('admin-create-employee-btn')), findsOneWidget);

      // 2. Open Create Employee Dialog
      await tester.tap(find.byKey(const Key('admin-create-employee-btn')));
      await tester.pumpAndSettle();

      expect(find.text('Tạo tài khoản nhân viên mới'), findsOneWidget);

      // 3. Fill in account details for mainguyenbinhtan2005@gmail.com
      await tester.enterText(
        find.byKey(const Key('admin-create-username-input')),
        'mainguyenbinhtan',
      );
      await tester.enterText(
        find.byKey(const Key('admin-create-display-name-input')),
        'Mai Nguyễn Bình Tân',
      );
      await tester.enterText(
        find.byKey(const Key('admin-create-email-input')),
        'mainguyenbinhtan2005@gmail.com',
      );

      // 4. Select Admin role filter chip
      final adminChip = find.widgetWithText(FilterChip, 'Chủ Quán / Quản Trị Viên (Admin)');
      await tester.tap(adminChip);
      await tester.pumpAndSettle();

      // 5. Select invite_email radio option
      final inviteRadio = find.text('Gửi email mời kích hoạt');
      await tester.tap(inviteRadio);
      await tester.pumpAndSettle();

      // 6. Confirm creation
      await tester.tap(find.byKey(const Key('admin-create-employee-confirm-btn')));
      await tester.pumpAndSettle();

      // 7. Verify success confirmation modal appears
      expect(find.text('Đã gửi thư mời kích hoạt'), findsOneWidget);
      expect(
        find.textContaining('mainguyenbinhtan2005@gmail.com'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('admin-copy-invite-link-btn')), findsOneWidget);

      // 8. Close modal
      await tester.tap(find.text('Hoàn tất'));
      await tester.pumpAndSettle();

      // 9. Verify new administrator appears in employees list with Admin badge
      expect(find.text('Mai Nguyễn Bình Tân'), findsOneWidget);
      expect(find.textContaining('mainguyenbinhtan2005@gmail.com'), findsOneWidget);
    },
  );
}
