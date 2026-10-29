import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slate/data/demo_repository.dart';
import 'package:slate/data/models.dart';
import 'package:slate/main.dart';
import 'package:slate/state/app_state.dart';
import 'package:slate/widgets/card_art.dart';
import 'package:slate/widgets/card_designs.dart';
import 'package:slate/widgets/card_slots.dart';
import 'package:slate/widgets/common.dart';

void main() {
  Future<void> launch(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1320, 2868);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(CardApp(repository: DemoRepository(latency: Duration.zero)));
    await tester.pump(const Duration(milliseconds: 1400));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'alex@slate.app');
    await tester.enterText(find.byType(TextFormField).at(1), 'slate1234');
    await tester.tap(find.widgetWithText(PillButton, 'Login'));
    await tester.pumpAndSettle();
  }

  Finder front(String card) => find.bySemanticsLabel(RegExp('^$card, card \\d+ of 6\$'));
  Finder carousel() => find.bySemanticsLabel(RegExp(r', card \d+ of 6$'));

  Future<void> openFromHome(WidgetTester tester) async {
    await tester.tap(find.bySemanticsLabel('Slate Platinum ending 4821'));
    await tester.pumpAndSettle();
  }

  testWidgets('tapping the home card opens the carousel on that card', (tester) async {
    final semantics = tester.ensureSemantics();
    await launch(tester);
    await openFromHome(tester);
    expect(front('Slate Platinum ending 4821'), findsOneWidget);
    expect(find.text('1 of 6'), findsOneWidget);
    expect(find.text('Slate Platinum'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('swipe or tap a neighbour to move round the ring', (tester) async {
    final semantics = tester.ensureSemantics();
    await launch(tester);
    await openFromHome(tester);

    await tester.drag(carousel(), const Offset(-260, 0));
    await tester.pumpAndSettle();
    expect(front('Amex Centurion ending 1009'), findsOneWidget);

    await tester.tapAt(tester.getRect(carousel()).centerRight - const Offset(8, 0));
    await tester.pumpAndSettle();
    expect(front('Amex Platinum ending 2003'), findsOneWidget);
    expect(find.text('3 of 6'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('a flick spins past several cards and lands on one', (tester) async {
    final semantics = tester.ensureSemantics();
    await launch(tester);
    await openFromHome(tester);
    await tester.fling(carousel(), const Offset(-200, 0), 2200);
    await tester.pumpAndSettle();
    final label = tester.getSemantics(carousel()).label;
    final position = int.parse(RegExp(r'card (\d+) of 6').firstMatch(label)!.group(1)!);
    expect(position, greaterThan(2), reason: 'momentum carried it past the next card');
    final page = tester.widget<PageView>(find.byType(PageView)).controller!.page!;
    expect(page, closeTo(position - 1, 0.001), reason: 'it settles exactly on a card');
    semantics.dispose();
  });

  testWidgets('tapping the front card turns it over and back', (tester) async {
    final semantics = tester.ensureSemantics();
    await launch(tester);
    await openFromHome(tester);
    // Cards round the back of the ring show their backs too, so look at this card only.
    Finder platinum({required bool back}) =>
        find.byWidgetPredicate((w) => w is CardArt && w.last4 == '4821' && w.back == back);
    expect(platinum(back: true), findsNothing);
    await tester.tap(find.bySemanticsLabel('Turn over'));
    await tester.pumpAndSettle();
    expect(platinum(back: true), findsOneWidget);
    expect(platinum(back: false), findsNothing);
    expect(find.text('••••  ••••  ••••  4821'), findsOneWidget);
    await tester.tapAt(tester.getRect(carousel()).center);
    await tester.pumpAndSettle();
    expect(platinum(back: true), findsNothing);
    semantics.dispose();
  });

  testWidgets('Details opens the card sheet', (tester) async {
    final semantics = tester.ensureSemantics();
    await launch(tester);
    await openFromHome(tester);
    await tester.tap(find.bySemanticsLabel('Details'));
    await tester.pumpAndSettle();
    expect(find.text('Card number'), findsOneWidget);
    expect(find.text('Freeze card'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('closing lands the home row on the card the carousel ended on', (tester) async {
    final semantics = tester.ensureSemantics();
    await launch(tester);
    final first = tester.getRect(find.bySemanticsLabel('Slate Platinum ending 4821'));
    await openFromHome(tester);
    await tester.drag(carousel(), const Offset(-260, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Close'));
    await tester.pumpAndSettle();
    expect(carousel(), findsNothing);
    final now = tester.getRect(find.bySemanticsLabel('Amex Centurion ending 1009'));
    expect(now.left, closeTo(first.left, 0.5));
    semantics.dispose();
  });

  testWidgets('pulling the cards down closes the carousel', (tester) async {
    final semantics = tester.ensureSemantics();
    await launch(tester);
    await openFromHome(tester);
    await tester.drag(carousel(), const Offset(0, 60));
    await tester.pumpAndSettle();
    expect(carousel(), findsOneWidget, reason: 'a short pull springs back');
    await tester.drag(carousel(), const Offset(0, 200));
    await tester.pumpAndSettle();
    expect(carousel(), findsNothing);
    expect(find.text('Recent transactions'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('fits a small phone in a browser, with a long custom card', (tester) async {
    final semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(375 * 3, 548 * 3); // iPhone SE in Safari
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final repo = DemoRepository(latency: Duration.zero);
    await tester.pumpWidget(CardApp(repository: repo));
    await tester.pump(const Duration(milliseconds: 1400));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'alex@slate.app');
    await tester.enterText(find.byType(TextFormField).at(1), 'slate1234');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    final state = AppScope.read(tester.element(find.text('Recent transactions')));
    // The demo repository answers on a timer, so let the test clock run while it does.
    final adding = state.addLinkedCard(const NewLinkedCard(
      designId: 'custom_blue',
      issuer: 'A Very Long Credit Union Name Indeed',
      product: 'Rewards Signature Preferred Plus',
      network: CardNetwork.visa,
      last4: '0042',
      holderName: 'Alex Carter',
      nickname: 'The one with the very long nickname for testing',
    ));
    await tester.pumpAndSettle();
    await adding;
    await openFromHome(tester);
    final seven = find.bySemanticsLabel(RegExp(r', card \d+ of 7$'));
    await tester.fling(seven, const Offset(-300, 0), 4000);
    await tester.pumpAndSettle();
    await tester.fling(seven, const Offset(-300, 0), 4000);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp(r'^A Very Long Credit Union.*card 7 of 7$')), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  test('every design has both pictures, and every slot table belongs to one', () {
    final designs = [
      CardCatalog.slatePlatinum,
      CardCatalog.slateSilver,
      CardCatalog.slateGold,
      ...CardCatalog.addable,
      for (final entry in CardCatalog.customColors.entries)
        CardDesign(id: entry.key, issuer: 'Bank', product: 'Card', network: CardNetwork.visa, material: entry.value),
    ];
    for (final d in designs) {
      expect(File(d.frontArt).existsSync(), isTrue, reason: d.frontArt);
      expect(File(d.backArt).existsSync(), isTrue, reason: d.backArt);
    }
    for (final name in cardSlots.keys) {
      expect(File('assets/cards/$name.webp').existsSync(), isTrue, reason: 'slots for $name');
    }
  });

  testWidgets('every design draws its front and back without errors', (tester) async {
    tester.view.physicalSize = const Size(1200, 6000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final custom = CardCatalog.forCard(LinkedCard(
      id: 'c',
      designId: 'custom_rose',
      issuer: 'A Very Long Credit Union Name Indeed',
      product: 'Rewards Signature Preferred',
      network: CardNetwork.discover,
      last4: '0042',
      holderName: 'Alexandra Catherine Montgomery-Smythe',
      createdAt: DateTime(2026),
    ));
    final designs = [...CardCatalog.addable, CardCatalog.slatePlatinum, CardCatalog.slateGold, custom];
    await tester.pumpWidget(MaterialApp(
      home: Material(
        child: ListView(
          children: [
            for (final d in designs)
              for (final back in [false, true])
                for (final width in [160.0, 392.0])
                  Center(
                    child: SizedBox(
                      width: width,
                      child: CardArt(
                        design: d,
                        holderName: 'Alexandra Catherine Montgomery-Smythe',
                        last4: '1009',
                        memberSince: '21',
                        back: back,
                      ),
                    ),
                  ),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
