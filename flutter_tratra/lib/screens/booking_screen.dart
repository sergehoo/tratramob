// lib/screens/booking_screen.dart
//
// Réservation : tunnel de création (BookingScreen.withService) et liste « Mes réservations »
// (BookingScreen). Écran bâti sur le Design System Tratra (lib/design) ; la logique
// (validation, BookingApi.create / listMine, arguments de navigation) est inchangée.
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/models/booking.dart';
import 'package:flutter_tratra/models/service.dart';
import 'package:flutter_tratra/routes.dart';
import 'package:flutter_tratra/services/booking_api.dart';

import 'booking_flow/booking_format.dart';
import 'booking_flow/booking_widgets.dart';

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

/// Montant transmis au paiement : tarif remisé s'il est inférieur au tarif, sinon le tarif.
double _priceToPay(Service s) {
  return (s.discountedPrice != null &&
          s.discountedPrice! < (s.price ?? double.infinity))
      ? s.discountedPrice!
      : (s.price ?? 0.0);
}

/// Une remise n'est affichée que si les deux tarifs existent et que le remisé est inférieur.
bool _showsDiscount(Service s) {
  return s.discountedPrice != null &&
      s.price != null &&
      s.discountedPrice! < s.price!;
}

/// Le service a-t-il un tarif chiffré ? (sinon : « Sur devis » / « Prix non spécifié »).
bool _hasAmount(Service s) => s.price != null || s.discountedPrice != null;

/// `Service.fromJson` met une image « placeholder » quand l'API n'en fournit pas :
/// on ne l'affiche pas, une icône sobre la remplace.
bool _hasRealImage(String url) =>
    url.isNotEmpty && !url.contains('placeholder');

class _BookingScreenState extends State<BookingScreen> {
  late final BookingApi _bookingApi;
  final _formKey = GlobalKey<FormState>();

  // Form state
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = const TimeOfDay(hour: 9, minute: 0);
  final _addressController = TextEditingController();
  Position? _located; // position de l'appareil (facultative), envoyée avec la réservation
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
      // Une actualisation manuelle doit réellement interroger l'API (le cache de
      // BookingApi dure 5 min) ; le premier chargement garde le comportement normal.
      final mine = await _bookingApi.listMine(
        pageSize: 100,
        forceRefresh: !showLoading,
      );
      if (!mounted) return;

      setState(() => _bookings = mine);
    } catch (e) {
      if (!mounted) return;
      setState(() => _listError = cleanError(e));
    } finally {
      if (mounted && showLoading) {
        setState(() => _loadingList = false);
      }
    }
  }

  /// Sélecteurs Material thémés avec les jetons de la marque.
  Widget _pickerTheme(BuildContext context, Widget child) {
    final base = Theme.of(context);
    return Theme(
      data: base.copyWith(
        datePickerTheme: DatePickerThemeData(
          backgroundColor: TtColors.surface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: TtRadius.cardAll),
        ),
        timePickerTheme: TimePickerThemeData(
          backgroundColor: TtColors.surface,
          shape: RoundedRectangleBorder(borderRadius: TtRadius.cardAll),
          hourMinuteShape:
              RoundedRectangleBorder(borderRadius: TtRadius.controlAll),
          dialHandColor: TtColors.primaryDark,
          dialBackgroundColor: TtColors.primarySoft,
        ),
      ),
      child: child,
    );
  }

  Future<void> _selectDate(BuildContext context) async {
    final now = DateTime.now();
    // Les dimanches sont exclus : l'initialDate du sélecteur doit rester sélectionnable.
    final initial = _selectedDate.weekday == DateTime.sunday
        ? _selectedDate.add(const Duration(days: 1))
        : _selectedDate;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: now,
      lastDate: now.add(const Duration(days: 60)),
      selectableDayPredicate: (DateTime day) {
        // Exclure les dimanches
        return day.weekday != DateTime.sunday;
      },
      helpText: 'Choisir la date',
      cancelText: 'Annuler',
      confirmText: 'Valider',
      builder: (ctx, child) => _pickerTheme(ctx, child!),
    );

    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _selectTime(BuildContext context) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
      helpText: 'Choisir l’heure',
      cancelText: 'Annuler',
      confirmText: 'Valider',
      hourLabelText: 'Heure',
      minuteLabelText: 'Minute',
      builder: (BuildContext ctx, Widget? child) {
        return MediaQuery(
          data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
          child: _pickerTheme(ctx, child!),
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

  /// Date et heure choisies, dans le même référentiel que la requête envoyée (UTC).
  DateTime get _scheduledAt => DateTime.utc(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        _selectedTime.hour,
        _selectedTime.minute,
      );

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded,
                size: 20, color: TtColors.accent),
            const SizedBox(width: TtSpace.s3),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }

  /// Appui sur le bouton principal : si un champ obligatoire manque, on affiche
  /// les messages de validation ; sinon on lance la réservation.
  Future<void> _onSubmitPressed() async {
    if (_submitting) return;
    if (!_isFormValid) {
      _formKey.currentState?.validate();
      return;
    }
    await _submitBooking();
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
        latitude: _located?.latitude,
        longitude: _located?.longitude,
      );

      if (!req.scheduledAt.isAfter(DateTime.now().toUtc())) {
        throw ArgumentError('Veuillez choisir une date et une heure futures.');
      }

      final booking = await _bookingApi.create(req);

      if (!mounted) return;

      final priceToPay = _priceToPay(s);

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
        _showSuccess('Réservation créée avec succès !');
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Échec de la réservation : ${cleanError(e)}'),
          backgroundColor: TtColors.dangerInk,
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
      appBar: TratraAppBar(
        title: 'Mes réservations',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadingList ? null : () => _fetchMine(showLoading: false),
            tooltip: 'Actualiser',
          ),
        ],
      ),
      body: RefreshIndicator(
        color: TtColors.primaryDark,
        onRefresh: () => _fetchMine(showLoading: false),
        child: _loadingList
            ? const SingleChildScrollView(
                physics: AlwaysScrollableScrollPhysics(),
                child: TratraSkeletonList(count: 6),
              )
            : _listError != null
                ? _ScrollableCenter(
                    child: TratraEmptyState(
                      icon: Icons.error_outline_rounded,
                      title: 'Une erreur est survenue',
                      description: _listError,
                      actions: [
                        TratraButton(
                          label: 'Réessayer',
                          leading: const Icon(Icons.refresh_rounded),
                          onPressed: () => _fetchMine(),
                        ),
                      ],
                    ),
                  )
                : _bookings.isEmpty
                    ? _ScrollableCenter(
                        child: TratraEmptyState(
                          icon: Icons.calendar_month_outlined,
                          title: 'Aucune réservation',
                          description: 'Vos réservations apparaîtront ici.',
                          actions: [
                            TratraButton(
                              label: 'Découvrir les services',
                              trailing: const Icon(Icons.arrow_forward_rounded),
                              onPressed: () => Navigator.of(context)
                                  .pushNamed(RouteNames.allServices),
                            ),
                          ],
                        ),
                      )
                    : BookingListView(
                        bookings: _bookings,
                        onRefresh: () => _fetchMine(showLoading: false),
                      ),
      ),
    );
  }

  Widget _buildBookingForm() {
    final s = widget.service!;
    final scheduledAt = _scheduledAt;
    final isPast = !scheduledAt.isAfter(DateTime.now().toUtc());
    // Clavier ouvert : la barre d'action basse libère la place aux champs.
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    return Scaffold(
      appBar: const TratraAppBar(title: 'Réserver un service'),
      body: Form(
        key: _formKey,
        child: BookingContentWidth(
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(
                TtSpace.s4, TtSpace.s4, TtSpace.s4, TtSpace.s8),
            children: [
              const BookingReveal(
                child: _FormIntro(),
              ),
              const SizedBox(height: TtSpace.s4),
              BookingReveal(
                index: 1,
                child: _ServiceCard(service: s),
              ),
              const SizedBox(height: TtSpace.s4),
              BookingReveal(
                index: 2,
                child: _DateTimeSection(
                  selectedDate: _selectedDate,
                  selectedTime: _selectedTime,
                  isPast: isPast,
                  onDateSelected: () => _selectDate(context),
                  onTimeSelected: () => _selectTime(context),
                ),
              ),
              const SizedBox(height: TtSpace.s4),
              BookingReveal(
                index: 3,
                child: _AddressSection(
                  addressController: _addressController,
                  cityController: _cityController,
                  postalController: _postalController,
                  located: _located,
                  onLocated: (p) => setState(() => _located = p),
                ),
              ),
              const SizedBox(height: TtSpace.s4),
              BookingReveal(
                index: 4,
                child: _NotesSection(notesController: _notesController),
              ),
              const SizedBox(height: TtSpace.s4),
              BookingReveal(
                index: 5,
                child: _RecapCard(
                  service: s,
                  scheduledAt: scheduledAt,
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: keyboardOpen
          ? null
          : _BookingBottomBar(
              isSubmitting: _submitting,
              service: s,
              onSubmit: _onSubmitPressed,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return widget.isDirect ? _buildBookingForm() : _buildListScreen();
  }
}

/// Centre un état (vide / erreur) dans une zone défilante : le tirer pour actualiser
/// reste possible.
class _ScrollableCenter extends StatelessWidget {
  const _ScrollableCenter({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(child: child),
        ),
      ),
    );
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
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(TtSpace.s4),
      itemCount: bookings.length,
      separatorBuilder: (_, __) => const SizedBox(height: TtSpace.s3),
      itemBuilder: (context, index) {
        final b = bookings[index];
        return _BookingTile(
          booking: b,
          onTap: () async {
            // Détail d'une réservation : écran de suivi existant.
            await Navigator.pushNamed(
              context,
              RouteNames.tracking,
              arguments: TrackingArgs(b.id),
            );
            // Au retour, l'état a pu changer (annulation…) : on actualise la liste.
            if (context.mounted) await onRefresh();
          },
        );
      },
    );
  }
}

/// Ligne de la liste « Mes réservations » (données réelles uniquement).
class _BookingTile extends StatelessWidget {
  const _BookingTile({required this.booking, required this.onTap});
  final Booking booking;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final b = booking;
    final title = (b.serviceTitle != null && b.serviceTitle!.isNotEmpty)
        ? b.serviceTitle!
        : 'Réservation #${b.id}';
    final when = b.bookingDate == null ? null : formatDateTimeShort(b.bookingDate!);
    final hasAmount = b.amount != null && b.amount! > 0;

    return TratraCard(
      padding: TratraCard.compact,
      onTap: onTap,
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: TtColors.primarySoft,
              borderRadius: TtRadius.panelAll,
            ),
            child: const SizedBox(
              width: TtSpace.s12,
              height: TtSpace.s12,
              child: Icon(Icons.home_repair_service_outlined,
                  color: TtColors.primaryDark),
            ),
          ),
          const SizedBox(width: TtSpace.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TratraTheme.style(TtType.title),
                ),
                const SizedBox(height: TtSpace.s1),
                Text(
                  'Réservation #${b.id}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TratraTheme.style(TtType.caption, color: TtColors.ash),
                ),
                const SizedBox(height: TtSpace.s2),
                TratraStatusBadge(TratraStatus.booking, b.status),
                if (when != null) ...[
                  const SizedBox(height: TtSpace.s2),
                  Row(
                    children: [
                      const Icon(Icons.event_outlined,
                          size: 16, color: TtColors.fog),
                      const SizedBox(width: TtSpace.s1 + 2),
                      Expanded(
                        child: Text(
                          when,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TratraTheme.style(TtType.bodySm,
                              color: TtColors.inkSoft),
                        ),
                      ),
                    ],
                  ),
                ],
                if (hasAmount) ...[
                  const SizedBox(height: TtSpace.s1),
                  Text(
                    formatFcfa(b.amount!),
                    style: TratraTheme.style(TtType.bodySm,
                            color: TtColors.primaryDark)
                        .copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: TtSpace.s2),
          const Icon(Icons.chevron_right_rounded, color: TtColors.fog),
        ],
      ),
    );
  }
}

// Widgets décomposés pour meilleure lisibilité

/// En-tête de la page : sur-titre en pastille + titre + consigne.
class _FormIntro extends StatelessWidget {
  const _FormIntro();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const BookingEyebrow('Réservation'),
        const SizedBox(height: TtSpace.s3),
        Semantics(
          header: true,
          child: Text(
            'Planifiez votre intervention',
            style: TratraTheme.style(TtType.h1),
          ),
        ),
        const SizedBox(height: TtSpace.s2),
        Text(
          'Indiquez la date, l’heure et l’adresse de l’intervention.',
          style: TratraTheme.style(TtType.body, color: TtColors.ash),
        ),
      ],
    );
  }
}

class _ServiceCard extends StatelessWidget {
  final Service service;

  const _ServiceCard({required this.service});

  @override
  Widget build(BuildContext context) {
    final s = service;
    final discounted = _showsDiscount(s);
    final priceText = discounted
        ? formatFcfa(s.discountedPrice!)
        : s.price != null
            ? formatFcfa(s.price!)
            : s.priceDisplay;

    return TratraCard(
      padding: TratraCard.compact,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ServiceImage(url: s.imageUrl),
          const SizedBox(width: TtSpace.s4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (s.categoryName.isNotEmpty) ...[
                  BookingEyebrow(s.categoryName),
                  const SizedBox(height: TtSpace.s2),
                ],
                Text(
                  s.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TratraTheme.style(TtType.h3),
                ),
                const SizedBox(height: TtSpace.s1 + 2),
                Row(
                  children: [
                    const Icon(Icons.schedule_rounded,
                        size: 16, color: TtColors.fog),
                    const SizedBox(width: TtSpace.s1 + 2),
                    Expanded(
                      child: Text(
                        s.hasDuration
                            ? s.durationDisplay
                            : 'Durée non spécifiée',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TratraTheme.style(TtType.bodySm,
                            color: TtColors.ash),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: TtSpace.s2),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.end,
                  spacing: TtSpace.s2,
                  children: [
                    Text(
                      priceText,
                      style: TratraTheme.style(TtType.h3,
                          color: TtColors.primaryDark),
                    ),
                    if (discounted)
                      Text(
                        formatFcfa(s.price!),
                        style: TratraTheme.style(TtType.bodySm,
                                color: TtColors.fog)
                            .copyWith(
                          decoration: TextDecoration.lineThrough,
                          decorationColor: TtColors.fog,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Photo réelle du service ; sinon (ou si elle ne charge pas) une icône sobre.
class _ServiceImage extends StatelessWidget {
  const _ServiceImage({required this.url});
  final String url;

  static const double _size = 88;

  Widget _fallback() => DecoratedBox(
        decoration: BoxDecoration(
          color: TtColors.primarySoft,
          borderRadius: TtRadius.panelAll,
        ),
        child: const SizedBox(
          width: _size,
          height: _size,
          child: Icon(Icons.home_repair_service_outlined,
              size: 32, color: TtColors.primaryDark),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (!_hasRealImage(url)) return ExcludeSemantics(child: _fallback());
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: TtRadius.panelAll,
        child: Image.network(
          url,
          width: _size,
          height: _size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _fallback(),
          loadingBuilder: (_, child, progress) {
            if (progress == null) return child;
            return const TratraSkeleton(
              width: _size,
              height: _size,
              radius: TtRadius.panel,
            );
          },
        ),
      ),
    );
  }
}

class _DateTimeSection extends StatelessWidget {
  final DateTime selectedDate;
  final TimeOfDay selectedTime;
  final bool isPast;
  final VoidCallback onDateSelected;
  final VoidCallback onTimeSelected;

  const _DateTimeSection({
    required this.selectedDate,
    required this.selectedTime,
    required this.isPast,
    required this.onDateSelected,
    required this.onTimeSelected,
  });

  @override
  Widget build(BuildContext context) {
    return BookingStepCard(
      step: 1,
      title: 'Date et heure',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _SelectorCard(
                  label: 'Date',
                  value: formatDateNumeric(selectedDate),
                  icon: Icons.calendar_today_outlined,
                  onTap: onDateSelected,
                ),
              ),
              const SizedBox(width: TtSpace.s3),
              Expanded(
                child: _SelectorCard(
                  label: 'Heure',
                  value: formatTime(selectedTime.hour, selectedTime.minute),
                  icon: Icons.schedule_rounded,
                  onTap: onTimeSelected,
                ),
              ),
            ],
          ),
          const SizedBox(height: TtSpace.s3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(Icons.info_outline_rounded,
                    size: 16, color: TtColors.fog),
              ),
              const SizedBox(width: TtSpace.s2),
              Expanded(
                child: Text(
                  'Les dimanches ne sont pas disponibles.',
                  style: TratraTheme.style(TtType.caption,
                      color: TtColors.ash),
                ),
              ),
            ],
          ),
          if (isPast) ...[
            const SizedBox(height: TtSpace.s3),
            const TratraAlert(
              tone: TratraAlertTone.warning,
              message: 'Veuillez choisir une date et une heure futures.',
            ),
          ],
        ],
      ),
    );
  }
}

class _AddressSection extends StatelessWidget {
  final TextEditingController addressController;
  final TextEditingController cityController;
  final TextEditingController postalController;
  final Position? located;
  final ValueChanged<Position> onLocated;

  const _AddressSection({
    required this.addressController,
    required this.cityController,
    required this.postalController,
    required this.located,
    required this.onLocated,
  });

  Future<void> _locate(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) throw StateError('désactivée');
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) throw StateError('refusée');
      onLocated(await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15))));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Position introuvable ou refusée : vous pouvez réserver sans elle.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return BookingStepCard(
      step: 2,
      title: 'Adresse',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TratraInput(
            controller: addressController,
            label: 'Adresse complète',
            hint: 'Entrez votre adresse complète',
            leadingIcon: Icons.location_on_outlined,
            required: true,
            textInputAction: TextInputAction.next,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Veuillez renseigner votre adresse';
              }
              return null;
            },
          ),
          const SizedBox(height: TtSpace.s4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TratraInput(
                  controller: cityController,
                  label: 'Ville',
                  required: true,
                  textInputAction: TextInputAction.next,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Veuillez renseigner votre ville';
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(width: TtSpace.s3),
              Expanded(
                child: TratraInput(
                  controller: postalController,
                  label: 'Code postal',
                  required: true,
                  textInputAction: TextInputAction.next,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
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
          const SizedBox(height: TtSpace.s3),
          TratraButton(
            label: located == null ? 'Localiser le lieu avec ma position' : 'Mettre à jour ma position',
            variant: TratraButtonVariant.outline,
            size: TratraButtonSize.sm,
            leading: const Icon(Icons.my_location_rounded, size: 18),
            onPressed: () => _locate(context),
          ),
          const SizedBox(height: 4),
          Text(
            located != null
                ? 'Lieu localisé (±${located!.accuracy.round()} m) : l’heure d’arrivée de l’artisan sera calculée.'
                : 'Facultatif : permet d’afficher l’heure d’arrivée estimée de l’artisan. À utiliser seulement sur place.',
            style: TratraTheme.style(TtType.caption, color: located != null ? TtColors.successInk : TtColors.ash),
          ),
        ],
      ),
    );
  }
}

class _NotesSection extends StatelessWidget {
  final TextEditingController notesController;

  const _NotesSection({required this.notesController});

  @override
  Widget build(BuildContext context) {
    return BookingStepCard(
      step: 3,
      title: 'Notes (optionnel)',
      child: TratraInput(
        controller: notesController,
        maxLines: 3,
        hint: 'Informations supplémentaires pour l’artisan…',
      ),
    );
  }
}

/// Récapitulatif : uniquement des données réelles (service, créneau choisi, tarifs du service).
class _RecapCard extends StatelessWidget {
  const _RecapCard({required this.service, required this.scheduledAt});
  final Service service;
  final DateTime scheduledAt;

  @override
  Widget build(BuildContext context) {
    final s = service;
    final discounted = _showsDiscount(s);

    return BookingStepCard(
      icon: Icons.receipt_long_outlined,
      title: 'Récapitulatif',
      child: Column(
        children: [
          BookingInfoRow(label: 'Service', value: s.title),
          const SizedBox(height: TtSpace.s3),
          BookingInfoRow(
            label: 'Date et heure',
            value: formatDateTimeLong(scheduledAt),
          ),
          if (_hasAmount(s)) ...[
            if (discounted) ...[
              const SizedBox(height: TtSpace.s3),
              BookingInfoRow(
                label: 'Tarif',
                value: formatFcfa(s.price!),
                strike: true,
              ),
              const SizedBox(height: TtSpace.s3),
              BookingInfoRow(
                label: 'Remise',
                value: '−${formatFcfa(s.price! - s.discountedPrice!)}',
                valueColor: TtColors.successInk,
              ),
            ],
            const Padding(
              padding: EdgeInsets.symmetric(vertical: TtSpace.s4),
              child: Divider(),
            ),
            BookingInfoRow(
              label: 'Total à payer',
              value: formatFcfa(_priceToPay(s)),
              strong: true,
            ),
          ] else ...[
            const SizedBox(height: TtSpace.s3),
            BookingInfoRow(label: 'Tarif', value: s.priceDisplay),
          ],
        ],
      ),
    );
  }
}

class _BookingBottomBar extends StatelessWidget {
  final bool isSubmitting;
  final Service service;
  final Future<void> Function() onSubmit;

  const _BookingBottomBar({
    required this.isSubmitting,
    required this.service,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final hasAmount = _hasAmount(service);

    return BookingStickyBar(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                hasAmount ? 'Total à payer' : 'Tarif',
                style: TratraTheme.style(TtType.title),
              ),
              const SizedBox(width: TtSpace.s3),
              Flexible(
                child: Text(
                  hasAmount
                      ? formatFcfa(_priceToPay(service))
                      : service.priceDisplay,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TratraTheme.style(TtType.h3,
                      color: TtColors.primaryDark),
                ),
              ),
            ],
          ),
          const SizedBox(height: TtSpace.s3),
          TratraButton(
            label: 'Confirmer la réservation',
            size: TratraButtonSize.lg,
            block: true,
            loading: isSubmitting,
            trailing: const Icon(Icons.arrow_forward_rounded),
            onPressed: () => onSubmit(),
          ),
        ],
      ),
    );
  }
}

/// Champ de sélection (date / heure) au style des champs de saisie du Design System.
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
          style: TratraTheme.style(TtType.bodySm)
              .copyWith(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        const SizedBox(height: TtSpace.s1 + 2),
        Semantics(
          button: true,
          label: '$label : $value. Modifier',
          excludeSemantics: true,
          child: Material(
            color: TtColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: TtRadius.controlAll,
              side: const BorderSide(color: TtColors.line),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(minHeight: TtLayout.controlHeight + 4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: TtSpace.s3, vertical: TtSpace.s3),
                  child: Row(
                    children: [
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            value,
                            maxLines: 1,
                            style: TratraTheme.style(TtType.body)
                                .copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      const SizedBox(width: TtSpace.s2),
                      Icon(icon, size: 18, color: TtColors.primaryDark),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
