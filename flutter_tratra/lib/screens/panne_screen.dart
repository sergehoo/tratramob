// lib/screens/panne_screen.dart
//
// « J'ai une panne » : le client décrit son problème avec ses mots (« mon frigo ne refroidit plus », « écran cassé ») ; le serveur
// (`GET /handy/catalog/match/`, public) propose les prestations et métiers pertinents du catalogue commun, puis le client voit les offres
// des artisans, éventuellement dans sa commune. Le texte n'est ni conservé ni journalisé ; rien n'est inventé côté application.
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/screens/all_services_screen.dart';
import 'package:flutter_tratra/screens/home/home_icons.dart';

const int panneMaxChars = 300;

const List<String> panneExamples = [
  'Mon frigo ne refroidit plus',
  'L’écran de mon téléphone est cassé',
  'Fuite d’eau sous l’évier',
  'Ma clim coule',
  'Ma voiture ne démarre pas',
];

/// Une prestation (ou un métier) proposée pour la panne décrite.
class PanneMatch {
  const PanneMatch({required this.id, required this.name, required this.kind, required this.tradeName, this.iconKey, this.offersTotal = 0});

  final String id;
  final String name;
  final String kind; // « service » (prestation) ou « trade » (métier)
  final String tradeName;
  final String? iconKey;
  final int offersTotal;

  factory PanneMatch.fromJson(Map<String, dynamic> j) => PanneMatch(
        id: '${j['id']}',
        name: '${j['name'] ?? ''}',
        kind: '${j['kind'] ?? 'service'}',
        tradeName: '${j['trade_name'] ?? ''}',
        iconKey: j['icon_key']?.toString(),
        offersTotal: j['offers_total'] is int ? j['offers_total'] as int : int.tryParse('${j['offers_total']}') ?? 0,
      );
}

/// Appel public (sans jeton) : prestations correspondant à la description.
Future<List<PanneMatch>> fetchPanneMatches(BaseApi api, String text) async {
  final uri = Uri.parse('${api.baseUrl}/catalog/match/').replace(queryParameters: {'q': text.trim()});
  final r = await api.client.get(uri, headers: await api.getHeaders(withAuth: false));
  if (r.statusCode != 200) api.handleError(r);
  final decoded = api.decodeBody(r);
  final rows = decoded is Map && decoded['results'] is List ? decoded['results'] as List : const [];
  return [for (final row in rows) if (row is Map) PanneMatch.fromJson(Map<String, dynamic>.from(row))];
}

class PanneScreen extends StatefulWidget {
  const PanneScreen({super.key, this.initialText});

  final String? initialText;

  @override
  State<PanneScreen> createState() => _PanneScreenState();
}

class _PanneScreenState extends State<PanneScreen> {
  late final BaseApi _api = context.read<BaseApi>();
  late final TextEditingController _text = TextEditingController(text: widget.initialText ?? '');
  final TextEditingController _commune = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final GlobalKey _resultsKey = GlobalKey();
  bool _busy = false;
  String? _error;
  List<PanneMatch>? _results;

  @override
  void initState() {
    super.initState();
    if ((widget.initialText ?? '').trim().length >= 3) WidgetsBinding.instance.addPostFrameCallback((_) => _analyse());
  }

  @override
  void dispose() {
    _text.dispose();
    _commune.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _analyse() async {
    final text = _text.text.trim();
    if (text.length < 3 || _busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final results = await fetchPanneMatches(_api, text);
      if (!mounted) return;
      setState(() => _results = results);
      // Les résultats arrivent sous le formulaire : on les amène à l'écran.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final target = _resultsKey.currentContext;
        if (target != null && mounted) {
          Scrollable.ensureVisible(target, duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic, alignment: 0.05);
        }
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'L’analyse n’a pas pu être faite. Vérifiez votre connexion et réessayez.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _open(PanneMatch m) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => AllServicesScreen(initialCategory: m.name, initialCommune: _commune.text.trim()),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    return Scaffold(
      backgroundColor: TtColors.canvas,
      appBar: const TratraAppBar(title: 'J’ai une panne'),
      body: ListView(
        controller: _scroll,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(TtSpace.s4, TtSpace.s4, TtSpace.s4, TtSpace.s8 + MediaQuery.paddingOf(context).bottom),
        children: [
          Text('Décrivez le problème avec vos mots : Tratra trouve le bon métier et les artisans près de chez vous.',
              style: TratraTheme.style(TtType.body, color: TtColors.inkSoft)),
          const SizedBox(height: TtSpace.s4),
          TratraInput(
            key: const ValueKey('panne-text'),
            controller: _text,
            label: 'Quel est le problème ?',
            hint: 'Ex. Mon frigo ne refroidit plus depuis hier',
            maxLines: 4,
            minLines: 3,
            maxLength: panneMaxChars,
            helper: 'Votre description n’est pas enregistrée.',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: TtSpace.s2),
          LayoutBuilder(
            builder: (context, box) => Wrap(spacing: TtSpace.s2, runSpacing: TtSpace.s2, children: [
              for (final ex in panneExamples)
                _ExampleChip(label: ex, maxWidth: box.maxWidth, onTap: () {
                  _text.text = ex;
                  _analyse();
                }),
            ]),
          ),
          const SizedBox(height: TtSpace.s4),
          TratraInput(
            key: const ValueKey('panne-commune'),
            controller: _commune,
            label: 'Commune ou quartier',
            optional: true,
            hint: 'Cocody, Yopougon, Marcory…',
            leadingIcon: Icons.place_outlined,
            maxLength: 60,
          ),
          const SizedBox(height: TtSpace.s4),
          TratraButton(
            key: const ValueKey('panne-submit'),
            label: 'Trouver le bon artisan',
            block: true,
            loading: _busy,
            leading: const Icon(Icons.build_outlined),
            onPressed: _text.text.trim().length >= 3 && !_busy ? _analyse : null,
          ),
          if (_error != null) ...[const SizedBox(height: TtSpace.s4), TratraAlert(tone: TratraAlertTone.danger, message: _error!)],
          if (results != null && results.isEmpty) ...[
            SizedBox(key: _resultsKey, height: TtSpace.s5),
            const TratraEmptyState(
              compact: true,
              icon: Icons.help_outline_rounded,
              title: 'Problème non reconnu',
              description: 'Précisez l’appareil ou la pièce concernée (« frigo », « clim », « robinet »…), ou parcourez tous les métiers.',
            ),
          ],
          if (results != null && results.isNotEmpty) ...[
            SizedBox(key: _resultsKey, height: TtSpace.s5),
            Text('Prestations correspondant à votre panne', style: TratraTheme.style(TtType.h2)),
            const SizedBox(height: TtSpace.s2),
            for (final m in results)
              Padding(
                padding: const EdgeInsets.only(bottom: TtSpace.s2),
                child: TratraCard(
                  key: ValueKey('panne-result-${m.id}'),
                  padding: TratraCard.compact,
                  onTap: () => _open(m),
                  semanticLabel: '${m.name}, ${m.kind == 'service' ? m.tradeName : 'métier'}',
                  child: Row(children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(color: TtColors.primarySoft, borderRadius: TtRadius.panelAll),
                      child: Center(child: FaIcon(categoryIconFor(m.iconKey), color: TtColors.primaryDark, size: 20)),
                    ),
                    const SizedBox(width: TtSpace.s3),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(m.name, style: TratraTheme.style(TtType.title)),
                        Text(
                          '${m.kind == 'service' ? m.tradeName : 'Métier'} · '
                          '${m.offersTotal > 0 ? '${m.offersTotal} offre${m.offersTotal > 1 ? 's' : ''}' : 'aucune offre pour l’instant'}',
                          style: TratraTheme.style(TtType.caption, color: TtColors.ash),
                        ),
                      ]),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: TtColors.fog),
                  ]),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Exemple de panne : une ligne, tronquée proprement sur un écran étroit ou avec un texte agrandi (jamais de débordement).
class _ExampleChip extends StatelessWidget {
  const _ExampleChip({required this.label, required this.maxWidth, required this.onTap});
  final String label;
  final double maxWidth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Material(
          color: TtColors.surface,
          shape: const StadiumBorder(side: BorderSide(color: TtColors.line)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 40),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft).copyWith(fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ),
      );
}
