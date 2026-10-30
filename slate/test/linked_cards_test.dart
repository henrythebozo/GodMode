import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slate/data/demo_repository.dart';
import 'package:slate/data/models.dart';
import 'package:slate/data/slate_repository.dart';
import 'package:slate/main.dart';
import 'package:slate/widgets/card_designs.dart';
import 'package:slate/widgets/common.dart';

void main() {
  group('demo repository', () {
    late DemoRepository repo;

    setUp(() async {
      repo = DemoRepository(latency: Duration.zero);
      await repo.signIn(email: 'alex@slate.app', password: 'slate1234');
    });

    Matcher fails(String message) =>
        throwsA(isA<SlateException>().having((e) => e.message, 'message', message));

    NewLinkedCard card({String design = 'citi_strata_premier', String last4 = '4242'}) => NewLinkedCard(
          designId: design,
          issuer: 'Citi',
          product: 'Strata Premier',
          network: CardNetwork.mastercard,
          last4: last4,
          holderName: 'Alex Carter',
        );

    test('the demo account carries cards from several banks', () async {
      final cards = await repo.fetchLinkedCards();
      expect(cards.map((c) => c.designId), [
        'amex_centurion',
        'amex_platinum',
        'chase_sapphire_reserve',
        'capital_one_venture_x',
        'amex_gold',
      ]);
      expect({for (final c in cards) c.issuer}, {'American Express', 'Chase', 'Capital One'});
    });

    test('adds and removes a card', () async {
      final added = await repo.addLinkedCard(card());
      expect((await repo.fetchLinkedCards()).last.id, added.id);
      await repo.removeLinkedCard(added.id);
      expect((await repo.fetchLinkedCards()).any((c) => c.id == added.id), isFalse);
      await expectLater(() => repo.removeLinkedCard(added.id), fails('Card not found.'));
    });

    test('follows the same rules as the database', () async {
      await expectLater(() => repo.addLinkedCard(card(last4: '12a4')), fails('Enter the last 4 digits of the card.'));
      await expectLater(() => repo.addLinkedCard(card(last4: '12345')), fails('Enter the last 4 digits of the card.'));
      await expectLater(() => repo.addLinkedCard(card(design: 'Not a slug')), fails('Pick a card design.'));
      await expectLater(() => repo.addLinkedCard(card(design: 'amex_platinum', last4: '2003')),
          fails("You've already added this card."));
      for (var i = 0; i < 15; i++) {
        await repo.addLinkedCard(card(last4: i.toString().padLeft(4, '0')));
      }
      await expectLater(() => repo.addLinkedCard(card(last4: '9999')), fails('You can add up to 20 cards.'));
    });
  });

  test('catalog designs resolve; custom cards keep the names typed in', () {
    final known = LinkedCard(
      id: '1',
      designId: 'amex_centurion',
      issuer: 'American Express',
      product: 'Centurion',
      network: CardNetwork.amex,
      last4: '1009',
      holderName: 'A',
      createdAt: DateTime(2026),
    );
    expect(CardCatalog.forCard(known), same(CardCatalog.amexCenturion));
    expect(CardCatalog.forCard(known).name, 'Amex Centurion');

    final custom = LinkedCard(
      id: '2',
      designId: 'custom_green',
      issuer: 'Wells Fargo',
      product: 'Autograph',
      network: CardNetwork.visa,
      last4: '1111',
      holderName: 'A',
      createdAt: DateTime(2026),
    );
    final design = CardCatalog.forCard(custom);
    expect(design.name, 'Wells Fargo Autograph');
    expect(design.material, same(CardCatalog.customColors['custom_green']));
  });

  group('app', () {
    Future<DemoRepository> launch(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1320, 2868);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final repo = DemoRepository(latency: Duration.zero);
      await tester.pumpWidget(CardApp(repository: repo));
      await tester.pump(const Duration(milliseconds: 1400));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), 'alex@slate.app');
      await tester.enterText(find.byType(TextFormField).at(1), 'slate1234');
      await tester.tap(find.widgetWithText(PillButton, 'Login'));
      await tester.pumpAndSettle();
      return repo;
    }

    testWidgets('the home row starts with the Slate card and ends with Add', (tester) async {
      final semantics = tester.ensureSemantics();
      await launch(tester);
      expect(find.bySemanticsLabel('Slate Platinum ending 4821'), findsOneWidget);
      // Swipe to the end of the row.
      for (var i = 0; i < 6; i++) {
        await tester.drag(find.byType(PageView).first, const Offset(-420, 0));
        await tester.pumpAndSettle();
      }
      expect(find.bySemanticsLabel('Amex Gold ending 3008'), findsOneWidget);
      expect(find.bySemanticsLabel('Add a card'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('tapping the peeking card slides it in instead of opening anything', (tester) async {
      final semantics = tester.ensureSemantics();
      await launch(tester);
      // Semantics rects cover the whole page (card plus its gap), so compare
      // the second card's position with where the first one started.
      final first = tester.getRect(find.bySemanticsLabel('Slate Platinum ending 4821'));
      await tester.tapAt(Offset(436, first.center.dy)); // the sliver of the next card
      await tester.pumpAndSettle();
      expect(find.text('Card number'), findsNothing, reason: 'no card sheet opened');
      expect(tester.getRect(find.bySemanticsLabel('Amex Centurion ending 1009')).left, closeTo(first.left, 0.5));
      semantics.dispose();
    });

    testWidgets('add a card from the list, from the + menu', (tester) async {
      final semantics = tester.ensureSemantics();
      final repo = await launch(tester);
      await tester.tap(find.bySemanticsLabel('Move money'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add a card'));
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Citi Strata Premier'));
      await tester.pumpAndSettle();
      expect(find.text('Check the details, then add it to your wallet.'), findsOneWidget);

      await tester.tap(find.widgetWithText(PillButton, 'Add card'));
      await tester.pumpAndSettle();
      expect(find.text('Enter the last 4 digits.'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).at(0), '42x42'); // digits only, max 4
      await tester.enterText(find.byType(TextFormField).at(2), 'Points');
      await tester.tap(find.widgetWithText(PillButton, 'Add card'));
      await tester.pumpAndSettle();

      final added = (await repo.fetchLinkedCards()).last;
      expect((added.designId, added.last4, added.nickname), ('citi_strata_premier', '4242', 'Points'));
      expect(find.text('Citi Strata Premier added.'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('add an "Other card" from the Cards tab, then remove it', (tester) async {
      final semantics = tester.ensureSemantics();
      final repo = await launch(tester);
      await tester.tap(find.bySemanticsLabel('Cards'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Add a card'));
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Other card'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), 'Wells Fargo');
      await tester.enterText(find.byType(TextFormField).at(1), 'Autograph');
      await tester.tap(find.bySemanticsLabel('green'));
      await tester.enterText(find.byType(TextFormField).at(2), '1111');
      await tester.pump();
      expect(find.text('WELLS FARGO'), findsOneWidget, reason: 'the preview shows the bank');
      await tester.scrollUntilVisible(
        find.widgetWithText(PillButton, 'Add card'),
        200,
        scrollable: find.byType(Scrollable).first, // the form, not a text field's own scroller
      );
      await tester.ensureVisible(find.widgetWithText(PillButton, 'Add card'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(PillButton, 'Add card'));
      await tester.pumpAndSettle();

      final added = (await repo.fetchLinkedCards()).last;
      expect((added.issuer, added.product, added.designId), ('Wells Fargo', 'Autograph', 'custom_green'));

      // The shelf slides to the new card; once the "added" note above the
      // buttons has gone, Details opens its sheet.
      expect(find.bySemanticsLabel('Wells Fargo Autograph ending 1111, card 7 of 7'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Details'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(PillButton, 'Remove card'));
      await tester.pump();
      await tester.tap(find.widgetWithText(PillButton, 'Tap again to remove'));
      await tester.pumpAndSettle();
      expect((await repo.fetchLinkedCards()).any((c) => c.id == added.id), isFalse);
      semantics.dispose();
    });
  });
}
