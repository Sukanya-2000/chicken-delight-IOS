import 'package:flutter_test/flutter_test.dart';
import 'package:chicken_delight/main.dart';

void main() {
  testWidgets('shows location landing screen', (tester) async {
    await tester.pumpWidget(const DelightApp());
    expect(find.text('CHICKEN DELIGHT'), findsOneWidget);
    expect(find.text('Find Chicken Delight near you'), findsOneWidget);
  });
}
