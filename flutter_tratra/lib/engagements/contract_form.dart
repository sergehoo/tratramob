// lib/engagements/contract_form.dart
//
// Brouillon de contrat. Rien n'engage personne tant que le contrat n'est pas PROPOSÉ puis ACCEPTÉ par les deux parties ;
// l'adresse n'est visible du prestataire qu'à la proposition. Le serveur revalide toutes les règles.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/engagements/contract_screen.dart';
import 'package:flutter_tratra/engagements/engagements_api.dart';
import 'package:flutter_tratra/engagements/engagements_ui.dart';
import 'package:flutter_tratra/engagements/labels.dart';
import 'package:flutter_tratra/engagements/posting_form.dart' show TermsContext;
import 'package:flutter_tratra/engagements/terms_form.dart';
import 'package:flutter_tratra/screens/dashboard/dash_ui.dart' show DashPage;

class ContractFormScreen extends StatefulWidget {
  /// `existing` : brouillon à modifier ; `application` + `posting` : contrat issu d'une candidature retenue ;
  /// `worker` : contrat direct avec un professionnel déjà choisi.
  const ContractFormScreen({super.key, this.existing, this.application, this.posting, this.worker});
  final Json? existing;
  final int? application;
  final int? posting;
  final PickedWorker? worker;
  @override
  State<ContractFormScreen> createState() => _ContractFormScreenState();
}

class _ContractFormScreenState extends State<ContractFormScreen> {
  late final EngagementsApi _api = context.read<EngagementsApi>();
  late final Future<(TermsContext, TermsValue, Json?)> _load = _loadAll();
  final _base = randomHex();
  TermsValue? _value;
  PickedWorker? _worker;
  Map<String, String> _errors = const {};
  String? _error;
  int? _saved;
  String? _busy;

  bool get _direct => widget.application == null && widget.existing == null;

  @override
  void initState() {
    super.initState();
    _worker = widget.worker;
  }

  Future<(TermsContext, TermsValue, Json?)> _loadAll() async {
    final ctx = await TermsContext.load(_api);
    if (widget.existing != null) return (ctx, TermsValue.fromContract(widget.existing!), null);
    if (widget.posting == null) return (ctx, TermsValue(), null);
    // Les conditions de l'offre et la candidature retenue (montant proposé, disponibilité) servent de point de départ.
    final posting = await _api.getMap('/postings/${widget.posting}/');
    final apps = widget.application == null ? <Json>[] : (await _api.getList('/postings/${widget.posting}/applications/?limit=50'));
    final chosen = apps.where((a) => a.i('id') == widget.application).firstOrNull;
    final v = TermsValue.fromPosting(posting)..address = '';
    v.city = posting.s('city');
    if (chosen != null && chosen.sn('proposed_amount') != null) v.amount = TermsValue.fromPosting({'amount': chosen['proposed_amount']}).amount;
    final today = isoDay(DateTime.now());
    if (v.startDate.compareTo(today) < 0) v.startDate = (chosen?.sn('available_from') ?? '').compareTo(today) >= 0 ? chosen!.s('available_from') : '';
    return (ctx, v, chosen);
  }

  Future<void> _submit(TermsValue value, bool propose) async {
    if (_direct && _worker == null) {
      setState(() => _errors = {'worker': 'Choisissez le professionnel.'});
      return;
    }
    setState(() {
      _busy = propose ? 'propose' : 'save';
      _error = null;
      _errors = const {};
    });
    final terms = value.toContract();
    var id = widget.existing?.i('id') ?? _saved;
    try {
      if (widget.existing != null) {
        await _api.patch('/contracts/$id/', {...terms, 'expected_version': widget.existing!.i('version')});
      } else if (id == null) {
        final body = widget.application != null ? {...terms, 'application': widget.application} : {...terms, 'worker': _worker?.id, if (value.organization.isNotEmpty) 'organization': int.tryParse(value.organization)};
        final created = await _api.post('/contracts/', body, intentKey('contract', _base, body));
        id = created.i('id');
        _saved = id;
      }
      if (propose && id != null) {
        try {
          await _api.post('/contracts/$id/propose/');
        } catch (e) {
          if (!mounted) return;
          setState(() {
            _errors = fieldErrorsOf(e);
            _error = 'Brouillon enregistré, mais la proposition n’a pas pu être envoyée : ${messageOf(e)}';
            _busy = null;
          });
          return;
        }
      }
      if (!mounted || id == null) return;
      if (widget.existing != null) {
        Navigator.of(context).pop(true);
      } else {
        await Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => ContractScreen(id: id!)));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errors = fieldErrorsOf(e);
        _error = errorCodeOf(e) == 'version_conflict' ? 'Ce brouillon a été modifié ailleurs. Rouvrez-le pour repartir de la dernière version.' : messageOf(e, 'Enregistrement impossible. Rien n’a été envoyé.');
        _busy = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) => DashPage(
        title: widget.existing != null ? 'Modifier le brouillon' : 'Préparer un contrat',
        body: FutureBuilder<(TermsContext, TermsValue, Json?)>(
          future: _load,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) return const TratraSkeletonList(count: 4);
            final data = snap.data;
            if (snap.hasError || data == null) {
              return TratraEmptyState(icon: Icons.cloud_off_rounded, title: 'Formulaire indisponible', description: messageOf(snap.error ?? '', 'Les conditions de départ n’ont pas pu être chargées.'));
            }
            final (ctx, initial, chosen) = data;
            final value = _value ??= initial;
            return ListView(
              padding: const EdgeInsets.fromLTRB(TtSpace.s4, TtSpace.s4, TtSpace.s4, TtSpace.s8),
              children: [
                const TratraAlert(
                  tone: TratraAlertTone.brand,
                  title: 'Un accord clair, accepté par les deux parties',
                  message: 'Le prestataire relit exactement ces conditions et les accepte (ou demande une modification). Toute évolution ultérieure passe par un avenant accepté par l’autre partie, sans effet rétroactif.',
                ),
                if (chosen != null && chosen.sn('proposed_amount') != null) ...[
                  const SizedBox(height: 12),
                  TratraAlert(tone: TratraAlertTone.info, message: '${chosen.m('applicant').s('name')} propose ${fcfa(chosen.s('proposed_amount'))} : ce montant est repris ci-dessous.'),
                ],
                const SizedBox(height: 14),
                TratraCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    if (_direct) ...[
                      WorkerPicker(api: _api, label: 'Prestataire', picked: _worker, onPicked: (w) => setState(() => _worker = w)),
                      if (_errors['worker'] != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_errors['worker']!, style: TratraTheme.style(TtType.caption, color: TtColors.dangerInk))),
                      const SizedBox(height: 16),
                    ],
                    TermsFields(contractMode: true, value: value, onChanged: () => setState(() {}), errors: _errors, categories: ctx.categories, rules: ctx.rulesFor, enabled: _busy == null),
                  ]),
                ),
                if (_error != null) ...[const SizedBox(height: 14), TratraAlert(tone: TratraAlertTone.danger, message: _error!)],
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(child: TratraButton(label: widget.existing != null ? 'Enregistrer' : 'Brouillon', variant: TratraButtonVariant.outline, loading: _busy == 'save', onPressed: _busy == null ? () => _submit(value, false) : null)),
                  const SizedBox(width: 10),
                  Expanded(child: TratraButton(label: 'Enregistrer et proposer', loading: _busy == 'propose', onPressed: _busy == null ? () => _submit(value, true) : null)),
                ]),
              ],
            );
          },
        ),
      );
}
