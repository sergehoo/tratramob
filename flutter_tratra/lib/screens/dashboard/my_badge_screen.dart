// lib/screens/dashboard/my_badge_screen.dart
//
// « Mon badge Tratra ID » (artisan) : badge numérique (photo, métiers, KYC vérifié), QR permanent, lien de
// vérification et badge imprimable (PDF). GET /me/tratra-id/ — mêmes données que le web (/dashboard/badge).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/screens/dashboard/dash_nav.dart';
import 'package:flutter_tratra/screens/dashboard/dash_ui.dart';
import 'package:flutter_tratra/screens/dashboard/dashboard_core.dart';
import 'package:flutter_tratra/screens/trust/identity_api.dart';

class MyBadgeScreen extends StatefulWidget {
  const MyBadgeScreen({super.key});
  @override
  State<MyBadgeScreen> createState() => _MyBadgeScreenState();
}

class _MyBadgeScreenState extends State<MyBadgeScreen> {
  late final IdentityApi _api = IdentityApi(context.read<BaseApi>());
  bool _pdfBusy = false;

  void _toast(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: error ? TtColors.danger : null));
  }

  Future<void> _sharePdf(String code) async {
    setState(() => _pdfBusy = true);
    try {
      final file = await _api.badgePdf(code);
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: 'application/pdf')], subject: 'Mon badge Tratra ID'));
    } catch (e) {
      if (mounted) _toast(friendlyError(e, 'Le badge imprimable n’est pas disponible pour le moment.'), error: true);
    } finally {
      if (mounted) setState(() => _pdfBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isProvider = context.watch<DashboardController>().data?.isProvider ?? false;
    return DashPage(
      title: 'Mon badge Tratra ID',
      body: !isProvider
          ? Center(
              child: TratraEmptyState(
                icon: Icons.badge_outlined,
                title: 'Aucun profil artisan',
                description: 'Le badge Tratra ID est délivré aux artisans : proposez vos services pour l’obtenir.',
                actions: [TratraButton(label: 'Proposer un service', onPressed: () => openProvide(context))],
              ),
            )
          : ApiView<Map<String, dynamic>>(
              errorTitle: 'Badge indisponible',
              load: _api.myId,
              builder: (context, d, reload) {
                final holder = (d['holder'] as Map?)?.cast<String, dynamic>() ?? const {};
                final active = d['valid'] == true;
                final trades = ((holder['trades'] as List?) ?? const []).map((e) => '$e').toList();
                final kyc = DateTime.tryParse('${holder['kyc_verified_on'] ?? ''}')?.toLocal();
                final code = '${d['tratra_id']}';
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(TtSpace.s4, TtSpace.s4, TtSpace.s4, TtSpace.s8),
                  children: [
                    if (!active) ...[
                      TratraAlert(tone: TratraAlertTone.warning, title: 'Badge suspendu', message: '${d['message']}'),
                      const SizedBox(height: TtSpace.s3),
                    ],
                    TratraCard(
                      padding: EdgeInsets.zero,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(TtRadius.card),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Container(
                            color: TtColors.primary,
                            padding: const EdgeInsets.symmetric(horizontal: TtSpace.s4, vertical: TtSpace.s3),
                            child: Row(children: [
                              Text('Tratra', style: TratraTheme.style(TtType.h3, color: Colors.white)),
                              const Spacer(),
                              Text('IDENTITÉ PROFESSIONNELLE', style: TratraTheme.style(TtType.eyebrow, color: Colors.white)),
                            ]),
                          ),
                          Container(height: 5, color: TtColors.accent),
                          Padding(
                            padding: const EdgeInsets.all(TtSpace.s4),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                TratraAvatar(name: '${holder['display_name']}', photoUrl: holder['photo'] as String?, size: 72),
                                const SizedBox(width: TtSpace.s3),
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text('${holder['display_name']}', style: TratraTheme.style(TtType.h2)),
                                    if (trades.isNotEmpty) Text(trades.join(', '), style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft)),
                                    const SizedBox(height: 6),
                                    TratraTrustBadges(trustBadgeCodes(holder['badges'])),
                                  ]),
                                ),
                              ]),
                              const SizedBox(height: TtSpace.s4),
                              Text('TRATRA ID', style: TratraTheme.style(TtType.eyebrow, color: TtColors.ash)),
                              Text(code, style: TratraTheme.style(TtType.h2, color: TtColors.primaryDark)),
                              Text(
                                kyc == null ? 'Identité non vérifiée' : 'Identité vérifiée le ${kyc.day.toString().padLeft(2, '0')}/${kyc.month.toString().padLeft(2, '0')}/${kyc.year}',
                                style: TratraTheme.style(TtType.caption, color: TtColors.ash),
                              ),
                              const SizedBox(height: TtSpace.s4),
                              Center(
                                child: Opacity(
                                  opacity: active ? 1 : 0.35,
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(TtRadius.panel), border: Border.all(color: TtColors.lineSoft)),
                                    child: Image.memory(dataUrlBytes('${d['qr']}'), width: 200, height: 200, filterQuality: FilterQuality.none, semanticLabel: 'QR de vérification Tratra ID $code'),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Center(child: Text(active ? 'Scannez pour vérifier' : 'Badge suspendu', style: TratraTheme.style(TtType.caption, color: TtColors.inkSoft).copyWith(fontWeight: FontWeight.w700))),
                            ]),
                          ),
                        ]),
                      ),
                    ),
                    const SizedBox(height: TtSpace.s3),
                    TratraButton(
                      label: 'Badge imprimable (PDF)',
                      block: true,
                      loading: _pdfBusy,
                      leading: const Icon(Icons.picture_as_pdf_outlined),
                      onPressed: d['pdf_available'] == true ? () => _sharePdf(code) : null,
                    ),
                    if (d['pdf_available'] != true) ...[
                      const SizedBox(height: 4),
                      Text('Le badge imprimable redevient disponible dès que votre identité est vérifiée.', style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
                    ],
                    const SizedBox(height: TtSpace.s2),
                    TratraButton(
                      label: 'Copier le lien de vérification',
                      variant: TratraButtonVariant.outline,
                      block: true,
                      leading: const Icon(Icons.link_rounded),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: '${d['verify_url']}'));
                        if (mounted) _toast('Lien copié.');
                      },
                    ),
                    const SizedBox(height: TtSpace.s3),
                    Text(
                      'Le QR ne contient aucune donnée sensible : il renvoie vers la page de vérification Tratra. À chaque intervention, affichez le QR de mission depuis la page de la mission (temporaire, à usage unique).',
                      style: TratraTheme.style(TtType.caption, color: TtColors.ash),
                    ),
                  ],
                );
              },
            ),
    );
  }
}
