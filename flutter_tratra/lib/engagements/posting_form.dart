// lib/engagements/posting_form.dart
//
// Publier ou modifier un besoin de longue durée. « Publier » = enregistrer puis rendre visible : la publication est revalidée
// par le serveur ; si elle échoue, le brouillon reste enregistré et le dit.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/engagements/engagements_api.dart';
import 'package:flutter_tratra/engagements/engagements_ui.dart';
import 'package:flutter_tratra/engagements/labels.dart';
import 'package:flutter_tratra/engagements/posting_screen.dart';
import 'package:flutter_tratra/engagements/terms_form.dart';
import 'package:flutter_tratra/screens/dashboard/dash_ui.dart' show DashPage;

/// Contexte des formulaires : métiers, règles par métier, organisations habilitées — tout vient du serveur.
class TermsContext {
  const TermsContext({required this.categories, required this.rulesIndex, required this.organizations});
  final List<Json> categories;
  final Json rulesIndex;
  final List<Json> organizations;

  Json? rulesFor(String categoryId) {
    final match = rulesIndex.l('categories').where((c) => '${c.m('category').i('id')}' == categoryId);
    return match.isNotEmpty ? match.first : rulesIndex.m('default');
  }

  static Future<TermsContext> load(EngagementsApi api) async {
    final results = await Future.wait<Object>([api.categories(), api.getMap('/rules/'), api.getMap('/me/overview/')]);
    return TermsContext(categories: results[0] as List<Json>, rulesIndex: results[1] as Json, organizations: (results[2] as Json).l('organizations'));
  }
}

class PostingFormScreen extends StatefulWidget {
  const PostingFormScreen({super.key, this.existing});
  final Json? existing;
  @override
  State<PostingFormScreen> createState() => _PostingFormScreenState();
}

class _PostingFormScreenState extends State<PostingFormScreen> {
  late final EngagementsApi _api = context.read<EngagementsApi>();
  late final TermsValue _value = widget.existing == null ? TermsValue() : TermsValue.fromPosting(widget.existing!);
  late final Future<TermsContext> _ctx = TermsContext.load(_api);
  final _base = randomHex();
  Map<String, String> _errors = const {};
  String? _error;
  int? _saved;
  String? _busy;

  bool get _editing => widget.existing != null;
  bool get _draft => widget.existing == null || widget.existing!.s('status') == 'draft';

  Future<void> _submit(bool publish) async {
    setState(() {
      _busy = publish ? 'publish' : 'save';
      _error = null;
      _errors = const {};
    });
    final body = _value.toPosting();
    var id = widget.existing?.i('id') ?? _saved;
    try {
      if (_editing) {
        await _api.patch('/postings/$id/', {...body, 'expected_version': widget.existing!.i('version')});
      } else if (id == null) {
        final created = await _api.post('/postings/', body, intentKey('posting', _base, body));
        id = created.i('id');
        _saved = id;
      }
      if (publish && id != null && _draft) {
        try {
          await _api.post('/postings/$id/publish/');
        } catch (e) {
          if (!mounted) return;
          setState(() {
            _errors = fieldErrorsOf(e);
            _error = 'Le besoin est enregistré en brouillon mais n’a pas pu être publié : ${messageOf(e)}';
            _busy = null;
          });
          return;
        }
      }
      if (!mounted || id == null) return;
      await Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => PostingScreen(id: id!)));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errors = fieldErrorsOf(e);
        _error = errorCodeOf(e) == 'version_conflict' ? 'Ce besoin a été modifié ailleurs. Rouvrez-le pour repartir de la dernière version.' : messageOf(e, 'Enregistrement impossible. Rien n’a été publié.');
        _busy = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) => DashPage(
        title: _editing ? 'Modifier le besoin' : 'Publier un besoin',
        body: FutureBuilder<TermsContext>(
          future: _ctx,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) return const TratraSkeletonList(count: 4);
            if (snap.hasError || snap.data == null) {
              return TratraEmptyState(icon: Icons.cloud_off_rounded, title: 'Formulaire indisponible', description: messageOf(snap.error ?? '', 'Les métiers et règles n’ont pas pu être chargés.'));
            }
            final ctx = snap.data!;
            return ListView(
              padding: const EdgeInsets.fromLTRB(TtSpace.s4, TtSpace.s4, TtSpace.s4, TtSpace.s8),
              children: [
                if (!_editing)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 14),
                    child: TratraAlert(tone: TratraAlertTone.brand, message: 'Décrivez la mission, le planning et la rémunération. Seuls des professionnels vérifiés pourront postuler ; vous choisissez qui retenir, puis vous préparez le contrat ensemble.'),
                  ),
                TratraCard(
                  child: TermsFields(contractMode: false, value: _value, onChanged: () => setState(() {}), errors: _errors, categories: ctx.categories, rules: ctx.rulesFor, organizations: ctx.organizations, enabled: _busy == null),
                ),
                if (_error != null) ...[const SizedBox(height: 14), TratraAlert(tone: TratraAlertTone.danger, message: _error!)],
                const SizedBox(height: 16),
                if (_editing && !_draft)
                  TratraButton(label: 'Enregistrer les modifications', block: true, loading: _busy == 'save', onPressed: _busy == null ? () => _submit(false) : null)
                else
                  Row(children: [
                    Expanded(child: TratraButton(label: 'Enregistrer le brouillon', variant: TratraButtonVariant.outline, loading: _busy == 'save', onPressed: _busy == null ? () => _submit(false) : null)),
                    const SizedBox(width: 10),
                    Expanded(child: TratraButton(label: 'Publier', loading: _busy == 'publish', onPressed: _busy == null ? () => _submit(true) : null)),
                  ]),
              ],
            );
          },
        ),
      );
}
