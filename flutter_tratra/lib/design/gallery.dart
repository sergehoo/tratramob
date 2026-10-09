// Guide de style vivant (debug uniquement) : tous les composants et leurs états.
// Ouvrir avec `flutter run --dart-define=TRATRA_GALLERY=true`. Les libellés sont
// des exemples de rendu ; l'écran n'est jamais atteignable en release.
import 'package:flutter/material.dart';

import 'design.dart';

class TratraGalleryScreen extends StatefulWidget {
  const TratraGalleryScreen({super.key});
  static const route = '/design-system';

  @override
  State<TratraGalleryScreen> createState() => _TratraGalleryScreenState();
}

class _TratraGalleryScreenState extends State<TratraGalleryScreen> {
  int _tab = 0;
  bool _loading = false;
  bool _chip = true;
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _section(String title, Widget child) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TratraSectionHeader(title: title, padding: const EdgeInsets.fromLTRB(0, 28, 0, 12)),
          child,
        ],
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const TratraAppBar(title: 'Guide de style', subtitle: 'Design System Tratra · debug'),
      bottomNavigationBar: TratraBottomNav(
        currentIndex: _tab,
        onTap: (i) => setState(() => _tab = i),
        items: const [
          TratraNavItem(icon: Icons.home_outlined, activeIcon: Icons.home_rounded, label: 'Accueil'),
          TratraNavItem(icon: Icons.search_rounded, label: 'Recherche'),
          TratraNavItem(icon: Icons.calendar_month_outlined, activeIcon: Icons.calendar_month, label: 'Réservations', badge: 2),
          TratraNavItem(icon: Icons.person_outline, activeIcon: Icons.person, label: 'Profil'),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          _section(
            'Couleurs',
            Wrap(spacing: 10, runSpacing: 10, children: [
              for (final (name, c) in const [
                ('primary', TtColors.primary),
                ('primaryDark', TtColors.primaryDark),
                ('primarySoft', TtColors.primarySoft),
                ('accent', TtColors.accent),
                ('accentSoft', TtColors.accentSoft),
                ('night', TtColors.night),
                ('ink', TtColors.ink),
                ('ash', TtColors.ash),
                ('line', TtColors.line),
                ('canvas', TtColors.canvas),
              ])
                Column(children: [
                  Container(
                    width: 58,
                    height: 40,
                    decoration: BoxDecoration(
                      color: c,
                      borderRadius: BorderRadius.circular(TtRadius.control),
                      border: Border.all(color: TtColors.line),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(name, style: Theme.of(context).textTheme.labelMedium?.copyWith(fontSize: 10)),
                ]),
            ]),
          ),
          _section(
            'Typographie',
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('L’artisan qu’il vous faut', style: Theme.of(context).textTheme.displayMedium),
              const SizedBox(height: 8),
              Text('Titre de section h2', style: Theme.of(context).textTheme.headlineMedium),
              Text('Titre de carte h3', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text('Texte courant en Poppins, lisible et chaleureux.', style: Theme.of(context).textTheme.bodyMedium),
              Text('Texte secondaire', style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
          _section(
            'Boutons',
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 10, runSpacing: 10, children: [
                for (final v in TratraButtonVariant.values)
                  TratraButton(label: v.name, variant: v, onPressed: () {}),
              ]),
              const SizedBox(height: 14),
              Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
                TratraButton(label: 'Petit', size: TratraButtonSize.sm, onPressed: () {}),
                TratraButton(label: 'Moyen', onPressed: () {}),
                TratraButton(
                  label: 'Grand',
                  size: TratraButtonSize.lg,
                  trailing: const Icon(Icons.arrow_forward_rounded),
                  onPressed: () {},
                ),
                const TratraButton(label: 'Désactivé', onPressed: null),
              ]),
              const SizedBox(height: 14),
              TratraButton(
                label: _loading ? 'Chargement…' : 'Simuler un chargement',
                block: true,
                size: TratraButtonSize.lg,
                loading: _loading,
                onPressed: () async {
                  setState(() => _loading = true);
                  await Future<void>.delayed(const Duration(milliseconds: 1200));
                  if (mounted) setState(() => _loading = false);
                },
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: TtColors.night, borderRadius: TtRadius.cardAll),
                child: Row(children: [
                  TratraButton(
                    label: 'Accent sur nuit',
                    variant: TratraButtonVariant.accent,
                    leading: const Icon(Icons.bolt_rounded),
                    onPressed: () {},
                  ),
                ]),
              ),
            ]),
          ),
          _section(
            'Champs',
            Column(children: [
              TratraInput(
                label: 'Nom complet',
                hint: 'Prénom Nom',
                required: true,
                controller: _controller,
                leadingIcon: Icons.person_outline,
                helper: 'Tel qu’il apparaît sur votre pièce d’identité.',
              ),
              const SizedBox(height: 16),
              const TratraInput(label: 'E-mail', initialValue: 'adresse-invalide', errorText: 'Saisissez une adresse e-mail valide.'),
              const SizedBox(height: 16),
              const TratraInput(label: 'Mot de passe', obscureText: true, initialValue: 'secret123'),
              const SizedBox(height: 16),
              const TratraInput(label: 'Description', optional: true, maxLines: 3, hint: 'Décrivez votre besoin…'),
            ]),
          ),
          _section(
            'Cartes',
            Column(children: [
              TratraCard(
                onTap: () {},
                child: Row(children: [
                  const TratraAvatar(name: 'Aya Konan', size: 48),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Carte standard', style: Theme.of(context).textTheme.titleMedium),
                      Text('Appui = ondulation discrète', style: Theme.of(context).textTheme.bodySmall),
                    ]),
                  ),
                  const TratraStatusBadge(TratraStatus.booking, 'in_progress'),
                ]),
              ),
              const SizedBox(height: 12),
              const TratraCard(variant: TratraCardVariant.soft, child: Text('Carte douce — teinte verte de marque')),
              const SizedBox(height: 12),
              const TratraCard(variant: TratraCardVariant.accent, child: Text('Carte accent — mise en avant jaune')),
              const SizedBox(height: 12),
              const TratraCard(variant: TratraCardVariant.night, child: Text('Carte nuit — surface sombre')),
            ]),
          ),
          _section(
            'Badges & puces',
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final t in TratraTone.values) TratraBadge(t.name, tone: t, dot: true),
                const TratraBadge('En direct', tone: TratraTone.night, pulse: true),
              ]),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final s in ['pending', 'confirmed', 'in_progress', 'completed', 'cancelled'])
                  TratraStatusBadge(TratraStatus.booking, s),
              ]),
              const SizedBox(height: 12),
              Wrap(spacing: 8, children: [
                TratraChip(label: 'Plomberie', selected: _chip, icon: Icons.plumbing, onTap: () => setState(() => _chip = !_chip)),
                TratraChip(label: 'Électricité', selected: !_chip, icon: Icons.bolt, onTap: () => setState(() => _chip = !_chip)),
              ]),
            ]),
          ),
          _section(
            'Alertes',
            const Column(children: [
              TratraAlert(tone: TratraAlertTone.info, title: 'Information', message: 'Votre demande a bien été enregistrée.'),
              SizedBox(height: 10),
              TratraAlert(tone: TratraAlertTone.success, title: 'Succès', message: 'Les modifications ont été enregistrées.'),
              SizedBox(height: 10),
              TratraAlert(tone: TratraAlertTone.warning, title: 'Attention', message: 'Un document est manquant.'),
              SizedBox(height: 10),
              TratraAlert(tone: TratraAlertTone.danger, title: 'Erreur', message: 'L’action a échoué. Réessayez dans un instant.'),
            ]),
          ),
          _section(
            'Modales',
            Wrap(spacing: 10, runSpacing: 10, children: [
              TratraButton(
                label: 'Feuille basse',
                variant: TratraButtonVariant.outline,
                onPressed: () => showTratraSheet<void>(
                  context,
                  title: 'Titre de la feuille',
                  description: 'Poignée, titre, contenu défilant.',
                  child: const TratraInput(label: 'Champ', hint: 'Saisissez…'),
                ),
              ),
              TratraButton(
                label: 'Confirmation',
                variant: TratraButtonVariant.danger,
                onPressed: () => showTratraConfirm(
                  context,
                  title: 'Annuler la réservation ?',
                  message: 'Cette action est définitive.',
                  confirmLabel: 'Annuler la réservation',
                  cancelLabel: 'Retour',
                  danger: true,
                ),
              ),
            ]),
          ),
          _section(
            'Squelettes & état vide',
            const Column(children: [
              TratraSkeletonList(count: 2, padding: EdgeInsets.zero),
              SizedBox(height: 16),
              TratraSkeletonText(lines: 3),
              SizedBox(height: 8),
              TratraEmptyState(
                icon: Icons.inbox_outlined,
                title: 'Rien à afficher pour le moment',
                description: 'Un état vide explique la situation réelle et propose une action utile.',
              ),
            ]),
          ),
        ],
      ),
    );
  }
}
