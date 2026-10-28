import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slate/data/demo_repository.dart';
import 'package:slate/main.dart';
import 'package:slate/widgets/common.dart';

/// Drives the app on demo data at iPhone 17 Pro Max size.
void main() {
  Future<DemoRepository> launch(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1320, 2868);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final repo = DemoRepository(latency: Duration.zero);
    await tester.pumpWidget(CardApp(repository: repo));
    expect(find.text('SLATE'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1400)); // splash
    await tester.pump(const Duration(milliseconds: 200)); // login waits a beat
    await tester.pumpAndSettle(); // intro animation
    return repo;
  }

  Finder pill(String label) => find.widgetWithText(PillButton, label);

  Future<void> logIn(WidgetTester tester) async {
    await tester.enterText(find.byType(TextFormField).at(0), 'alex@slate.app');
    await tester.enterText(find.byType(TextFormField).at(1), 'slate1234');
    await tester.tap(pill('Login'));
    await tester.pumpAndSettle();
  }

  testWidgets('login validates, then opens the home screen', (tester) async {
    await launch(tester);
    expect(find.text('Welcome back! Log in to continue.'), findsOneWidget);

    await tester.tap(pill('Login'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid email address.'), findsOneWidget);
    expect(find.text('Password should be at least 6 characters.'), findsOneWidget);

    await logIn(tester);
    expect(find.text('Hello Alex'), findsOneWidget);
    expect(find.text(r'$22,000'), findsOneWidget);
    expect(find.text('Recent transactions'), findsOneWidget);
    expect(find.text(r'+$2,400.00'), findsOneWidget);
  });

  testWidgets('sign-up mode asks for a name', (tester) async {
    await launch(tester);
    await tester.tap(find.textContaining('Create an account', findRichText: true));
    await tester.pumpAndSettle();
    expect(find.text('Full name'), findsOneWidget);
    expect(pill('Create account'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).at(0), 'Sam Lee');
    await tester.enterText(find.byType(TextFormField).at(1), 'sam.lee@example.com');
    await tester.enterText(find.byType(TextFormField).at(2), 'hunter22');
    await tester.tap(pill('Create account'));
    await tester.pumpAndSettle();
    expect(find.text('Hello Sam'), findsOneWidget);
  });

  testWidgets('order a Silver card from the plan picker', (tester) async {
    final semantics = tester.ensureSemantics();
    await launch(tester);
    await logIn(tester);

    await tester.tap(find.bySemanticsLabel('Move money'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New card'));
    await tester.pumpAndSettle();
    expect(pill('Choose Platinum'), findsOneWidget);
    expect(find.textContaining(r'$249', findRichText: true), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(-320, 0));
    await tester.pumpAndSettle();
    expect(pill('Choose Silver'), findsOneWidget);

    await tester.tap(pill('Choose Silver'));
    await tester.pumpAndSettle();
    expect(find.text(r'$99.00 for the first year, paid from your balance.'), findsOneWidget);
    await tester.tap(pill(r'Pay $99.00'));
    await tester.pumpAndSettle();

    expect(find.text('Your Silver card is ready.'), findsOneWidget);
    expect(find.text(r'$21,901'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('logging out returns to the login screen', (tester) async {
    final semantics = tester.ensureSemantics();
    final repo = await launch(tester);
    await logIn(tester);
    await tester.tap(find.bySemanticsLabel('Profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log out'));
    await tester.pumpAndSettle();
    expect(repo.isSignedIn, isFalse);
    expect(find.text('Welcome back! Log in to continue.'), findsOneWidget);
    expect(find.text('Hello Alex'), findsNothing);
    semantics.dispose();
  });

  testWidgets('every tab fits an iPhone SE with 130% text', (tester) async {
    tester.view.physicalSize = const Size(750, 1334);
    tester.view.devicePixelRatio = 2;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(CardApp(repository: DemoRepository(latency: Duration.zero)));
    await tester.pump(const Duration(milliseconds: 1400));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    await logIn(tester);
    for (final tab in ['Transfer', 'Cards', 'Profile', 'Home']) {
      await tester.tap(find.bySemanticsLabel(tab));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.bySemanticsLabel('Move money'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New card'));
    await tester.pumpAndSettle();
    expect(pill('Choose Platinum'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('send money after the recipient is confirmed', (tester) async {
    final semantics = tester.ensureSemantics();
    final repo = await launch(tester);
    await logIn(tester);

    await tester.tap(find.bySemanticsLabel('Transfer'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '125');
    await tester.pump();
    // The button stays disabled until the email belongs to a member.
    final send = pill(r'Send $125.00');
    expect(tester.widget<PillButton>(send).onPressed, isNull);

    await tester.enterText(fields.at(1), 'jamie@slate.app');
    await tester.pump(const Duration(milliseconds: 500)); // lookup debounce
    await tester.pumpAndSettle();
    expect(find.text('Jamie Rivera'), findsOneWidget);
    expect(tester.widget<PillButton>(send).onPressed, isNotNull);

    await tester.tap(send);
    await tester.pumpAndSettle();
    expect(find.text(r'Sent $125.00 to Jamie Rivera'), findsOneWidget);
    expect(find.text(r'New balance $21,875.00'), findsOneWidget);
    final usd = (await repo.fetchWallets()).firstWhere((w) => w.currency == 'USD');
    expect(usd.balanceCents, 2187500);
    semantics.dispose();
  });
}
