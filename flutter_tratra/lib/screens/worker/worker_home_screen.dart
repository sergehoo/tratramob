// lib/screens/worker/worker_home_screen.dart
//
// Tableau de bord ARTISAN : présence, missions, gains, compte. Branché sur
// l'API découplée (BookingService / HandymanService / Session).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/core/constants.dart';
import 'package:flutter_tratra/core/session.dart';
import 'package:flutter_tratra/models/booking.dart';
import 'package:flutter_tratra/services/booking_service.dart';
import 'package:flutter_tratra/services/handyman_service.dart';
import 'package:flutter_tratra/screens/worker/mission_detail_screen.dart';
import 'package:flutter_tratra/screens/worker/kyc_screen.dart';

class WorkerHomeScreen extends StatefulWidget {
  const WorkerHomeScreen({super.key});

  @override
  State<WorkerHomeScreen> createState() => _WorkerHomeScreenState();
}

class _WorkerHomeScreenState extends State<WorkerHomeScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final tabs = <Widget>[
      const _MissionsTab(),
      const _EarningsTab(),
      const _AccountTab(),
    ];
    return Scaffold(
      backgroundColor: AppConstants.backgroundColor,
      body: SafeArea(child: tabs[_index]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        backgroundColor: Colors.white,
        indicatorColor: AppConstants.primaryLight,
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.work_outline),
              selectedIcon: Icon(Icons.work),
              label: 'Missions'),
          NavigationDestination(
              icon: Icon(Icons.account_balance_wallet_outlined),
              selectedIcon: Icon(Icons.account_balance_wallet),
              label: 'Gains'),
          NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Compte'),
        ],
      ),
    );
  }
}

// ============================ MISSIONS ============================
class _MissionsTab extends StatefulWidget {
  const _MissionsTab();

  @override
  State<_MissionsTab> createState() => _MissionsTabState();
}

class _MissionsTabState extends State<_MissionsTab> {
  late Future<List<Booking>> _future;
  bool? _online;
  bool _presenceBusy = false;

  @override
  void initState() {
    super.initState();
    _future = context.read<BookingService>().list();
  }

  Future<void> _reload() async {
    setState(() => _future = context.read<BookingService>().list());
    await _future;
  }

  Future<void> _togglePresence(bool value) async {
    setState(() => _presenceBusy = true);
    try {
      final now = await context.read<HandymanService>().setPresence(value);
      if (!mounted) return;
      setState(() => _online = now);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Présence impossible : profil non vérifié ? ($e)'),
        backgroundColor: AppConstants.dangerColor,
      ));
    } finally {
      if (mounted) setState(() => _presenceBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Mes missions',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          _PresenceCard(
              online: _online, busy: _presenceBusy, onChanged: _togglePresence),
          const SizedBox(height: 16),
          FutureBuilder<List<Booking>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snap.hasError) {
                return _InfoBox(
                    icon: Icons.error_outline,
                    text: 'Erreur de chargement.\n${snap.error}');
              }
              final items = snap.data ?? const <Booking>[];
              if (items.isEmpty) {
                return const _InfoBox(
                    icon: Icons.inbox_outlined,
                    text: 'Aucune mission pour le moment.');
              }
              return Column(
                children: items.map((b) => _MissionCard(booking: b, onChanged: _reload)).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PresenceCard extends StatelessWidget {
  final bool? online;
  final bool busy;
  final ValueChanged<bool> onChanged;
  const _PresenceCard(
      {required this.online, required this.busy, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final isOnline = online == true;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppConstants.borderColor),
      ),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isOnline ? AppConstants.successColor : Colors.grey,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(isOnline ? 'En ligne' : 'Hors ligne',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(
                  isOnline
                      ? 'Vous recevez des missions'
                      : 'Activez pour recevoir des missions',
                  style: const TextStyle(
                      fontSize: 12, color: AppConstants.textSecondary),
                ),
              ],
            ),
          ),
          if (busy)
            const SizedBox(
                width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          else
            Switch(
              value: isOnline,
              activeThumbColor: AppConstants.primaryColor,
              onChanged: onChanged,
            ),
        ],
      ),
    );
  }
}

class _MissionCard extends StatelessWidget {
  final Booking booking;
  final Future<void> Function() onChanged;
  const _MissionCard({required this.booking, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppConstants.borderColor),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Text(booking.serviceTitle ?? 'Mission #${booking.id}',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          [booking.city, booking.address].where((s) => (s ?? '').isNotEmpty).join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: StatusChip(status: booking.status),
        onTap: () async {
          await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => MissionDetailScreen(bookingId: booking.id),
          ));
          await onChanged();
        },
      ),
    );
  }
}

// ============================ GAINS ============================
class _EarningsTab extends StatefulWidget {
  const _EarningsTab();

  @override
  State<_EarningsTab> createState() => _EarningsTabState();
}

class _EarningsTabState extends State<_EarningsTab> {
  late Future<num> _available;
  Map<String, dynamic>? _account;
  bool _loadingAccount = true;

  @override
  void initState() {
    super.initState();
    _available = context.read<HandymanService>().availableEarnings();
    _loadAccount();
  }

  Future<void> _loadAccount() async {
    try {
      final acc = await context.read<HandymanService>().getPayoutAccount();
      if (mounted) setState(() => _account = acc);
    } finally {
      if (mounted) setState(() => _loadingAccount = false);
    }
  }

  Future<void> _reload() async {
    setState(() {
      _available = context.read<HandymanService>().availableEarnings();
      _loadingAccount = true;
    });
    await _loadAccount();
  }

  Future<void> _requestPayout(num available) async {
    if (available <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Aucun gain disponible au retrait.')));
      return;
    }
    if (_account == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Configurez d\'abord un compte de versement.')));
      return;
    }
    try {
      await context.read<HandymanService>().requestPayout(available);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Demande de versement envoyée.'),
          backgroundColor: AppConstants.successColor));
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Échec : $e'),
          backgroundColor: AppConstants.dangerColor));
    }
  }

  Future<void> _editAccount() async {
    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _PayoutAccountSheet(),
    );
    if (result == null) return;
    try {
      final acc = await context.read<HandymanService>().upsertPayoutAccount(
            provider: result['provider']!,
            accountRef: result['account_ref']!,
          );
      if (mounted) setState(() => _account = acc);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Échec : $e'),
          backgroundColor: AppConstants.dangerColor));
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Mes gains',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          FutureBuilder<num>(
            future: _available,
            builder: (context, snap) {
              final amount = snap.data ?? 0;
              return Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [
                    AppConstants.primaryColor,
                    AppConstants.primaryDark
                  ]),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Disponible au retrait',
                        style: TextStyle(color: Colors.white70)),
                    const SizedBox(height: 6),
                    Text(
                      snap.connectionState == ConnectionState.waiting
                          ? '…'
                          : '${amount.toStringAsFixed(0)} FCFA',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 30,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppConstants.accentColor,
                          foregroundColor: AppConstants.textPrimary,
                        ),
                        onPressed: () => _requestPayout(amount),
                        icon: const Icon(Icons.payments_outlined),
                        label: const Text('Demander un versement'),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          const Text('Compte de versement',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppConstants.borderColor),
            ),
            child: ListTile(
              leading: const Icon(Icons.account_balance_wallet_outlined,
                  color: AppConstants.primaryColor),
              title: Text(_loadingAccount
                  ? 'Chargement…'
                  : (_account == null
                      ? 'Non configuré'
                      : '${_account!['provider'] ?? ''} · ${_account!['account_ref'] ?? ''}')),
              subtitle: _account != null
                  ? Text(_account!['verified'] == true
                      ? 'Vérifié'
                      : 'En attente de vérification')
                  : const Text('Mobile Money ou compte bancaire'),
              trailing: TextButton(
                onPressed: _editAccount,
                child: Text(_account == null ? 'Ajouter' : 'Modifier'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PayoutAccountSheet extends StatefulWidget {
  const _PayoutAccountSheet();

  @override
  State<_PayoutAccountSheet> createState() => _PayoutAccountSheetState();
}

class _PayoutAccountSheetState extends State<_PayoutAccountSheet> {
  String _provider = 'om';
  final _ref = TextEditingController();

  @override
  void dispose() {
    _ref.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Compte de versement',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _provider,
            decoration: const InputDecoration(labelText: 'Opérateur'),
            items: const [
              DropdownMenuItem(value: 'om', child: Text('Orange Money')),
              DropdownMenuItem(value: 'mtn', child: Text('MTN MoMo')),
              DropdownMenuItem(value: 'moov', child: Text('Moov Money')),
              DropdownMenuItem(value: 'wave', child: Text('Wave')),
              DropdownMenuItem(value: 'bank', child: Text('Compte bancaire')),
            ],
            onChanged: (v) => setState(() => _provider = v ?? 'om'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ref,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
                labelText: 'Numéro / IBAN', hintText: '+225 0X XX XX XX XX'),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                if (_ref.text.trim().isEmpty) return;
                Navigator.of(context).pop(
                    {'provider': _provider, 'account_ref': _ref.text.trim()});
              },
              child: const Text('Enregistrer'),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================ COMPTE ============================
class _AccountTab extends StatelessWidget {
  const _AccountTab();

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final user = session.user;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 8),
        Center(
          child: CircleAvatar(
            radius: 40,
            backgroundColor: AppConstants.primaryLight,
            child: const Icon(Icons.handyman,
                size: 40, color: AppConstants.primaryColor),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(user?.fullName ?? 'Artisan',
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        ),
        Center(
          child: Text(user?.email ?? '',
              style: const TextStyle(color: AppConstants.textSecondary)),
        ),
        const SizedBox(height: 24),
        _AccountTile(
          icon: Icons.verified_user_outlined,
          title: 'Vérification (KYC)',
          subtitle: 'Pièces d\'identité et justificatifs',
          onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const KycScreen())),
        ),
        _AccountTile(
          icon: Icons.workspace_premium_outlined,
          title: 'Abonnement Pro',
          subtitle: 'Mise en avant et avantages artisan',
          onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const _SubscriptionScreen())),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
                foregroundColor: AppConstants.dangerColor),
            onPressed: () async {
              await context.read<Session>().logout();
              if (!context.mounted) return;
              Navigator.of(context)
                  .pushNamedAndRemoveUntil('/login', (r) => false);
            },
            icon: const Icon(Icons.logout),
            label: const Text('Déconnexion'),
          ),
        ),
      ],
    );
  }
}

class _AccountTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _AccountTile(
      {required this.icon,
      required this.title,
      required this.subtitle,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppConstants.borderColor),
      ),
      child: ListTile(
        leading: Icon(icon, color: AppConstants.primaryColor),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

// ============================ ABONNEMENT ============================
class _SubscriptionScreen extends StatefulWidget {
  const _SubscriptionScreen();

  @override
  State<_SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<_SubscriptionScreen> {
  late Future<List<Map<String, dynamic>>> _plans;

  @override
  void initState() {
    super.initState();
    _plans = context.read<HandymanService>().plans(audience: 'handyman');
  }

  Future<void> _subscribe(int planId) async {
    try {
      await context.read<HandymanService>().subscribe(planId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Abonnement activé.'),
          backgroundColor: AppConstants.successColor));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Échec : $e'),
          backgroundColor: AppConstants.dangerColor));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Abonnement Pro')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _plans,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final plans = snap.data ?? const [];
          if (plans.isEmpty) {
            return const _InfoBox(
                icon: Icons.workspace_premium_outlined,
                text: 'Aucune offre disponible.');
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: plans.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final p = plans[i];
              final features =
                  (p['features'] as List?)?.cast<dynamic>() ?? const [];
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppConstants.borderColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p['name']?.toString() ?? 'Offre',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text('${p['price'] ?? 0} FCFA / ${p['interval'] ?? ''}',
                        style: const TextStyle(
                            color: AppConstants.primaryColor,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    ...features.map((f) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(children: [
                            const Icon(Icons.check_circle,
                                size: 16, color: AppConstants.successColor),
                            const SizedBox(width: 8),
                            Expanded(child: Text(f.toString())),
                          ]),
                        )),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          final id = int.tryParse('${p['id']}');
                          if (id != null) _subscribe(id);
                        },
                        child: const Text('Choisir cette offre'),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ============================ SHARED ============================
class StatusChip extends StatelessWidget {
  final String status;
  const StatusChip({super.key, required this.status});

  static const _labels = {
    'pending': 'En attente',
    'confirmed': 'Confirmée',
    'in_progress': 'En cours',
    'completed': 'Terminée',
    'cancelled': 'Annulée',
  };

  Color get _color {
    switch (status) {
      case 'completed':
        return AppConstants.successColor;
      case 'cancelled':
        return AppConstants.dangerColor;
      case 'in_progress':
        return AppConstants.accentDark;
      default:
        return AppConstants.primaryColor;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(_labels[status] ?? status,
          style: TextStyle(
              color: _color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

class _InfoBox extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoBox({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppConstants.borderColor),
      ),
      child: Column(
        children: [
          Icon(icon, size: 40, color: AppConstants.textSecondary),
          const SizedBox(height: 8),
          Text(text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppConstants.textSecondary)),
        ],
      ),
    );
  }
}
