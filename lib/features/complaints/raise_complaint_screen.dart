import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart' hide Text, TextField, DropdownButtonFormField;

import '../../widgets/tr_text.dart';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../backend/upload_preparation.dart' show maxOriginalImageBytes;
import '../../l10n/app_localizations.dart';
import '../../models/models.dart';
import '../../models/sla.dart';
import '../../models/vendor.dart';
import '../../backend/backend.dart' show backendEnabled;
import '../../backend/voice_recorder.dart';
import '../../backend/complaints_repo.dart' show VoiceFormat, wavVoiceFormat;
import '../../backend/vendors_repo.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

final complaintVendorsProvider = FutureProvider.autoDispose<List<AssociationVendor>>((ref) async {
  if (!backendEnabled) return const [];
  return VendorsRepo.list();
});

const complaintCategories = [
  'Plumbing',
  'Electrical',
  'Lift',
  'Water supply',
  'Security',
  'Cleaning',
  'STP',
  'Community',
  'Gym',
  'Other',
];

class RaiseComplaintScreen extends ConsumerStatefulWidget {
  const RaiseComplaintScreen({super.key});

  @override
  ConsumerState<RaiseComplaintScreen> createState() => _RaiseComplaintScreenState();
}

class _RaiseComplaintScreenState extends ConsumerState<RaiseComplaintScreen> {
  final _title = TextEditingController();
  final _desc = TextEditingController();
  TicketType _type = TicketType.maintenance;
  ReportKind _kind = ReportKind.complaint;
  final _cost = TextEditingController();
  String? _category;
  bool? _commonAreaChoice;
  String? _flat;
  bool _private = false;
  final List<Uint8List> _photos = [];
  Uint8List? _voiceNote;
  VoiceFormat _voiceFormat = wavVoiceFormat;
  bool _recording = false;
  bool _recordingBusy = false;
  bool _submitting = false;
  final _imagePicker = ImagePicker();
  final _recorder = VoiceRecorder();
  Criticality? _override;
  String? _vendorId;

  AiSuggestion? get _ai => suggestCriticality('${_title.text} ${_desc.text}');

  /// EC members and the caretaker report common-area issues (spec 7.5).
  bool get _staff {
    final r = ref.read(sessionProvider)!.activeRole;
    return r.isCommittee || r == Role.caretaker;
  }

  bool get _commonArea => _commonAreaChoice ?? _staff;

  @override
  void dispose() {
    unawaited(_recorder.dispose());
    _title.dispose();
    _desc.dispose();
    _cost.dispose();
    super.dispose();
  }

  Future<void> _addPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from photos'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    try {
      final file = await _imagePicker.pickImage(source: source);
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      if (bytes.length > maxOriginalImageBytes) {
        toast(context, 'Photo must be 30 MB or smaller');
        return;
      }
      setState(() => _photos.add(bytes));
    } catch (error) {
      if (mounted) toast(context, '$error');
    }
  }

  Future<void> _toggleVoiceRecording() async {
    if (_recording) {
      await _stopVoiceRecording();
      return;
    }
    try {
      if (!await _recorder.hasPermission()) {
        if (mounted) toast(context, 'Microphone permission is required to record a voice note');
        return;
      }
      await _recorder.start(
        onAutoStop: () => unawaited(_stopVoiceRecording()),
        onError: (Object error) {
          if (mounted) {
            toast(context, 'Recording failed: $error');
            unawaited(_stopVoiceRecording());
          }
        },
      );
      if (mounted) setState(() => _recording = true);
    } catch (error) {
      if (mounted) toast(context, 'Could not start recording: $error');
    }
  }

  Future<void> _stopVoiceRecording() async {
    if (!_recording || _recordingBusy) return;
    setState(() => _recordingBusy = true);
    try {
      final result = await _recorder.stop();
      if (mounted) {
        setState(() {
          _recording = false;
          _voiceNote = result.bytes;
          _voiceFormat = result.format;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _recording = false);
        toast(context, '$error');
      }
    } finally {
      if (mounted) setState(() => _recordingBusy = false);
    }
  }

  Future<void> _submit() async {
    if (_recording || _recordingBusy) {
      toast(context, 'Stop the voice recording before submitting');
      return;
    }
    final s = ref.read(sessionProvider)!;
    if (_title.text.trim().isEmpty) {
      toast(context, 'Please add a short title');
      return;
    }
    if (_title.text.trim().length > 160 || _desc.text.trim().length > 4000) {
      toast(context, 'Title must be 160 characters and details 4,000 characters or fewer');
      return;
    }
    if (_kind.isEnhancement && _cost.text.trim().isNotEmpty && (int.tryParse(_cost.text.trim()) ?? 0) <= 0) {
      toast(context, 'Estimated cost must be a positive whole number');
      return;
    }
    final ai = _ai;
    final notifier = ref.read(complaintsProvider.notifier);
    final id = notifier.nextId();
    final crit = _override ?? ai?.criticality ?? Criticality.medium;
    final now = DateTime.now();
    final role = s.activeRole;
    final vendorState = ref.read(complaintVendorsProvider);
    final selectedVendor = vendorState.hasValue
        ? vendorState.value!.where((vendor) => vendor.id == _vendorId).firstOrNull
        : null;
    final needsReview = _staff && _commonArea && role != Role.secretary;
    final bypass = needsReview && _kind == ReportKind.complaint && crit == Criticality.critical;
    final status = !needsReview || bypass ? TicketStatus.newTicket : TicketStatus.pendingReview;
    final complaint = Complaint(
      id: id,
      flatNumber: _commonArea ? 'Common' : (_flat ?? _myFlats(s).firstOrNull ?? s.user.flatNumber ?? 'Common'),
      type: _type,
      category: _category ?? ai?.category ?? 'Other',
      title: _title.text.trim(),
      description: _desc.text.trim(),
      criticality: crit,
      aiSuggested: _override == null && ai != null,
      status: status,
      createdAt: now,
      kind: _kind,
      acceptedAt: status == TicketStatus.newTicket ? now : null,
      estimatedCost: int.tryParse(_cost.text.replaceAll(RegExp(r'[^0-9]'), '')),
      remarks: bypass
          ? [
              TicketRemark(
                by: 'System',
                at: now,
                text: 'Critical – skipped review and sent straight to the caretaker. Secretary notified.',
              ),
            ]
          : const [],
      raisedBy: s.user.name,
      photoCount: _photos.length,
      hasVoiceNote: _voiceNote != null,
      isPrivate: _private,
      location: _commonArea ? 'Common area' : 'Inside flat',
      vendorId: _vendorId,
      vendorName: selectedVendor?.name,
    );
    setState(() => _submitting = true);
    try {
      await notifier.add(complaint, photos: _photos, voiceNote: _voiceNote, voiceFormat: _voiceFormat);
    } catch (error) {
      if (mounted) toast(context, '$error');
      return;
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
    if (!mounted) return;
    toast(
      context,
      status == TicketStatus.pendingReview
          ? '$id sent to the Secretary for review.'
          : 'Ticket $id created. Caretaker and committee notified.',
    );
    context.go('/complaints/$id');
  }

  /// Owner/resident flats in the open association; an owner may have several.
  List<String> _myFlats(dynamic s) => <String>{
    ...(s.user.flatsFor(Role.owner) as List<String>),
    ...(s.user.flatsFor(Role.resident) as List<String>),
  }.toList();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final ai = _ai;
    final role = ref.watch(sessionProvider)!.activeRole;
    final vendorOptions = role.isOfficeBearer ? ref.watch(complaintVendorsProvider.select((value) => value)) : null;
    return Scaffold(
      appBar: AppBar(title: Text(l.raiseComplaint)),
      body: PageBody(
        maxWidth: 720,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_staff) ...[
                    Text('What are you reporting?', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    SegmentedButton<ReportKind>(
                      segments: const [
                        ButtonSegment(
                          value: ReportKind.complaint,
                          label: Text('Complaint'),
                          icon: Icon(Icons.report_outlined),
                        ),
                        ButtonSegment(
                          value: ReportKind.enhancementImmediate,
                          label: Text('Enhancement – now'),
                          icon: Icon(Icons.bolt),
                        ),
                        ButtonSegment(
                          value: ReportKind.enhancementFuture,
                          label: Text('Enhancement – later'),
                          icon: Icon(Icons.event_note_outlined),
                        ),
                      ],
                      selected: {_kind},
                      onSelectionChanged: (v) => setState(() => _kind = v.first),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (!_kind.isEnhancement)
                    SegmentedButton<TicketType>(
                      segments: const [
                        ButtonSegment(
                          value: TicketType.maintenance,
                          label: Text('Maintenance request'),
                          icon: Icon(Icons.build_outlined),
                        ),
                        ButtonSegment(
                          value: TicketType.complaint,
                          label: Text('Complaint'),
                          icon: Icon(Icons.report_outlined),
                        ),
                      ],
                      selected: {_type},
                      onSelectionChanged: (v) => setState(() => _type = v.first),
                    ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _title,
                    maxLength: 160,
                    decoration: const InputDecoration(labelText: 'Short title *'),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _desc,
                    maxLines: 4,
                    maxLength: 4000,
                    decoration: const InputDecoration(labelText: 'Details', alignLabelWithHint: true),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _category,
                    decoration: InputDecoration(
                      labelText: 'Category',
                      helperText: ai != null && _category == null ? 'AI suggests: ${ai.category}' : null,
                    ),
                    items: [for (final c in complaintCategories) DropdownMenuItem(value: c, child: Text(c))],
                    onChanged: (v) => setState(() => _category = v),
                  ),
                  if (role.isOfficeBearer) ...[
                    const SizedBox(height: 10),
                    vendorOptions!.when(
                      data: (vendors) => DropdownButtonFormField<String?>(
                        initialValue: _vendorId,
                        decoration: const InputDecoration(labelText: 'Assigned vendor (optional)'),
                        items: [
                          const DropdownMenuItem<String?>(value: null, child: Text('No vendor')),
                          for (final vendor in vendors.where((vendor) => vendor.active))
                            DropdownMenuItem<String?>(value: vendor.id, child: Text(vendor.name)),
                        ],
                        onChanged: (value) => setState(() => _vendorId = value),
                      ),
                      loading: () => const LinearProgressIndicator(),
                      error: (_, _) => const Text('Vendor list is unavailable'),
                    ),
                  ],
                  const SizedBox(height: 8),
                  if (_staff)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Common area'),
                      subtitle: Text(
                        _commonArea && ref.read(sessionProvider)!.activeRole != Role.secretary
                            ? 'Goes to the Secretary for review first (critical complaints skip review)'
                            : 'Inside my flat',
                      ),
                      value: _commonArea,
                      onChanged: (v) => setState(() => _commonAreaChoice = v),
                    ),
                  if (!_commonArea && _myFlats(ref.read(sessionProvider)!).length > 1) ...[
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: _flat ?? _myFlats(ref.read(sessionProvider)!).first,
                      decoration: const InputDecoration(labelText: 'Which flat?'),
                      items: [
                        for (final f in _myFlats(ref.read(sessionProvider)!))
                          DropdownMenuItem(value: f, child: Text('Flat $f')),
                      ],
                      onChanged: (v) => setState(() => _flat = v),
                    ),
                  ],
                  if (_kind.isEnhancement) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: _cost,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(9)],
                      decoration: const InputDecoration(labelText: 'Estimated cost (optional)', prefixText: '₹ '),
                    ),
                    const SizedBox(height: 8),
                  ],
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Private (only committee and caretaker can see)'),
                    value: _private,
                    onChanged: (v) => setState(() => _private = v),
                  ),
                  const Divider(),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _photos.length >= 5 ? null : _addPhoto,
                        icon: const Icon(Icons.photo_camera_outlined),
                        label: Text(_photos.isEmpty ? 'Add photo' : 'Photos: ${_photos.length} / 5'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _recordingBusy ? null : _toggleVoiceRecording,
                        icon: Icon(
                          _recording ? Icons.stop_circle : Icons.mic_none,
                          color: _recording ? Colors.red : null,
                        ),
                        label: Text(
                          _recording
                              ? 'Stop recording'
                              : (_voiceNote != null ? 'Voice note recorded ✓' : l.recordVoice),
                        ),
                      ),
                      if (_voiceNote != null)
                        TextButton.icon(
                          onPressed: () => setState(() => _voiceNote = null),
                          icon: const Icon(Icons.delete_outline),
                          label: Text('${(_voiceNote!.length / 1024).ceil()} KB · Remove voice note'),
                        ),
                    ],
                  ),
                  if (_photos.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (var i = 0; i < _photos.length; i++)
                          Stack(
                            alignment: Alignment.topRight,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.memory(_photos[i], width: 76, height: 64, fit: BoxFit.cover),
                              ),
                              IconButton.filledTonal(
                                visualDensity: VisualDensity.compact,
                                onPressed: () => setState(() => _photos.removeAt(i)),
                                icon: const Icon(Icons.close, size: 16),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (ai != null && !_kind.isEnhancement)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.auto_awesome, size: 18),
                              const SizedBox(width: 8),
                              const Text('AI suggested criticality: ', style: TextStyle(fontWeight: FontWeight.w600)),
                              CriticalityPill(ai.criticality),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Reason: ${ai.reason}. The caretaker or Secretary can change this.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            children: [
                              const Text('Override: '),
                              for (final c in Criticality.values)
                                ChoiceChip(
                                  label: Text(c.label),
                                  selected: _override == c,
                                  onSelected: (v) => setState(() => _override = v ? c : null),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _submitting ? null : _submit,
                    child: Padding(padding: const EdgeInsets.all(12), child: Text(l.submit)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
