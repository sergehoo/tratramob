import 'package:flutter/material.dart';
import '../core/constants.dart';
import '../widgets/custom_app_bar.dart';
import '../widgets/animated_button.dart';

class PaymentScreen extends StatefulWidget {
  final double amount;
  final String serviceName;

  const PaymentScreen({
    super.key,
    required this.amount,
    required this.serviceName,
  });

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  int _selectedPaymentMethod = 0;
  final TextEditingController _cardNumberController = TextEditingController();
  final TextEditingController _expiryController = TextEditingController();
  final TextEditingController _cvvController = TextEditingController();
  final TextEditingController _cardHolderController = TextEditingController();

  final List<Map<String, dynamic>> _paymentMethods = const [
    {'icon': Icons.credit_card, 'name': 'Carte bancaire', 'type': 'card'},
    {'icon': Icons.mobile_friendly, 'name': 'Mobile Money', 'type': 'mobile'},
    {'icon': Icons.money, 'name': 'Espèces', 'type': 'cash'},
  ];

  @override
  void dispose() {
    _cardNumberController.dispose();
    _expiryController.dispose();
    _cvvController.dispose();
    _cardHolderController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.backgroundColor,
      appBar: const CustomAppBar(
        title: 'Paiement',
        showBackButton: true,
        leading: null,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Récapitulatif
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Text('Récapitulatif de la commande',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Text('Service'),
                        const Spacer(),
                        Text(widget.serviceName),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // TODO: Inject real date/time from Booking
                    const Row(
                      children: [
                        Text('Date'),
                        Spacer(),
                        Text('15 Nov 2023 - 14:00'),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Text('Total à payer',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        const Spacer(),
                        Text(
                          '${widget.amount} €',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppConstants.primaryColor,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Méthodes de paiement
            const Text('Méthode de paiement',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Column(
              children: _paymentMethods.asMap().entries.map((entry) {
                final index = entry.key;
                final method = entry.value;
                final isSelected = index == _selectedPaymentMethod;

                return Card(
                  color: isSelected
                      ? AppConstants.primaryLight
                      : AppConstants.cardColor,
                  child: ListTile(
                    leading: Icon(
                      method['icon'] as IconData,
                      color: isSelected
                          ? AppConstants.primaryColor
                          : AppConstants.textPrimary,
                    ),
                    title: Text(method['name'] as String),
                    trailing: isSelected
                        ? const Icon(Icons.check_circle,
                            color: AppConstants.primaryColor)
                        : null,
                    onTap: () => setState(() => _selectedPaymentMethod = index),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),

            // Formulaire de carte (si sélectionné)
            if (_selectedPaymentMethod == 0) _buildCardForm(),
            const SizedBox(height: 24),

            // Conditions
            const Text(
              'En procédant au paiement, vous acceptez nos conditions générales d\'utilisation.',
              style: TextStyle(fontSize: 12, color: AppConstants.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16),
        child: AnimatedButton(
          onPressed: () {
            // TODO: implémenter la création Payment côté API
          },
          child: const Text('Payer maintenant'),
        ),
      ),
    );
  }

  Widget _buildCardForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Informations de la carte',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        TextField(
          controller: _cardNumberController,
          decoration: const InputDecoration(
            labelText: 'Numéro de carte',
            hintText: '1234 5678 9012 3456',
            prefixIcon: Icon(Icons.credit_card),
          ),
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _expiryController,
                decoration: const InputDecoration(
                  labelText: 'Expiration',
                  hintText: 'MM/AA',
                  prefixIcon: Icon(Icons.calendar_today),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextField(
                controller: _cvvController,
                decoration: const InputDecoration(
                  labelText: 'CVV',
                  hintText: '123',
                  prefixIcon: Icon(Icons.lock),
                ),
                keyboardType: TextInputType.number,
                obscureText: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _cardHolderController,
          decoration: const InputDecoration(
            labelText: 'Titulaire de la carte',
            hintText: 'John Doe',
            prefixIcon: Icon(Icons.person),
          ),
        ),
      ],
    );
  }
}
