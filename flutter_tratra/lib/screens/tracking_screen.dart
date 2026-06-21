// screens/tracking_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_tratra/routes.dart';
import '../core/constants.dart';
import '../widgets/custom_app_bar.dart';
import '../widgets/animated_button.dart';

class TrackingScreen extends StatefulWidget {
  final String bookingId;
  const TrackingScreen({super.key, required this.bookingId});

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> {
  int _currentStep = 2; // Exemple: étape 2 sur 4

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.backgroundColor,
      appBar: CustomAppBar(
        title: 'Suivi de commande',
        showBackButton: true,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _buildTimeline(),
          const SizedBox(height: 24),
          _buildArtisanCard(),
          const SizedBox(height: 24),
          const Text('Détails de la commande',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 12),
          _buildOrderDetails(),
          const SizedBox(height: 24),
          const Text('Statut actuel',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 12),
          _buildCurrentStatus(),
        ]),
      ),
      bottomNavigationBar: _buildBottomActions(),
    );
  }

  Widget _buildTimeline() {
    const steps = [
      'Commandé',
      'Confirmé',
      'Artisan en route',
      'Intervention en cours',
      'Terminé'
    ];
    return Column(
      children: [
        Container(
          height: 6,
          decoration: BoxDecoration(
              color: AppConstants.borderColor,
              borderRadius: BorderRadius.circular(3)),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: _currentStep / (steps.length - 1),
            child: Container(
              decoration: BoxDecoration(
                  color: AppConstants.primaryColor,
                  borderRadius: BorderRadius.circular(3)),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: steps.asMap().entries.map((entry) {
            final index = entry.key;
            final step = entry.value;
            final isActive = index <= _currentStep;
            final isCurrent = index == _currentStep;
            return Flexible(
              child: Column(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: isActive
                          ? AppConstants.primaryColor
                          : AppConstants.borderColor,
                      shape: BoxShape.circle,
                      border: isCurrent
                          ? Border.all(
                              color: AppConstants.primaryColor, width: 3)
                          : null,
                    ),
                    child: isActive
                        ? const Icon(Icons.check, size: 16, color: Colors.white)
                        : Center(
                            child: Text('${index + 1}',
                                style: TextStyle(
                                  color: isCurrent
                                      ? AppConstants.primaryColor
                                      : AppConstants.textSecondary,
                                  fontWeight: FontWeight.bold,
                                )),
                          ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    step,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight:
                          isCurrent ? FontWeight.bold : FontWeight.normal,
                      color: isActive
                          ? AppConstants.primaryColor
                          : AppConstants.textSecondary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildArtisanCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          const CircleAvatar(
            radius: 25,
            backgroundImage: NetworkImage(
                'https://images.unsplash.com/photo-1585747861815-0468f061d4f4?auto=format&fit=crop&w=100&q=80'),
          ),
          const SizedBox(width: 16),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Martin Dupont',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const Text('Plombier'),
              const SizedBox(height: 8),
              Row(
                children: [
                  IconButton(
                      icon: const Icon(Icons.phone,
                          color: AppConstants.primaryColor),
                      onPressed: _callArtisan),
                  IconButton(
                    icon: const Icon(Icons.message,
                        color: AppConstants.primaryColor),
                    onPressed: () {
                      Navigator.pushNamed(
                        context,
                        RouteNames.messaging,
                        arguments: MessagingArgs(
                          artisanName: 'Martin Dupont',
                          artisanImage:
                              'https://images.unsplash.com/photo-1585747861815-0468f061d4f4?auto=format&fit=crop&w=100&q=80',
                        ),
                      );
                    },
                  ),
                  const Spacer(),
                  _buildRatingInfo(),
                ],
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _buildRatingInfo() {
    return Row(children: [
      const Icon(Icons.star, size: 16, color: AppConstants.ratingColor),
      const SizedBox(width: 4),
      const Text('4.8', style: TextStyle(fontWeight: FontWeight.bold)),
      const SizedBox(width: 4),
      Text('(124 avis)',
          style: TextStyle(color: AppConstants.textSecondary, fontSize: 12)),
    ]);
  }

  Widget _buildOrderDetails() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: const [
          _DetailRow(label: 'Service', value: 'Réparation de fuite'),
          SizedBox(height: 8),
          _DetailRow(label: 'Date et heure', value: '15 Nov 2023 - 14:00'),
          SizedBox(height: 8),
          _DetailRow(label: 'Durée estimée', value: '1h 30min'),
          SizedBox(height: 8),
          _DetailRow(label: 'Adresse', value: '123 Rue Principale, Cocody'),
          SizedBox(height: 12),
          Divider(),
          SizedBox(height: 12),
          _DetailRow(label: 'Total', value: '69.00€', isTotal: true),
        ]),
      ),
    );
  }

  Widget _buildCurrentStatus() {
    final statusMessages = [
      'Votre commande a été confirmée',
      'L\'artisan a accepté votre demande',
      'Martin Dupont est en route vers votre domicile',
      'L\'intervention est en cours',
      'Service terminé avec succès'
    ];
    return Card(
      color: AppConstants.primaryLight,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          const Icon(Icons.info_outline,
              color: AppConstants.primaryColor, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              statusMessages[_currentStep],
              style: TextStyle(
                  color: AppConstants.primaryDark, fontWeight: FontWeight.w500),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildBottomActions() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppConstants.cardColor,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, -2))
        ],
      ),
      child: Row(children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _cancelBooking,
            style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                side: const BorderSide(color: AppConstants.promoColor)),
            child: const Text('Annuler',
                style: TextStyle(color: AppConstants.promoColor)),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: AnimatedButton(
              onPressed: _contactSupport, child: const Text('Support')),
        ),
      ]),
    );
  }

  void _callArtisan() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Appeler l\'artisan'),
        content: const Text(
            'Voulez-vous appeler Martin Dupont au +225 07 00 00 00 00 ?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler')),
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Appeler')),
        ],
      ),
    );
  }

  void _cancelBooking() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Annuler la réservation'),
        content: const Text(
            'Êtes-vous sûr de vouloir annuler cette réservation ? Des frais d\'annulation peuvent s\'appliquer.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Non')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Réservation annulée avec succès'),
                    backgroundColor: AppConstants.primaryColor),
              );
            },
            child: const Text('Oui, annuler'),
          ),
        ],
      ),
    );
  }

  void _contactSupport() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Contacter le support',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.phone, color: AppConstants.primaryColor),
            title: const Text('Appeler le support'),
            subtitle: const Text('+225 05 00 00 00 00'),
            onTap: () => Navigator.pop(context),
          ),
          ListTile(
            leading: const Icon(Icons.email, color: AppConstants.primaryColor),
            title: const Text('Envoyer un email'),
            subtitle: const Text('support@tratra.com'),
            onTap: () => Navigator.pop(context),
          ),
          ListTile(
            leading: const Icon(Icons.chat, color: AppConstants.primaryColor),
            title: const Text('Chat en direct'),
            subtitle: const Text('Disponible 24/7'),
            onTap: () => Navigator.pop(context),
          ),
        ]),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isTotal;
  const _DetailRow(
      {required this.label, required this.value, this.isTotal = false});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Text(label, style: TextStyle(color: AppConstants.textSecondary)),
      const Spacer(),
      Text(
        value,
        style: TextStyle(
          fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
          color: isTotal ? AppConstants.primaryColor : AppConstants.textPrimary,
          fontSize: isTotal ? 16 : null,
        ),
      ),
    ]);
  }
}
