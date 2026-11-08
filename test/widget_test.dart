import 'package:emby_downloader/ui/login_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('login form asks for a server and username before submitting', (tester) async {
    var submitted = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: LoginForm(onSubmit: (_) async => submitted++),
      ),
    );

    expect(find.text('Emby 下载'), findsOneWidget);
    await tester.tap(find.text('登录'));
    await tester.pump();
    expect(find.text('请填写服务器地址和用户名'), findsOneWidget);
    expect(submitted, 0);

    await tester.enterText(find.widgetWithText(TextField, '服务器地址'), 'http://192.168.1.10:8096');
    await tester.enterText(find.widgetWithText(TextField, '用户名'), 'me');
    await tester.enterText(find.widgetWithText(TextField, '密码'), 'secret');
    await tester.tap(find.text('登录'));
    await tester.pump();
    expect(submitted, 1);
  });
}
