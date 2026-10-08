// lib/screens/worker/kyc_screen.dart
//
// Vérification KYC artisan : liste des documents + téléversement (galerie/caméra).
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/core/constants.dart';
import 'package:flutter_tratra/services/handyman_service.dart';

class KycScreen extends StatefulWidget {
  const KycScreen({super.key});

  @override
  State<KycScreen> createState() => _KycScreenState();
}

class _KycScreenState extends State<KycScreen> {
  late Future<List<Map<String, dynamic>>> _docs;
  bool _uploading = false;

  static const _types = <String, String>{
    'id_card': 'Carte d\'identité',
    'license': 'Permis de conduire',
    'casier': 'Casier judiciaire',
    'insurance': 'Assurance',
    'certification': 'Certificats / diplômes',
    'other': 'Autre',
  };

  @override
  void initState() {
    super.initState();
    _docs = context.read<HandymanService>().listDocuments();
  }

  Future<void> _reload() async {
    setState(() => _docs = context.read<HandymanService>().listDocuments());
    await _docs;
  }

  Future<void> _startUpload() async {
    final type = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: _types.entries
              .map((e) => ListTile(
                    leading: const Icon(Icons.description_outlined),
                    title: Text(e.value),
                    onTap: () => Navigator.of(context).pop(e.key),
                  ))
              .toList(),
        ),
      ),
    );
    if (type == null) return;

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choisir dans la galerie'),
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Prendre une photo'),
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    final picked = await ImagePicker().pickImage(source: source, imageQuality: 80);
    if (picked == null) return;

    setState(() => _uploading = true);
    try {
      await context.read<HandymanService>().uploadDocument(
            documentType: type,
            filePath: picked.path,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Document envoyé. En attente de revue.'),
          backgroundColor: AppConstants.successColor));
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Échec du téléversement : $e'),
          backgroundColor: AppConstants.dangerColor));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  ({Color color, String label, IconData icon}) _statusVisual(String status) {
    switch (status) {
      case 'approved':
        return (
          color: AppConstants.successColor,
          label: 'Approuvé',
          icon: Icons.verified
        );
      case 'rejected':
        return (
          color: AppConstants.dangerColor,
          label: 'Rejeté',
          icon: Icons.cancel
        );
      default:
        return (
          color: AppConstants.accentDark,
          label: 'En attente',
          icon: Icons.hourglass_top
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vérification (KYC)')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _uploading ? null : _startUpload,
        backgroundColor: AppConstants.primaryColor,
        icon: _uploading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.upload_file),
        label: const Text('Téléverser'),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _docs,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data ?? const [];
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppConstants.primaryLight,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline,
                          color: AppConstants.primaryDark),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Vos documents sont vérifiés avant de pouvoir passer en ligne et recevoir des missions.',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (docs.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Text('Aucun document téléversé.',
                          style:
                              TextStyle(color: AppConstants.textSecondary)),
                    ),
                  )
                else
                  ...docs.map((d) {
                    final v =
                        _statusVisual((d['status'] ?? 'pending').toString());
                    final typeKey = (d['document_type'] ?? '').toString();
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppConstants.borderColor),
                      ),
                      child: ListTile(
                        leading: Icon(v.icon, color: v.color),
                        title: Text(_types[typeKey] ?? typeKey,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: (d['rejection_reason'] ?? '')
                                .toString()
                                .isNotEmpty
                            ? Text('Motif : ${d['rejection_reason']}',
                                style: const TextStyle(
                                    color: AppConstants.dangerColor))
                            : null,
                        trailing: Text(v.label,
                            style: TextStyle(
                                color: v.color,
                                fontWeight: FontWeight.w600,
                                fontSize: 12)),
                      ),
                    );
                  }),
                const SizedBox(height: 80),
              ],
            ),
          );
        },
      ),
    );
  }
}
