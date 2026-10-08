import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../widgets/lab_widgets.dart';
import '../payment_controller.dart';

/// Step 2: the merchant backend creates an order (amount fixed server-side).
class CheckoutCard extends ConsumerWidget {
  const CheckoutCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(paymentLabProvider.select((s) => s.onboarded)) != true) return const SizedBox.shrink();
    final amount = ref.watch(paymentLabProvider.select((s) => s.amountText));
    final order = ref.watch(paymentLabProvider.select((s) => s.order));
    final controller = ref.read(paymentLabProvider.notifier);

    return SectionCard(
      title: 'Step 2 · Merchant creates order',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: SyncedTextField(
                  label: 'Amount',
                  prefixText: '₹ ',
                  keyboardType: TextInputType.number,
                  value: amount,
                  onChanged: controller.setAmount,
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(onPressed: controller.createOrder, child: const Text('Create')),
            ],
          ),
          if (order != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(colors: [Color(0xFF2B4C9B), Color(0xFF162B5C)]),
              ),
              child: Row(
                children: [
                  const CircleAvatar(
                    backgroundColor: Colors.white12,
                    child: Icon(Icons.storefront_rounded, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(order.payee, style: const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(order.id, style: mono.copyWith(color: AppColors.muted, fontSize: 11.5)),
                      ],
                    ),
                  ),
                  Text(
                    order.displayAmount,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.gold),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
