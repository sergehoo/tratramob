// lib/statuses/statuses_screen.dart
//
// « Statuts » : Actualités (comme WhatsApp : Mon statut, Récentes, Vues — contacts et membres qui partagent avec tous), Mes statuts
// (compteurs de vues, suppression) et Confidentialité (audience par défaut, réponses, contacts à qui masquer ses statuts).
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
import 'package:flutter_tratra/statuses/status_presence.dart';

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
            bottom: const TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [Tab(text: 'Actualités'), Tab(text: 'Mes statuts'), Tab(text: 'Confidentialité')]),
          ),
          body: const TabBarView(children: [_UpdatesTab(), _MineTab(), _PrivacyTab()]),
        ),
      );
}

/// « Actualités », comme WhatsApp : « Mon statut », puis « Récentes » (au moins un statut non vu) et « Vues », contacts et membres qui
/// partagent avec tous réunis, le plus récent d'abord. Chaque avatar porte l'anneau segmenté de ses statuts.
class _UpdatesTab extends StatefulWidget {
  const _UpdatesTab();
  @override
  State<_UpdatesTab> createState() => _UpdatesTabState();
}

class _UpdatesTabState extends State<_UpdatesTab> {
  late final StatusApi _api = context.read<StatusApi>();
  StatusFeed? _feed;
  List<StatusGroup> _public = const [];
  int? _next;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([_api.feed(), _api.discover()]);
      final f = results[0] as StatusFeed;
      final d = results[1] as ({List<StatusGroup> groups, int? next});
      if (!mounted) return;
      setState(() {
        _feed = f;
        _public = d.groups;
        _next = d.next;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e, 'Les statuts n’ont pas pu être chargés.'));
    }
    if (mounted) maybeStatusPresence(context, listen: false)?.refresh(force: true);
  }

  Future<void> _more() async {
    final page = _next;
    if (page == null) return;
    try {
      final d = await _api.discover(page: page);
      if (mounted) setState(() { _public = [..._public, ...d.groups]; _next = d.next; });
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e, 'La suite n’a pas pu être chargée.'), error: true);
    }
  }

  Future<void> _compose() async {
    final f = _feed;
    if (f == null) return;
    final item = await Navigator.of(context).push<StatusItem>(MaterialPageRoute(builder: (_) => StatusComposerScreen(limits: f.limits)));
    if (item != null) _load();
  }

  static String ago(DateTime when) {
    final d = DateTime.now().difference(when);
    if (d.inMinutes < 1) return 'À l’instant';
    if (d.inMinutes < 60) return 'Il y a ${d.inMinutes} min';
    if (d.inHours < 24) return 'Il y a ${d.inHours} h';
    return 'Hier';
  }

  Widget _header(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(TtSpace.s4, TtSpace.s4, TtSpace.s4, TtSpace.s1),
        child: Text(text, style: TratraTheme.style(TtType.caption, color: TtColors.ash).copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.4)),
      );

  Widget _row(List<StatusGroup> all, int i, Set<int> contactIds) {
    final g = all[i];
    return ListTile(
      key: ValueKey('status-row-${g.author.id}'),
      contentPadding: const EdgeInsets.symmetric(horizontal: TtSpace.s4),
      leading: StatusRing(
        unseen: !g.seen,
        count: g.statuses.length,
        unseenCount: g.unseen,
        size: 58,
        child: TratraAvatar(name: g.author.name, photoUrl: g.author.avatar == null ? null : resolveMediaUrl(g.author.avatar!), size: 46),
      ),
      title: Text(g.author.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TratraTheme.style(TtType.title).copyWith(fontWeight: g.seen ? FontWeight.w500 : FontWeight.w700)),
      subtitle: Text('${ago(latestOf(g))}${contactIds.contains(g.author.id) ? '' : ' · Partagé avec tous'}', style: TratraTheme.style(TtType.bodySm, color: TtColors.ash)),
      onTap: () => openStatusViewer(context, all, i, onDone: _load),
    );
  }

  @override
  Widget build(BuildContext context) {
    final f = _feed;
    if (_error != null && f == null) {
      return TratraEmptyState(icon: Icons.cloud_off_rounded, title: 'Statuts indisponibles', description: _error, actions: [TratraButton(label: 'Réessayer', variant: TratraButtonVariant.outline, onPressed: _load)]);
    }
    if (f == null) return const TratraSkeletonList(count: 4);
    final contactIds = {for (final g in f.contacts) g.author.id};
    final others = [...f.contacts, ..._public.where((g) => !contactIds.contains(g.author.id))];
    final recent = others.where((g) => !g.seen).toList()..sort((a, b) => latestOf(b).compareTo(latestOf(a)));
    final viewed = others.where((g) => g.seen).toList()..sort((a, b) => latestOf(b).compareTo(latestOf(a)));
    final ordered = [...recent, ...viewed];
    final mine = f.mine;
    return Stack(children: [
      RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.only(bottom: 96), children: [
          ListTile(
            key: const ValueKey('status-row-mine'),
            contentPadding: const EdgeInsets.fromLTRB(TtSpace.s4, TtSpace.s2, TtSpace.s4, 0),
            leading: Stack(clipBehavior: Clip.none, children: [
              mine.statuses.isEmpty
                  ? TratraAvatar(name: mine.author.name, photoUrl: mine.author.avatar == null ? null : resolveMediaUrl(mine.author.avatar!), size: 52)
                  : StatusRing(unseen: false, count: mine.statuses.length, size: 58, child: TratraAvatar(name: mine.author.name, photoUrl: mine.author.avatar == null ? null : resolveMediaUrl(mine.author.avatar!), size: 46)),
              if (mine.statuses.isEmpty)
                const Positioned(right: -2, bottom: -2, child: CircleAvatar(radius: 11, backgroundColor: TtColors.accent, child: Icon(Icons.add_rounded, size: 16, color: TtColors.night))),
            ]),
            title: Text('Mon statut', style: TratraTheme.style(TtType.title)),
            subtitle: Text(mine.statuses.isEmpty ? 'Appuyez pour ajouter un statut' : '${mine.statuses.length} statut${mine.statuses.length > 1 ? 's' : ''} · ${ago(latestOf(mine))}',
                style: TratraTheme.style(TtType.bodySm, color: TtColors.ash)),
            onTap: () => mine.statuses.isEmpty ? _compose() : openStatusViewer(context, [mine], 0, onDone: _load),
          ),
          if (recent.isNotEmpty) ...[_header('RÉCENTES'), for (var i = 0; i < recent.length; i++) _row(ordered, i, contactIds)],
          if (viewed.isNotEmpty) ...[_header('VUES'), for (var i = 0; i < viewed.length; i++) _row(ordered, recent.length + i, contactIds)],
          if (others.isEmpty)
            Padding(
              padding: const EdgeInsets.all(TtSpace.s6),
              child: Text('Aucun statut pour le moment. Les statuts de vos contacts Tratra et ceux que des membres partagent avec tous apparaîtront ici.',
                  textAlign: TextAlign.center, style: TratraTheme.style(TtType.bodySm, color: TtColors.ash)),
            ),
          if (_next != null) Center(child: TextButton(onPressed: _more, child: const Text('Voir plus'))),
        ]),
      ),
      Positioned(
        right: TtSpace.s4,
        bottom: TtSpace.s4,
        child: FloatingActionButton(
          heroTag: 'status-compose',
          tooltip: 'Nouveau statut',
          backgroundColor: TtColors.primary,
          foregroundColor: Colors.white,
          onPressed: _compose,
          child: const Icon(Icons.add_a_photo_outlined),
        ),
      ),
    ]);
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
