// lib/screens/worker/worker_home_screen.dart
//
// Tableau de bord ARTISAN : présence, missions, gains, compte. Branché sur
// l'API découplée (BookingService / HandymanService / Session).
// Interface : Design System Tratra (TratraBottomNav, cartes, badges, états vides/squelettes).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/core/session.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/models/booking.dart';
import 'package:flutter_tratra/screens/worker/dashboard/worker_ui.dart';
import 'package:flutter_tratra/screens/worker/kyc_screen.dart';
import 'package:flutter_tratra/screens/worker/mission_detail_screen.dart';
import 'package:flutter_tratra/services/booking_service.dart';
import 'package:flutter_tratra/services/handyman_service.dart';

/// Marges communes des pages défilantes de l'espace artisan.
const _pagePadding = EdgeInsets.fromLTRB(
  TtLayout.gutterMobile,
  TtSpace.s5,
  TtLayout.gutterMobile,
  TtSpace.s8,
);

/// Opérateurs de versement : code envoyé à l'API -> libellé affiché.
const _providerLabels = <String, String>{
  'om': 'Orange Money',
  'mtn': 'MTN MoMo',
  'moov': 'Moov Money',
  'wave': 'Wave',
  'bank': 'Compte bancaire',
};

class WorkerHomeScreen extends StatefulWidget {
  const WorkerHomeScreen({super.key});

  @override
  State<WorkerHomeScreen> createState() => _WorkerHomeScreenState();
}

class _WorkerHomeScreenState extends State<WorkerHomeScreen> {
  int _index = 0;

  static const _navItems = <TratraNavItem>[
    TratraNavItem(
        icon: Icons.work_outline, activeIcon: Icons.work, label: 'Missions'),
    TratraNavItem(
      icon: Icons.account_balance_wallet_outlined,
      activeIcon: Icons.account_balance_wallet,
      label: 'Gains',
    ),
    TratraNavItem(
        icon: Icons.person_outline, activeIcon: Icons.person, label: 'Compte'),
  ];

  @override
  Widget build(BuildContext context) {
    final tabs = <Widget>[
      const _MissionsTab(),
      const _EarningsTab(),
      const _AccountTab(),
    ];
    return Scaffold(
      backgroundColor: TtColors.canvas,
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: workerMotion(context, TtMotion.fast),
          switchInCurve: TtMotion.emphasized,
          child: KeyedSubtree(key: ValueKey<int>(_index), child: tabs[_index]),
        ),
      ),
      bottomNavigationBar: TratraBottomNav(
        items: _navItems,
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
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
    _future = context.read<BookingService>().list(handymanId: context.read<Session>().user?.id);
  }

  Future<void> _reload() async {
    setState(() {
      _future = context.read<BookingService>().list(handymanId: context.read<Session>().user?.id);
    });
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
      showWorkerToast(
        context,
        'Présence impossible : profil non vérifié ? ($e)',
        tone: WorkerToastTone.danger,
      );
    } finally {
      if (mounted) setState(() => _presenceBusy = false);
    }
  }

  Widget _section({String? subtitle, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TratraSectionHeader(
          title: 'Vos missions',
          subtitle: subtitle,
          padding: const EdgeInsets.fromLTRB(0, TtSpace.s6, 0, TtSpace.s3),
        ),
        child,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final firstName = (context.watch<Session>().user?.firstName ?? '').trim();
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: _pagePadding,
        children: [
          WorkerReveal(
            child: WorkerPageHeader(
              eyebrow: 'Espace artisan',
              title: 'Mes missions',
              subtitle: firstName.isEmpty
                  ? 'Vos demandes et interventions.'
                  : 'Bonjour $firstName, voici vos demandes et interventions.',
            ),
          ),
          const SizedBox(height: TtSpace.s5),
          WorkerReveal(
            index: 1,
            child: _PresenceCard(
                online: _online,
                busy: _presenceBusy,
                onChanged: _togglePresence),
          ),
          FutureBuilder<List<Booking>>(
            future: _future,
            builder: (context, snap) {
              final loading = snap.connectionState == ConnectionState.waiting &&
                  !snap.hasData;
              if (loading) {
                return _section(
                  child: const TratraSkeletonList(
                      count: 3, padding: EdgeInsets.zero),
                );
              }
              if (snap.hasError) {
                return _section(
                  child: TratraAlert(
                    tone: TratraAlertTone.danger,
                    title: 'Erreur de chargement',
                    message: '${snap.error}',
                    action: TratraButton(
                      label: 'Réessayer',
                      size: TratraButtonSize.sm,
                      variant: TratraButtonVariant.outline,
                      leading: const Icon(Icons.refresh_rounded),
                      onPressed: _reload,
                    ),
                  ),
                );
              }
              final items = snap.data ?? const <Booking>[];
              if (items.isEmpty) {
                return _section(
                  child: TratraEmptyState(
                    icon: Icons.inbox_outlined,
                    title: 'Aucune mission pour le moment',
                    description: _online == true
                        ? 'Les nouvelles demandes de vos clients apparaîtront ici.'
                        : 'Les demandes de vos clients apparaîtront ici. Activez votre présence pour recevoir des missions.',
                    actions: [
                      if (_online != true)
                        TratraButton(
                          label: 'Passer en ligne',
                          leading: const Icon(Icons.power_settings_new_rounded),
                          loading: _presenceBusy,
                          onPressed: () => _togglePresence(true),
                        ),
                      TratraButton(
                        label: 'Actualiser',
                        variant: TratraButtonVariant.outline,
                        leading: const Icon(Icons.refresh_rounded),
                        onPressed: _reload,
                      ),
                    ],
                  ),
                );
              }
              return _section(
                subtitle: items.length == 1
                    ? '1 mission'
                    : '${items.length} missions',
                child: Column(
                  children: [
                    for (var i = 0; i < items.length; i++)
                      WorkerReveal(
                        index: i,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: TtSpace.s3),
                          child: _MissionCard(
                              booking: items[i], onChanged: _reload),
                        ),
                      ),
                  ],
                ),
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
    return TratraCard(
      variant: isOnline ? TratraCardVariant.soft : TratraCardVariant.standard,
      padding: const EdgeInsets.fromLTRB(
          TtSpace.s5, TtSpace.s4, TtSpace.s4, TtSpace.s4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // La clé relance l'animation de pulsation quand la présence change.
                TratraBadge(
                  // Statut inconnu tant que l'artisan n'a pas touché au contrôle : pas de faux « Hors ligne ».
                  online == null ? 'Disponibilité' : (isOnline ? 'En ligne' : 'Hors ligne'),
                  key: ValueKey<bool>(isOnline),
                  tone: isOnline ? TratraTone.success : TratraTone.gray,
                  dot: true,
                  pulse: isOnline,
                ),
                const SizedBox(height: TtSpace.s2),
                Text(
                  isOnline
                      ? 'Vous recevez des missions'
                      : 'Activez pour recevoir des missions',
                  style:
                      TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft),
                ),
              ],
            ),
          ),
          const SizedBox(width: TtSpace.s3),
          SizedBox(
            width: 56,
            height: TtLayout.controlHeight,
            child: Center(
              child: busy
                  ? Semantics(
                      label: 'Mise à jour de la présence en cours',
                      liveRegion: true,
                      child: const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      ),
                    )
                  : Semantics(
                      label: 'Présence en ligne',
                      child: Switch(value: isOnline, onChanged: onChanged),
                    ),
            ),
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
    final title = booking.serviceTitle ?? 'Mission #${booking.id}';
    final place = [booking.city, booking.address]
        .where((s) => (s ?? '').isNotEmpty)
        .join(' · ');
    final when = booking.bookingDate;
    final amount = booking.amount;
    return TratraCard(
      padding: TratraCard.compact,
      onTap: () async {
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => MissionDetailScreen(bookingId: booking.id),
        ));
        await onChanged();
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              TratraStatusBadge(TratraStatus.booking, booking.status),
              const SizedBox(width: TtSpace.s3),
              Expanded(
                child: amount == null
                    ? const SizedBox.shrink()
                    : Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          formatFcfa(amount),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TratraTheme.style(TtType.title,
                              color: TtColors.primaryDark),
                        ),
                      ),
              ),
            ],
          ),
          const SizedBox(height: TtSpace.s3),
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TratraTheme.style(TtType.h3),
                ),
              ),
              const SizedBox(width: TtSpace.s2),
              const ExcludeSemantics(
                child: Icon(Icons.chevron_right_rounded, color: TtColors.fog),
              ),
            ],
          ),
          if (place.isNotEmpty) ...[
            const SizedBox(height: TtSpace.s2),
            WorkerMetaLine(icon: Icons.location_on_outlined, text: place),
          ],
          if (when != null) ...[
            const SizedBox(height: TtSpace.s1 + 2),
            WorkerMetaLine(icon: Icons.event_outlined, text: formatWhen(when)),
          ],
        ],
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
  Object? _accountError;
  bool _loadingAccount = true;
  bool _payoutBusy = false;

  @override
  void initState() {
    super.initState();
    _available = context.read<HandymanService>().availableEarnings();
    _loadAccount();
  }

  Future<void> _loadAccount() async {
    try {
      final acc = await context.read<HandymanService>().getPayoutAccount();
      if (mounted) {
        setState(() {
          _account = acc;
          _accountError = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _accountError = e);
    } finally {
      if (mounted) setState(() => _loadingAccount = false);
    }
  }

  Future<void> _reload() async {
    setState(() {
      _available = context.read<HandymanService>().availableEarnings();
      _loadingAccount = true;
      _accountError = null;
    });
    await _loadAccount();
  }

  Future<void> _requestPayout(num available) async {
    if (available <= 0) {
      showWorkerToast(context, 'Aucun gain disponible au retrait.');
      return;
    }
    if (_account == null) {
      showWorkerToast(context, 'Configurez d’abord un compte de versement.');
      return;
    }
    setState(() => _payoutBusy = true);
    try {
      await context.read<HandymanService>().requestPayout(available);
      if (!mounted) return;
      showWorkerToast(context, 'Demande de versement envoyée.',
          tone: WorkerToastTone.success);
      await _reload();
    } catch (e) {
      if (!mounted) return;
      showWorkerToast(context, 'Échec : $e', tone: WorkerToastTone.danger);
    } finally {
      if (mounted) setState(() => _payoutBusy = false);
    }
  }

  Future<void> _editAccount() async {
    final result = await showTratraSheet<Map<String, String>>(
      context,
      title: 'Compte de versement',
      description:
          'Choisissez l’opérateur et saisissez le numéro ou l’IBAN qui recevra vos versements.',
      child: const _PayoutAccountForm(),
    );
    if (result == null || !mounted) return;
    try {
      final acc = await context.read<HandymanService>().upsertPayoutAccount(
            provider: result['provider']!,
            accountRef: result['account_ref']!,
          );
      if (mounted) {
        setState(() {
          _account = acc;
          _accountError = null;
        });
      }
    } catch (e) {
      if (!mounted) return;
      showWorkerToast(context, 'Échec : $e', tone: WorkerToastTone.danger);
    }
  }

  String _accountTitle(Map<String, dynamic> account) {
    final provider = '${account['provider'] ?? ''}';
    final parts = [
      _providerLabels[provider] ?? provider,
      '${account['account_ref'] ?? ''}'
    ];
    final title = parts.where((s) => s.isNotEmpty).join(' · ');
    return title.isEmpty ? 'Compte enregistré' : title;
  }

  Widget _balanceCard(AsyncSnapshot<num> snap) {
    final loading = snap.connectionState == ConnectionState.waiting;
    final failed = !loading && snap.hasError;
    final amount = snap.data ?? 0;

    final Widget value;
    if (loading) {
      value = Semantics(
        label: 'Chargement du montant disponible',
        liveRegion: true,
        child: ExcludeSemantics(
          child: TratraShimmer(
            child: Container(
              width: 180,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: TtRadius.controlAll,
              ),
            ),
          ),
        ),
      );
    } else if (failed) {
      value = Text('—',
          style: TratraTheme.style(TtType.displayLg, color: Colors.white));
    } else {
      value = FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: formatAmount(amount),
                style: TratraTheme.style(TtType.displayLg, color: Colors.white),
              ),
              TextSpan(
                text: ' FCFA',
                style: TratraTheme.style(TtType.h3, color: Colors.white70),
              ),
            ],
          ),
        ),
      );
    }

    return TratraCard(
      variant: TratraCardVariant.night,
      padding: const EdgeInsets.all(TtSpace.s6),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Halo décoratif jaune dans l'angle (recadré par la carte).
          Positioned(
            right: -(TtSpace.s6 + TtSpace.s10),
            top: -(TtSpace.s6 + TtSpace.s10),
            child: ExcludeSemantics(
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      TtColors.accent.withValues(alpha: 0.22),
                      TtColors.accent.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.account_balance_wallet_outlined,
                      size: 18, color: TtColors.accent),
                  const SizedBox(width: TtSpace.s2),
                  Flexible(
                    child: Text(
                      'DISPONIBLE AU RETRAIT',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TratraTheme.style(TtType.eyebrow,
                          color: Colors.white70),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: TtSpace.s3),
              value,
              const SizedBox(height: TtSpace.s5),
              TratraButton(
                label: 'Demander un versement',
                variant: TratraButtonVariant.accent,
                size: TratraButtonSize.lg,
                block: true,
                loading: _payoutBusy,
                leading: const Icon(Icons.payments_outlined),
                onPressed: () => _requestPayout(amount),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _accountCard() {
    if (_accountError != null && !_loadingAccount) {
      return TratraAlert(
        tone: TratraAlertTone.danger,
        title: 'Compte de versement indisponible',
        message:
            'Impossible de charger votre compte de versement.\n$_accountError',
        action: TratraButton(
          label: 'Réessayer',
          size: TratraButtonSize.sm,
          variant: TratraButtonVariant.outline,
          leading: const Icon(Icons.refresh_rounded),
          onPressed: _reload,
        ),
      );
    }

    final account = _account;
    final Widget details;
    if (_loadingAccount) {
      details = Semantics(
        label: 'Chargement du compte de versement',
        liveRegion: true,
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TratraSkeleton(width: 160, height: 14),
            SizedBox(height: TtSpace.s2 + 2),
            TratraSkeleton(width: 110, height: 12),
          ],
        ),
      );
    } else if (account == null) {
      details = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Non configuré', style: TratraTheme.style(TtType.title)),
          const SizedBox(height: TtSpace.s1),
          Text(
            'Mobile Money ou compte bancaire',
            style: TratraTheme.style(TtType.bodySm, color: TtColors.ash),
          ),
        ],
      );
    } else {
      final verified = account['verified'] == true;
      details = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _accountTitle(account),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TratraTheme.style(TtType.title),
          ),
          const SizedBox(height: TtSpace.s2),
          TratraBadge(
            verified ? 'Vérifié' : 'En attente de vérification',
            tone: verified ? TratraTone.success : TratraTone.accent,
            dot: true,
          ),
        ],
      );
    }

    return TratraCard(
      padding: TratraCard.compact,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const WorkerIconTile(Icons.account_balance_wallet_outlined),
              const SizedBox(width: TtSpace.s3),
              Expanded(child: details),
            ],
          ),
          if (!_loadingAccount) ...[
            const SizedBox(height: TtSpace.s4),
            TratraButton(
              label: account == null ? 'Ajouter' : 'Modifier',
              variant: account == null
                  ? TratraButtonVariant.primary
                  : TratraButtonVariant.soft,
              block: true,
              leading: Icon(
                  account == null ? Icons.add_rounded : Icons.edit_outlined),
              onPressed: _editAccount,
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: _pagePadding,
        children: [
          const WorkerReveal(
            child:
                WorkerPageHeader(eyebrow: 'Espace artisan', title: 'Mes gains'),
          ),
          const SizedBox(height: TtSpace.s5),
          FutureBuilder<num>(
            future: _available,
            builder: (context, snap) {
              final failed = snap.connectionState != ConnectionState.waiting &&
                  snap.hasError;
              return WorkerReveal(
                index: 1,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _balanceCard(snap),
                    if (failed) ...[
                      const SizedBox(height: TtSpace.s3),
                      TratraAlert(
                        tone: TratraAlertTone.danger,
                        title: 'Gains indisponibles',
                        message:
                            'Impossible de charger vos gains disponibles.\n${snap.error}',
                        action: TratraButton(
                          label: 'Réessayer',
                          size: TratraButtonSize.sm,
                          variant: TratraButtonVariant.outline,
                          leading: const Icon(Icons.refresh_rounded),
                          onPressed: _reload,
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
          TratraSectionHeader(
            title: 'Compte de versement',
            padding: const EdgeInsets.fromLTRB(0, TtSpace.s6, 0, TtSpace.s3),
          ),
          WorkerReveal(index: 2, child: _accountCard()),
        ],
      ),
    );
  }
}

/// Formulaire du compte de versement (affiché dans une feuille basse) :
/// renvoie `{provider, account_ref}` à l'appelant, comme avant.
class _PayoutAccountForm extends StatefulWidget {
  const _PayoutAccountForm();

  @override
  State<_PayoutAccountForm> createState() => _PayoutAccountFormState();
}

class _PayoutAccountFormState extends State<_PayoutAccountForm> {
  String _provider = 'om';
  final _ref = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _ref.dispose();
    super.dispose();
  }

  void _submit() {
    final ref = _ref.text.trim();
    if (ref.isEmpty) {
      setState(() => _error = 'Saisissez un numéro ou un IBAN.');
      return;
    }
    Navigator.of(context).pop({'provider': _provider, 'account_ref': ref});
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Opérateur',
          style: TratraTheme.style(TtType.bodySm)
              .copyWith(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        const SizedBox(height: TtSpace.s2),
        Wrap(
          spacing: TtSpace.s2,
          runSpacing: TtSpace.s2,
          children: [
            for (final entry in _providerLabels.entries)
              SizedBox(
                height: TtLayout.touchTarget,
                child: TratraChip(
                  label: entry.value,
                  selected: _provider == entry.key,
                  onTap: () => setState(() => _provider = entry.key),
                ),
              ),
          ],
        ),
        const SizedBox(height: TtSpace.s4),
        TratraInput(
          label: 'Numéro / IBAN',
          hint: '+225 0X XX XX XX XX',
          required: true,
          controller: _ref,
          keyboardType:
              _provider == 'bank' ? TextInputType.text : TextInputType.phone,
          textInputAction: TextInputAction.done,
          errorText: _error,
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: TtSpace.s5),
        TratraButton(
          label: 'Enregistrer',
          size: TratraButtonSize.lg,
          block: true,
          onPressed: _submit,
        ),
      ],
    );
  }
}

// ============================ COMPTE ============================
class _AccountTab extends StatefulWidget {
  const _AccountTab();

  @override
  State<_AccountTab> createState() => _AccountTabState();
}

class _AccountTabState extends State<_AccountTab> {
  bool _loggingOut = false;

  Future<void> _logout() async {
    setState(() => _loggingOut = true);
    try {
      await context.read<Session>().logout();
    } finally {
      if (mounted) setState(() => _loggingOut = false);
    }
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (r) => false);
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final user = session.user;
    final name = user?.fullName ?? 'Artisan';
    final email = user?.email ?? '';
    final phone = (user?.phoneNumber ?? '').trim();
    return ListView(
      padding: _pagePadding,
      children: [
        WorkerReveal(
          child: Column(
            children: [
              TratraAvatar(name: name, photoUrl: user?.profileImage, size: 88),
              const SizedBox(height: TtSpace.s4),
              Text(
                name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TratraTheme.style(TtType.h2),
              ),
              const SizedBox(height: TtSpace.s2),
              const TratraBadge('Artisan', icon: Icons.handyman_outlined),
              if (email.isNotEmpty) ...[
                const SizedBox(height: TtSpace.s3),
                Text(
                  email,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TratraTheme.style(TtType.bodySm, color: TtColors.ash),
                ),
              ],
              if (phone.isNotEmpty) ...[
                const SizedBox(height: TtSpace.s1),
                Text(
                  phone,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TratraTheme.style(TtType.bodySm, color: TtColors.ash),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: TtSpace.s8),
        WorkerReveal(
          index: 1,
          child: _AccountTile(
            icon: Icons.verified_user_outlined,
            title: 'Vérification (KYC)',
            subtitle: 'Pièces d’identité et justificatifs',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const KycScreen()),
            ),
          ),
        ),
        const SizedBox(height: TtSpace.s3),
        WorkerReveal(
          index: 2,
          child: _AccountTile(
            icon: Icons.workspace_premium_outlined,
            title: 'Abonnement Pro',
            subtitle: 'Mise en avant et avantages artisan',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const _SubscriptionScreen()),
            ),
          ),
        ),
        const SizedBox(height: TtSpace.s6),
        WorkerReveal(
          index: 3,
          child: TratraButton(
            label: 'Déconnexion',
            variant: TratraButtonVariant.outline,
            size: TratraButtonSize.lg,
            block: true,
            loading: _loggingOut,
            leading: const Icon(Icons.logout_rounded, color: TtColors.danger),
            onPressed: _logout,
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
  const _AccountTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return TratraCard(
      padding: TratraCard.compact,
      onTap: onTap,
      child: Row(
        children: [
          WorkerIconTile(icon),
          const SizedBox(width: TtSpace.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TratraTheme.style(TtType.title)),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TratraTheme.style(TtType.bodySm, color: TtColors.ash),
                ),
              ],
            ),
          ),
          const SizedBox(width: TtSpace.s2),
          const ExcludeSemantics(
            child: Icon(Icons.chevron_right_rounded, color: TtColors.fog),
          ),
        ],
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
  int? _subscribingPlan;

  @override
  void initState() {
    super.initState();
    _plans = _fetchPlans();
  }

  Future<List<Map<String, dynamic>>> _fetchPlans() =>
      context.read<HandymanService>().plans(audience: 'handyman');

  Future<void> _subscribe(int planId) async {
    setState(() => _subscribingPlan = planId);
    try {
      await context.read<HandymanService>().subscribe(planId);
      if (!mounted) return;
      showWorkerToast(context, 'Abonnement activé.',
          tone: WorkerToastTone.success);
    } catch (e) {
      if (!mounted) return;
      showWorkerToast(context, 'Échec : $e', tone: WorkerToastTone.danger);
    } finally {
      if (mounted) setState(() => _subscribingPlan = null);
    }
  }

  /// Prix lisible ; la valeur brute est conservée si elle n'est pas un entier.
  String _priceLabel(dynamic raw) {
    final value = num.tryParse('${raw ?? 0}');
    if (value == null) return '${raw ?? 0}';
    if (value != value.roundToDouble()) return '$value';
    return formatAmount(value);
  }

  String _intervalLabel(dynamic raw) {
    final interval = '${raw ?? ''}';
    return switch (interval) {
      'monthly' => 'mois',
      'yearly' => 'an',
      _ => interval,
    };
  }

  Widget _planCard(Map<String, dynamic> p) {
    final features = (p['features'] as List?)?.cast<dynamic>() ?? const [];
    final id = int.tryParse('${p['id']}');
    final interval = _intervalLabel(p['interval']);
    return TratraCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(p['name']?.toString() ?? 'Offre',
              style: TratraTheme.style(TtType.h3)),
          const SizedBox(height: TtSpace.s2),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: _priceLabel(p['price']),
                  style:
                      TratraTheme.style(TtType.h1, color: TtColors.primaryDark),
                ),
                TextSpan(
                  text: ' FCFA${interval.isEmpty ? '' : ' / $interval'}',
                  style: TratraTheme.style(TtType.bodySm, color: TtColors.ash),
                ),
              ],
            ),
          ),
          if (features.isNotEmpty) ...[
            const SizedBox(height: TtSpace.s4),
            for (final f in features)
              Padding(
                padding: const EdgeInsets.only(bottom: TtSpace.s2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(Icons.check_circle_rounded,
                          size: 18, color: TtColors.primary),
                    ),
                    const SizedBox(width: TtSpace.s2 + 2),
                    Expanded(
                      child: Text(
                        f.toString(),
                        style: TratraTheme.style(TtType.body,
                                color: TtColors.inkSoft)
                            .copyWith(fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: TtSpace.s3),
          TratraButton(
            label: 'Choisir cette offre',
            size: TratraButtonSize.lg,
            block: true,
            loading: id != null && _subscribingPlan == id,
            onPressed: (id == null || _subscribingPlan != null)
                ? null
                : () => _subscribe(id),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TtColors.canvas,
      appBar: const TratraAppBar(title: 'Abonnement Pro'),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _plans,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const SingleChildScrollView(
              child: TratraSkeletonList(
                  count: 2, padding: EdgeInsets.all(TtLayout.gutterMobile)),
            );
          }
          if (snap.hasError) {
            return ListView(
              padding: _pagePadding,
              children: [
                TratraAlert(
                  tone: TratraAlertTone.danger,
                  title: 'Offres indisponibles',
                  message: 'Impossible de charger les offres.\n${snap.error}',
                  action: TratraButton(
                    label: 'Réessayer',
                    size: TratraButtonSize.sm,
                    variant: TratraButtonVariant.outline,
                    leading: const Icon(Icons.refresh_rounded),
                    onPressed: () => setState(() {
                      _plans = _fetchPlans();
                    }),
                  ),
                ),
              ],
            );
          }
          final plans = snap.data ?? const <Map<String, dynamic>>[];
          if (plans.isEmpty) {
            return const TratraEmptyState(
              icon: Icons.workspace_premium_outlined,
              title: 'Aucune offre disponible',
              description:
                  'Les offres d’abonnement Pro apparaîtront ici dès qu’elles seront publiées.',
            );
          }
          return ListView(
            padding: _pagePadding,
            children: [
              const WorkerReveal(
                child: TratraCard(
                  variant: TratraCardVariant.soft,
                  padding: TratraCard.compact,
                  child: Row(
                    children: [
                      WorkerIconTile(Icons.workspace_premium_outlined),
                      SizedBox(width: TtSpace.s3),
                      Expanded(child: _SubscriptionIntro()),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: TtSpace.s5),
              for (var i = 0; i < plans.length; i++)
                WorkerReveal(
                  index: i + 1,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: TtSpace.s3),
                    child: _planCard(plans[i]),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _SubscriptionIntro extends StatelessWidget {
  const _SubscriptionIntro();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Abonnement Pro', style: TratraTheme.style(TtType.title)),
        const SizedBox(height: 2),
        Text(
          'Mise en avant et avantages artisan',
          style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft),
        ),
      ],
    );
  }
}

// ============================ SHARED ============================

/// Pastille de statut d'une réservation. Conservée pour compatibilité des imports :
/// délègue au badge du Design System (libellés et tons identiques sur tout le produit).
class StatusChip extends StatelessWidget {
  final String status;
  const StatusChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) =>
      TratraStatusBadge(TratraStatus.booking, status);
}
