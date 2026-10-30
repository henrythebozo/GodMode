import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slate/data/demo_repository.dart';
import 'package:slate/main.dart';
import 'package:slate/widgets/card_art.dart';
import 'package:slate/widgets/common.dart';

void main() {
  Future<void> openCardsTab(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1290, 2796); // iPhone 15 Pro Max
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
    await tester.tap(find.bySemanticsLabel('Cards'));
    await tester.pumpAndSettle();
  }

  Finder shelf() => find.bySemanticsLabel(RegExp(r', card \d+ of 6$'));
  Finder face(String last4, {required bool back}) =>
      find.byWidgetPredicate((w) => w is CardArt && w.last4 == last4 && w.back == back);

  /// Pumps frame by frame for [duration], noting whether [finder] ever matched.
  Future<bool> seenWhilePumping(WidgetTester tester, Finder finder, Duration duration) async {
    var seen = false;
    for (var t = Duration.zero; t < duration; t += const Duration(milliseconds: 16)) {
      await tester.pump(const Duration(milliseconds: 16));
      seen |= finder.evaluate().isNotEmpty;
    }
    return seen;
  }

  testWidgets('the Cards tab shows the cards standing up, first one in front', (tester) async {
    final semantics = tester.ensureSemantics();
    await openCardsTab(tester);
    expect(find.bySemanticsLabel('Slate Platinum ending 4821, card 1 of 6'), findsOneWidget);
    expect(find.text('Slate Platinum'), findsOneWidget);
    expect(find.byType(PortraitCard), findsWidgets);
    final card = tester.getRect(find.byType(PortraitCard).first);
    expect(card.height, greaterThan(card.width), reason: 'upright');
    semantics.dispose();
  });

  testWidgets('the card you slide past spins round in the gust and lands face up', (tester) async {
    final semantics = tester.ensureSemantics();
    await openCardsTab(tester);
    await tester.drag(shelf(), const Offset(-300, 0));
    // Half way round the spin, the Slate card shows its back.
    expect(await seenWhilePumping(tester, face('4821', back: true), const Duration(milliseconds: 900)), isTrue);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Amex Centurion ending 1009, card 2 of 6'), findsOneWidget);
    expect(face('4821', back: true), findsNothing, reason: 'it settles face up');
    expect(face('1009', back: true), findsNothing, reason: 'the card you landed on does not spin');
    semantics.dispose();
  });

  testWidgets('a flick runs through several cards, spinning each, and lands on one', (tester) async {
    final semantics = tester.ensureSemantics();
    await openCardsTab(tester);
    await tester.fling(shelf(), const Offset(-200, 0), 2400);
    final sawCenturionBack = await seenWhilePumping(tester, face('1009', back: true), const Duration(milliseconds: 900));
    await tester.pumpAndSettle();
    final label = tester.getSemantics(shelf()).label;
    final position = int.parse(RegExp(r'card (\d+) of 6').firstMatch(label)!.group(1)!);
    expect(position, greaterThan(2), reason: 'momentum carried it past the next card');
    expect(sawCenturionBack, isTrue, reason: 'a card it ran past spun');
    final page = tester.widget<PageView>(find.byType(PageView).last).controller!.page!;
    expect(page, closeTo(position - 1, 0.001), reason: 'it settles exactly on a card');
    expect(find.byWidgetPredicate((w) => w is CardArt && w.back), findsNothing, reason: 'all face up again');
    semantics.dispose();
  });

  testWidgets('tapping the front card turns it over, and again turns it back', (tester) async {
    final semantics = tester.ensureSemantics();
    await openCardsTab(tester);
    await tester.tapAt(tester.getRect(shelf()).center);
    await tester.pumpAndSettle();
    expect(face('4821', back: true), findsOneWidget);
    expect(find.text('••••  ••••  ••••  4821'), findsOneWidget);
    await tester.tapAt(tester.getRect(shelf()).center);
    await tester.pumpAndSettle();
    expect(face('4821', back: true), findsNothing);
    semantics.dispose();
  });

  testWidgets('sliding away from a card left face down spins it back face up', (tester) async {
    final semantics = tester.ensureSemantics();
    await openCardsTab(tester);
    await tester.tapAt(tester.getRect(shelf()).center);
    await tester.pumpAndSettle();
    expect(face('4821', back: true), findsOneWidget);
    await tester.drag(shelf(), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(face('4821', back: true), findsNothing);
    semantics.dispose();
  });

  testWidgets('tapping a neighbour slides it in; Details opens the sheet for the front card', (tester) async {
    final semantics = tester.ensureSemantics();
    await openCardsTab(tester);
    await tester.tapAt(tester.getRect(shelf()).centerRight - const Offset(12, 0));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Amex Centurion ending 1009, card 2 of 6'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Details'));
    await tester.pumpAndSettle();
    expect(find.text('Remove card'), findsOneWidget);
    expect(find.text('American Express'), findsOneWidget);
    semantics.dispose();
  });
}
