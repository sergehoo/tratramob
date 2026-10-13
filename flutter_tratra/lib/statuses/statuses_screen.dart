// lib/statuses/statuses_screen.dart
//
// « Statuts » : Découvrir (statuts élargis de membres qui ne sont pas des contacts, regroupés par auteur), Mes statuts (compteurs de vues,
// suppression) et Confidentialité (audience par défaut, réponses, contacts à qui masquer ses statuts).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/messaging/media_widgets.dart';
import 'package:flutter_tratra/screens/dashboard/dash_ui.dart' show showMessage;
import 'package:flutter_tratra/screens/dashboard/dashboard_core.dart' show friendlyError;
import 'package:flutter_tratra/statuses/status_api.dart';
import 'package:flutter_tratra/statuses/status_bar.dart';
import 'package:flutter_tratra/statuses/status_composer.dart';
import 'package:flutter_tratra/statuses/status_models.dart';

class StatusesScreen extends StatelessWidget {
  const StatusesScreen({super.key});
  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 3,
        child: Scaffold(
          backgroundColor: TtColors.canvas,
          appBar: AppBar(
            backgroundColor: TtColors.surface,
            foregroundColor: TtColors.ink,
            title: Text('Statuts', style: TratraTheme.style(TtType.h3)),
            bottom: const TabBar(tabs: [Tab(text: 'Découvrir'), Tab(text: 'Mes statuts'), Tab(text: 'Confidentialité')]),
          ),
          body: const TabBarView(children: [_DiscoverTab(), _MineTab(), _PrivacyTab()]),
        ),
      );
}

class _DiscoverTab extends StatefulWidget {
  const _DiscoverTab();
  @override
  State<_DiscoverTab> createState() => _DiscoverTabState();
}

class _DiscoverTabState extends State<_DiscoverTab> {
  late final StatusApi _api = context.read<StatusApi>();
  List<StatusGroup>? _groups;
  int? _next;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    try {
      final r = await _api.discover(page: more ? (_next ?? 1) : 1);
      if (!mounted) return;
      setState(() {
        _groups = more ? [...?_groups, ...r.groups] : r.groups;
        _next = r.next;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e, 'Les statuts à découvrir n’ont pas pu être chargés.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groups;
    if (_error != null && groups == null) {
      return TratraEmptyState(icon: Icons.cloud_off_rounded, title: 'Statuts indisponibles', description: _error, actions: [TratraButton(label: 'Réessayer', variant: TratraButtonVariant.outline, onPressed: _load)]);
    }
    if (groups == null) return const TratraSkeletonList(count: 3);
    if (groups.isEmpty) {
      return const TratraEmptyState(icon: Icons.explore_outlined, title: 'Rien à découvrir pour le moment', description: 'Les statuts que des membres choisissent de partager avec tous apparaîtront ici.');
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: GridView.builder(
        padding: const EdgeInsets.all(TtSpace.s4),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 16, crossAxisSpacing: 8, childAspectRatio: 0.78),
        itemCount: groups.length + (_next != null ? 1 : 0),
        itemBuilder: (_, i) {
          if (i == groups.length) return Center(child: TextButton(onPressed: () => _load(more: true), child: const Text('Voir plus')));
          final g = groups[i];
          return InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => openStatusViewer(context, groups, i, onDone: _load),
            child: Column(children: [
              StatusRing(unseen: !g.seen, size: 72, child: TratraAvatar(name: g.author.name, photoUrl: g.author.avatar == null ? null : resolveMediaUrl(g.author.avatar!), size: 58)),
              const SizedBox(height: 6),
              Text(g.author.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TratraTheme.style(TtType.caption, color: g.seen ? TtColors.ash : TtColors.ink).copyWith(fontWeight: g.seen ? FontWeight.w500 : FontWeight.w700)),
              Text('${g.statuses.length} statut${g.statuses.length > 1 ? 's' : ''}', style: TratraTheme.style(TtType.caption, color: TtColors.ash).copyWith(fontSize: 11)),
            ]),
          );
        },
      ),
    );
  }
}

class _MineTab extends StatefulWidget {
  const _MineTab();
  @override
  State<_MineTab> createState() => _MineTabState();
}

class _MineTabState extends State<_MineTab> {
  late final StatusApi _api = context.read<StatusApi>();
  StatusFeed? _feed;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final f = await _api.feed();
      if (mounted) setState(() { _feed = f; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e, 'Vos statuts n’ont pas pu être chargés.'));
    }
  }

  Future<void> _remove(StatusItem s) async {
    final sure = await showTratraConfirm(context, title: 'Supprimer ce statut ?', message: 'Cette action est définitive.', confirmLabel: 'Supprimer', danger: true);
    if (!sure) return;
    try {
      await _api.delete(s.id);
      _load();
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e, 'Le statut n’a pas pu être supprimé.'), error: true);
    }
  }

  Future<void> _compose() async {
    final f = _feed;
    if (f == null) return;
    final item = await Navigator.of(context).push<StatusItem>(MaterialPageRoute(builder: (_) => StatusComposerScreen(limits: f.limits)));
    if (item != null) _load();
  }

  @override
  Widget build(BuildContext context) {
    final f = _feed;
    if (_error != null && f == null) return TratraEmptyState(icon: Icons.cloud_off_rounded, title: 'Statuts indisponibles', description: _error);
    if (f == null) return const TratraSkeletonList(count: 2);
    final mine = f.mine;
    return ListView(padding: const EdgeInsets.all(TtSpace.s4), children: [
      TratraButton(label: 'Nouveau statut', block: true, leading: const Icon(Icons.add_rounded, size: 18), onPressed: _compose),
      const SizedBox(height: TtSpace.s3),
      if (mine.statuses.isEmpty)
        TratraEmptyState(icon: Icons.visibility_outlined, title: 'Aucun statut actif', description: 'Un statut reste visible ${f.limits.ttlHours} h puis disparaît automatiquement.')
      else
        for (final s in mine.statuses)
          Padding(
            padding: const EdgeInsets.only(bottom: TtSpace.s2),
            child: TratraCard(
              padding: TratraCard.compact,
              onTap: () => openStatusViewer(context, [mine], 0, onDone: _load),
              child: Row(children: [
                Container(width: 44, height: 44, alignment: Alignment.center, decoration: BoxDecoration(color: TtColors.primarySoft, borderRadius: BorderRadius.circular(12)), child: Text(s.kind == 'text' ? 'Aa' : (s.kind == 'photo' ? '📷' : '🎥'))),
                const SizedBox(width: TtSpace.s3),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s.text.isEmpty ? (s.kind == 'photo' ? 'Photo' : 'Vidéo') : s.text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TratraTheme.style(TtType.title)),
                    Text('Expire dans ${s.timeLeft} · ${s.audience == 'extended' ? 'Tous les membres' : 'Mes contacts'}', style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
                  ]),
                ),
                Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.visibility_outlined, size: 16, color: TtColors.ash), const SizedBox(width: 4), Text('${s.viewsUnique}')]),
                IconButton(tooltip: 'Supprimer ce statut', icon: const Icon(Icons.delete_outline_rounded), onPressed: () => _remove(s)),
              ]),
            ),
          ),
    ]);
  }
}

class _PrivacyTab extends StatefulWidget {
  const _PrivacyTab();
  @override
  State<_PrivacyTab> createState() => _PrivacyTabState();
}

class _PrivacyTabState extends State<_PrivacyTab> {
  late final StatusApi _api = context.read<StatusApi>();
  String _audience = 'contacts';
  bool _replies = true;
  bool _loaded = false;
  List<Map<String, dynamic>>? _contacts;

  @override
  void initState() {
    super.initState();
    _api.settings().then((s) {
      if (mounted) setState(() { _audience = '${s['audience'] ?? 'contacts'}'; _replies = s['allow_replies'] != false; _loaded = true; });
    }).catchError((_) {});
    _api.contacts().then((c) { if (mounted) setState(() => _contacts = c); }).catchError((_) { if (mounted) setState(() => _contacts = []); });
  }

  Future<void> _save({String? audience, bool? replies}) async {
    try {
      final s = await _api.saveSettings(audience: audience, allowReplies: replies);
      if (mounted) setState(() { _audience = '${s['audience']}'; _replies = s['allow_replies'] != false; });
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e, 'Le réglage n’a pas pu être enregistré.'), error: true);
    }
  }

  Future<void> _toggle(Map<String, dynamic> c) async {
    final id = (c['user'] as num).toInt();
    try {
      if (c['excluded'] == true) {
        await _api.include(id);
      } else {
        await _api.exclude(id);
      }
      if (mounted) setState(() => c['excluded'] = !(c['excluded'] == true));
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e, 'La modification n’a pas pu être enregistrée.'), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const TratraSkeletonList(count: 2);
    return ListView(padding: const EdgeInsets.all(TtSpace.s4), children: [
      Text('Visibilité par défaut', style: TratraTheme.style(TtType.title)),
      RadioGroup<String>(
        groupValue: _audience,
        onChanged: (v) => v == null ? null : _save(audience: v),
        child: const Column(children: [
          RadioListTile<String>(value: 'contacts', contentPadding: EdgeInsets.zero, title: Text('Mes contacts Tratra'), subtitle: Text('Membres avec qui vous avez une réservation, un contrat ou une conversation.')),
          RadioListTile<String>(value: 'extended', contentPadding: EdgeInsets.zero, title: Text('Tous les membres'), subtitle: Text('Visible aussi dans « Découvrir les statuts ».')),
        ]),
      ),
      SwitchListTile(contentPadding: EdgeInsets.zero, value: _replies, onChanged: (v) => _save(replies: v), title: const Text('Autoriser les réponses par message')),
      const SizedBox(height: TtSpace.s4),
      Text('Masquer mes statuts à certains contacts', style: TratraTheme.style(TtType.title)),
      Text('Ces membres ne sont pas prévenus.', style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
      const SizedBox(height: TtSpace.s2),
      if (_contacts == null)
        const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
      else if (_contacts!.isEmpty)
        Text('Vous n’avez pas encore de contact Tratra.', style: TratraTheme.style(TtType.bodySm, color: TtColors.ash))
      else
        for (final c in _contacts!)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: TratraAvatar(name: '${c['name']}', size: 36),
            title: Text('${c['name']}'),
            trailing: TextButton(onPressed: () => _toggle(c), child: Text(c['excluded'] == true ? 'Masqué — rétablir' : 'Masquer')),
          ),
    ]);
  }
}
