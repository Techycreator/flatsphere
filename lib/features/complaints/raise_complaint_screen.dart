import 'package:flutter/material.dart' hide Text, TextField, DropdownButtonFormField;
import '../../widgets/tr_text.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_localizations.dart';
import '../../models/models.dart';
import '../../models/sla.dart';
import '../../models/vendor.dart';
import '../../backend/backend.dart' show backendEnabled;
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
  bool _private = false;
  int _photos = 0;
  bool _voice = false;
  bool _recording = false;
  Criticality? _override;
  String? _vendorId;

  AiSuggestion? get _ai => suggestCriticality('${_title.text} ${_desc.text}');

  /// EC members and the caretaker report common-area issues (spec 7.5).
  bool get _staff {
    final r = ref.read(sessionProvider)!.activeRole;
    return r.isCommittee || r == Role.caretaker;
  }

  bool get _commonArea => _commonAreaChoice ?? _staff;

  void _submit() {
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
    final selectedVendor = vendorState.hasValue ? vendorState.value!.where((vendor) => vendor.id == _vendorId).firstOrNull : null;
    final needsReview = _staff && _commonArea && role != Role.secretary;
    final bypass = needsReview && _kind == ReportKind.complaint && crit == Criticality.critical;
    final status = !needsReview || bypass ? TicketStatus.newTicket : TicketStatus.pendingReview;
    notifier.add(
      Complaint(
        id: id,
        flatNumber: _commonArea ? 'Common' : (s.user.flatNumber ?? 'Common'),
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
        photoCount: _photos,
        hasVoiceNote: _voice,
        isPrivate: _private,
        location: _commonArea ? 'Common area' : 'Inside flat',
        vendorId: _vendorId,
        vendorName: selectedVendor?.name,
      ),
    );
    toast(
      context,
      status == TicketStatus.pendingReview
          ? '$id sent to the Secretary for review.'
          : 'Ticket $id created. Caretaker and committee notified.',
    );
    context.go('/complaints/$id');
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final ai = _ai;
    final role = ref.watch(sessionProvider)!.activeRole;
    final vendorOptions = role.isOfficeBearer
        ? ref.watch(complaintVendorsProvider.select((value) => value))
        : null;
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
                        onPressed: _photos >= 5 ? null : () => setState(() => _photos++),
                        icon: const Icon(Icons.photo_camera_outlined),
                        label: Text(_photos == 0 ? 'Add photo' : 'Photos: $_photos / 5'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => setState(() {
                          if (_recording) {
                            _recording = false;
                            _voice = true;
                          } else {
                            _recording = true;
                          }
                        }),
                        icon: Icon(
                          _recording ? Icons.stop_circle : Icons.mic_none,
                          color: _recording ? Colors.red : null,
                        ),
                        label: Text(_recording ? 'Stop recording' : (_voice ? 'Voice note added ✓' : l.recordVoice)),
                      ),
                    ],
                  ),
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
                    onPressed: _submit,
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
