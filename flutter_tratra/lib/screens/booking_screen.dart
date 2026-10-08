// lib/screens/booking/booking_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_tratra/widgets/empty_bookings_widget.dart';
import 'package:provider/provider.dart';
import 'package:flutter_tratra/models/service.dart';
import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/models/booking.dart';
import 'package:flutter_tratra/services/booking_api.dart';
import 'package:flutter_tratra/widgets/animated_button.dart';
import 'package:flutter_tratra/widgets/loading_shimmer.dart';
import 'package:flutter_tratra/widgets/error_retry_widget.dart';
import 'package:flutter_tratra/routes.dart';

class BookingScreen extends StatefulWidget {
  const BookingScreen({super.key})
      : service = null,
        isDirect = false;

  const BookingScreen.withService({super.key, required this.service})
      : isDirect = true;

  final Service? service;
  final bool isDirect;

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  late final BookingApi _bookingApi;
  final _formKey = GlobalKey<FormState>();

  // Form state
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = const TimeOfDay(hour: 9, minute: 0);
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();
  final _postalController = TextEditingController();
  final _notesController = TextEditingController();

  bool _submitting = false;
  bool _loadingList = true;
  String? _listError;
  List<Booking> _bookings = const [];

  @override
  void initState() {
    super.initState();
    final api = context.read<BaseApi>();
    _bookingApi = BookingApi(api);

    if (!widget.isDirect) {
      _fetchMine();
    }
  }

  @override
  void dispose() {
    _addressController.dispose();
    _cityController.dispose();
    _postalController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _fetchMine({bool showLoading = true}) async {
    if (showLoading) {
      setState(() {
        _loadingList = true;
        _listError = null;
      });
    }

    try {
      final mine = await _bookingApi.listMine(pageSize: 100);
      if (!mounted) return;

      setState(() => _bookings = mine);
    } catch (e) {
      if (!mounted) return;
      setState(() => _listError = e.toString());
    } finally {
      if (mounted && showLoading) {
        setState(() => _loadingList = false);
      }
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 60)),
      selectableDayPredicate: (DateTime day) {
        // Exclure les dimanches
        return day.weekday != DateTime.sunday;
      },
    );

    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _selectTime(BuildContext context) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
      builder: (BuildContext context, Widget? child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF00B14F),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && picked != _selectedTime) {
      setState(() => _selectedTime = picked);
    }
  }

  bool get _isFormValid {
    return _addressController.text.trim().isNotEmpty &&
        _cityController.text.trim().isNotEmpty &&
        _postalController.text.trim().isNotEmpty;
  }

  Future<void> _submitBooking() async {
    if (!_isFormValid || _submitting) return;

    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);

    try {
      final s = widget.service!;
      final req = BookingCreateRequest.fromDateAndTime(
        serviceId: s.id,
        handymanId: s.handymanId.isNotEmpty ? s.handymanId : '',
        date: _selectedDate,
        hour: _selectedTime.hour,
        minute: _selectedTime.minute,
        address: _addressController.text.trim(),
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        city: _cityController.text.trim(),
        postalCode: _postalController.text.trim(),
      );

      if (!req.scheduledAt.isAfter(DateTime.now().toUtc())) {
        throw ArgumentError('Veuillez choisir une date et une heure futures.');
      }

      final booking = await _bookingApi.create(req);

      if (!mounted) return;

      final priceToPay = (s.discountedPrice != null &&
              s.discountedPrice! < (s.price ?? double.infinity))
          ? s.discountedPrice!
          : (s.price ?? 0.0);

      await Navigator.pushNamed(
        context,
        RouteNames.payment,
        arguments: PaymentArgs(
          amount: priceToPay,
          serviceName: s.title,
          bookingId: booking.id,
        ),
      );

      // Afficher un message de succès au retour
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Réservation créée avec succès!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Échec de la réservation : ${e.toString()}'),
          backgroundColor: Colors.red,
          action: SnackBarAction(
            label: 'Réessayer',
            textColor: Colors.white,
            onPressed: _submitBooking,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _buildListScreen() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes réservations'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _fetchMine(showLoading: false),
            tooltip: 'Actualiser',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _fetchMine(showLoading: false),
        child: _loadingList
            ? const BookingListShimmer()
            : _listError != null
                ? ErrorRetryWidget(
                    error: _listError!,
                    onRetry: () => _fetchMine(),
                  )
                : _bookings.isEmpty
                    ? const EmptyBookingsWidget()
                    : BookingListView(
                        bookings: _bookings,
                        onRefresh: () => _fetchMine(showLoading: false),
                      ),
      ),
    );
  }

  Widget _buildBookingForm() {
    final s = widget.service!;
    final imageUrl = s.imageUrl.isNotEmpty
        ? s.imageUrl
        : 'https://via.placeholder.com/600x400?text=Service';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Réserver un service'),
        elevation: 0,
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ServiceCard(service: s, imageUrl: imageUrl),
                    const SizedBox(height: 24),

                    // Section Date et Heure
                    _DateTimeSection(
                      selectedDate: _selectedDate,
                      selectedTime: _selectedTime,
                      onDateSelected: () => _selectDate(context),
                      onTimeSelected: () => _selectTime(context),
                    ),
                    const SizedBox(height: 24),

                    // Section Adresse
                    _AddressSection(
                      addressController: _addressController,
                      cityController: _cityController,
                      postalController: _postalController,
                    ),
                    const SizedBox(height: 16),

                    // Section Notes
                    _NotesSection(notesController: _notesController),
                    const SizedBox(height: 80),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _BookingBottomBar(
        isSubmitting: _submitting,
        isFormValid: _isFormValid,
        service: s,
        onSubmit: _submitBooking,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return widget.isDirect ? _buildBookingForm() : _buildListScreen();
  }
}

class BookingListView extends StatelessWidget {
  final List<Booking> bookings;
  final Future<void> Function() onRefresh;

  const BookingListView({
    super.key,
    required this.bookings,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    // Ici, le RefreshIndicator parent gère déjà le pull-to-refresh.
    // On ne met qu'une ListView.
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: bookings.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final b = bookings[index];
        return Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            contentPadding: const EdgeInsets.all(12),
            title: Text(
              'Réservation #${b.id}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                if (b.serviceTitle != null && b.serviceTitle!.isNotEmpty)
                  Text(b.serviceTitle!),
                if (b.status != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Statut : ${b.status}',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ),
                if (b.bookingDate != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Le ${b.bookingDate}',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ),
              ],
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              // TODO: Naviguer vers le détail d'une réservation si tu as un écran dédié.
            },
          ),
        );
      },
    );
  }
}

// Widgets décomposés pour meilleure lisibilité
class _ServiceCard extends StatelessWidget {
  final Service service;
  final String imageUrl;

  const _ServiceCard({required this.service, required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              imageUrl,
              width: 80,
              height: 80,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 80,
                height: 80,
                color: Colors.grey[300],
                child:
                    const Icon(Icons.home_repair_service, color: Colors.grey),
              ),
              loadingBuilder: (_, child, progress) {
                if (progress == null) return child;
                return Container(
                  width: 80,
                  height: 80,
                  color: Colors.grey[300],
                  child: const CircularProgressIndicator(),
                );
              },
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  service.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  service.duration != null
                      ? service.durationDisplay
                      : 'Durée non spécifiée',
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 8),
                Text(
                  (service.discountedPrice != null &&
                          service.price != null &&
                          service.discountedPrice! < service.price!)
                      ? '${service.discountedPrice!.toStringAsFixed(0)} FCFA'
                      : service.price != null
                          ? '${service.price!.toStringAsFixed(0)} FCFA'
                          : service.priceDisplay,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF00B14F),
                  ),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

class _DateTimeSection extends StatelessWidget {
  final DateTime selectedDate;
  final TimeOfDay selectedTime;
  final VoidCallback onDateSelected;
  final VoidCallback onTimeSelected;

  const _DateTimeSection({
    required this.selectedDate,
    required this.selectedTime,
    required this.onDateSelected,
    required this.onTimeSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Date et heure',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _SelectorCard(
                label: 'Date',
                value: '${selectedDate.day.toString().padLeft(2, '0')}/'
                    '${selectedDate.month.toString().padLeft(2, '0')}/'
                    '${selectedDate.year}',
                icon: Icons.calendar_today,
                onTap: onDateSelected,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SelectorCard(
                label: 'Heure',
                value: '${selectedTime.hour.toString().padLeft(2, '0')}:'
                    '${selectedTime.minute.toString().padLeft(2, '0')}',
                icon: Icons.access_time,
                onTap: onTimeSelected,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _AddressSection extends StatelessWidget {
  final TextEditingController addressController;
  final TextEditingController cityController;
  final TextEditingController postalController;

  const _AddressSection({
    required this.addressController,
    required this.cityController,
    required this.postalController,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Adresse',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: addressController,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            hintText: 'Entrez votre adresse complète',
            prefixIcon: Icon(Icons.location_on),
            border: OutlineInputBorder(),
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Veuillez renseigner votre adresse';
            }
            return null;
          },
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: cityController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  hintText: 'Ville',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Veuillez renseigner votre ville';
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: postalController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  hintText: 'Code postal',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Veuillez renseigner votre code postal';
                  }
                  return null;
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _NotesSection extends StatelessWidget {
  final TextEditingController notesController;

  const _NotesSection({required this.notesController});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Notes (optionnel)',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: notesController,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Informations supplémentaires pour l\'artisan...',
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
        ),
      ],
    );
  }
}

class _BookingBottomBar extends StatelessWidget {
  final bool isSubmitting;
  final bool isFormValid;
  final Service service;
  final Future<void> Function() onSubmit;

  const _BookingBottomBar({
    required this.isSubmitting,
    required this.isFormValid,
    required this.service,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final priceToPay = (service.discountedPrice != null &&
            service.discountedPrice! < (service.price ?? double.infinity))
        ? service.discountedPrice!
        : (service.price ?? 0.0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total à payer',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                '${priceToPay.toStringAsFixed(0)} FCFA',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF00B14F),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AnimatedButton(
            onPressed: () async {
              if (isFormValid && !isSubmitting) {
                await onSubmit();
              }
            },
            child: isSubmitting
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  )
                : const Text(
                    'Continuer vers le paiement',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _SelectorCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  const _SelectorCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  value,
                  style: const TextStyle(fontSize: 16),
                ),
                Icon(icon, color: Colors.grey),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
