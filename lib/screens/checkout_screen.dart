import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import '../models/models.dart';
import '../providers/app_state.dart';
import '../widgets/widgets.dart';

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});
  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController();
  final phone = TextEditingController();
  final email = TextEditingController();
  final address = TextEditingController();
  final cardNumber = TextEditingController();
  final cardExpiry = TextEditingController();
  final cardCvv = TextEditingController();
  bool submitting = false, scheduled = false;
  bool seededAddress = false;
  String? requiredField(String? value) =>
      value == null || value.trim().isEmpty ? 'Required' : null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!seededAddress) {
      address.text = context.read<AppState>().location;
      seededAddress = true;
    }
  }

  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    email.dispose();
    address.dispose();
    cardNumber.dispose();
    cardExpiry.dispose();
    cardCvv.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: Form(
        key: form,
        child: ListView(padding: const EdgeInsets.all(20), children: [
          Text('Contact information',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          TextFormField(
              controller: name,
              validator: requiredField,
              decoration: const InputDecoration(labelText: 'Full name')),
          const SizedBox(height: 12),
          TextFormField(
              controller: phone,
              validator: validatePhone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone')),
          const SizedBox(height: 12),
          TextFormField(
              controller: email,
              validator: validateEmail,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email')),
          const SizedBox(height: 24),
          Text(
              state.orderType == OrderType.delivery
                  ? 'Delivery address'
                  : 'Pickup time',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          if (state.orderType == OrderType.delivery) ...[
            TextFormField(
                controller: address,
                validator: requiredField,
                decoration:
                    const InputDecoration(labelText: 'Delivery address')),
          ] else
            SegmentedButton<bool>(segments: const [
              ButtonSegment(value: false, label: Text('ASAP')),
              ButtonSegment(value: true, label: Text('Schedule later'))
            ], selected: {
              scheduled
            }, onSelectionChanged: (v) => setState(() => scheduled = v.first)),
          const SizedBox(height: 24),
          Text('Payment method', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.credit_card),
            title: Text('Credit or debit card'),
          ),
          const SizedBox(height: 12),
          TextFormField(
              controller: cardNumber,
              validator: validateCardNumber,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Card number', hintText: '4242 4242 4242 4242')),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
                child: TextFormField(
                    controller: cardExpiry,
                    validator: validateCardExpiry,
                    keyboardType: TextInputType.datetime,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      const _CardExpiryInputFormatter(),
                    ],
                    decoration: const InputDecoration(
                        labelText: 'MM/YY', hintText: '12/28'))),
            const SizedBox(width: 10),
            Expanded(
                child: TextFormField(
                    controller: cardCvv,
                    validator: validateCvv,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'CVV')))
          ]),
          const SizedBox(height: 24),
          Text('Order summary', style: Theme.of(context).textTheme.titleLarge),
          ...state.cart.map((item) => PriceRow(
              '${item.quantity}x ${item.item.name}',
              currency.format(item.total))),
          const Divider(),
          PriceRow('Subtotal', currency.format(state.subtotal)),
          if (state.discount > 0)
            PriceRow('Promo discount', '-${currency.format(state.discount)}'),
          PriceRow('Tax', currency.format(state.tax)),
          if (state.deliveryFee > 0)
            PriceRow('Delivery fee', currency.format(state.deliveryFee)),
          if (state.tip > 0) PriceRow('Tip', currency.format(state.tip)),
          const Divider(),
          PriceRow('Total', currency.format(state.total), bold: true),
          const SizedBox(height: 20),
          FilledButton(
              onPressed: submitting ? null : () => _placeOrder(state),
              child: submitting
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Place order')),
        ]),
      ),
    );
  }

  Future<void> _placeOrder(AppState state) async {
    final currentForm = form.currentState;
    if (currentForm == null || !currentForm.validate()) return;
    setState(() => submitting = true);
    try {
      final placed = await state.placeOrder(
        customerName: name.text.trim(),
        phone: phone.text.trim(),
        email: email.text.trim(),
        address:
            state.orderType == OrderType.delivery ? address.text.trim() : '',
        postalCode: '',
        payLater: false,
      );
      if (!mounted) return;
      if (!placed) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Please select a restaurant and add an item before placing your order.')),
        );
        setState(() => submitting = false);
        return;
      }
      context.go('/confirmation');
    } catch (error) {
      if (!mounted) return;
      setState(() => submitting = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('RMS order failed: $error')));
    }
  }

  String? validateEmail(String? value) {
    final email = value?.trim() ?? '';
    final validEmail = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
    return validEmail.hasMatch(email) ? null : 'Enter a valid email';
  }

  String? validatePhone(String? value) {
    final phone = value?.trim() ?? '';
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 10 || digits.length > 15) {
      return 'Enter a valid phone number';
    }
    return null;
  }

  String? validateCardNumber(String? value) {
    final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.length < 13 || digits.length > 19 || !_passesLuhn(digits)) {
      return 'Enter a valid card number';
    }
    return null;
  }

  String? validateCardExpiry(String? value) {
    final match =
        RegExp(r'^\s*(0[1-9]|1[0-2])\s*/\s*(\d{2}|\d{4})\s*$')
            .firstMatch(value ?? '');
    if (match == null) return 'Use MM/YY';

    final month = int.parse(match.group(1)!);
    var year = int.parse(match.group(2)!);
    if (year < 100) year += 2000;

    final now = DateTime.now();
    final expiryEnd = DateTime(year, month + 1, 0, 23, 59, 59);
    return expiryEnd.isBefore(now) ? 'Card is expired' : null;
  }

  String? validateCvv(String? value) {
    final cvv = value?.trim() ?? '';
    return RegExp(r'^\d{3,4}$').hasMatch(cvv) ? null : 'Enter a valid CVV';
  }

  bool _passesLuhn(String digits) {
    var sum = 0;
    var doubleDigit = false;
    for (var index = digits.length - 1; index >= 0; index--) {
      var value = int.parse(digits[index]);
      if (doubleDigit) {
        value *= 2;
        if (value > 9) value -= 9;
      }
      sum += value;
      doubleDigit = !doubleDigit;
    }
    return sum % 10 == 0;
  }
}

class _CardExpiryInputFormatter extends TextInputFormatter {
  const _CardExpiryInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final limited = digits.length > 4 ? digits.substring(0, 4) : digits;
    final text = limited.length <= 2
        ? limited
        : '${limited.substring(0, 2)}/${limited.substring(2)}';
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
