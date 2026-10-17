import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_localizations.dart';
import '../../models/models.dart';
import '../../models/sla.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

const complaintCategories = ['Plumbing', 'Electrical', 'Lift', 'Water supply', 'Security', 'Cleaning', 'STP', 'Community', 'Gym', 'Other'];

class RaiseComplaintScreen extends ConsumerStatefulWidget {
  const RaiseComplaintScreen({super.key});

  @override
  ConsumerState<RaiseComplaintScreen> createState() => _RaiseComplaintScreenState();
}

class _RaiseComplaintScreenState extends ConsumerState<RaiseComplaintScreen> {
  final _title = TextEditingController();
  final _desc = TextEditingController();
  TicketType _type = TicketType.maintenance;
  String? _category;
  bool _commonArea = false;
  bool _private = false;
  int _photos = 0;
  bool _voice = false;
  bool _recording = false;
  Criticality? _override;

  AiSuggestion? get _ai => suggestCriticality('${_title.text} ${_desc.text}');

  void _submit() {
    final s = ref.read(sessionProvider)!;
    if (_title.text.trim().isEmpty) {
      toast(context, 'Please add a short title');
      return;
    }
    final ai = _ai;
    final notifier = ref.read(complaintsProvider.notifier);
    final id = notifier.nextId();
    notifier.add(Complaint(
      id: id,
      flatNumber: _commonArea ? 'Common' : (s.user.flatNumber ?? 'Common'),
      type: _type,
      category: _category ?? ai?.category ?? 'Other',
      title: _title.text.trim(),
      description: _desc.text.trim(),
      criticality: _override ?? ai?.criticality ?? Criticality.medium,
      aiSuggested: _override == null && ai != null,
      status: TicketStatus.newTicket,
      createdAt: DateTime.now(),
      raisedBy: s.user.name,
      photoCount: _photos,
      hasVoiceNote: _voice,
      isPrivate: _private,
      location: _commonArea ? 'Common area' : 'Inside flat',
    ));
    toast(context, 'Ticket $id created. Caretaker and committee notified.');
    context.go('/complaints/$id');
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final ai = _ai;
    return Scaffold(
      appBar: AppBar(title: Text(l.raiseComplaint)),
      body: PageBody(maxWidth: 720, children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SegmentedButton<TicketType>(
                segments: const [
                  ButtonSegment(value: TicketType.maintenance, label: Text('Maintenance request'), icon: Icon(Icons.build_outlined)),
                  ButtonSegment(value: TicketType.complaint, label: Text('Complaint'), icon: Icon(Icons.report_outlined)),
                ],
                selected: {_type},
                onSelectionChanged: (v) => setState(() => _type = v.first),
              ),
              const SizedBox(height: 16),
              TextField(controller: _title, decoration: const InputDecoration(labelText: 'Short title *'), onChanged: (_) => setState(() {})),
              const SizedBox(height: 12),
              TextField(controller: _desc, maxLines: 4, decoration: const InputDecoration(labelText: 'Details', alignLabelWithHint: true), onChanged: (_) => setState(() {})),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: InputDecoration(labelText: 'Category', helperText: ai != null && _category == null ? 'AI suggests: ${ai.category}' : null),
                items: [for (final c in complaintCategories) DropdownMenuItem(value: c, child: Text(c))],
                onChanged: (v) => setState(() => _category = v),
              ),
              const SizedBox(height: 8),
              SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('This is in a common area'), value: _commonArea, onChanged: (v) => setState(() => _commonArea = v)),
              SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Private (only committee and caretaker can see)'), value: _private, onChanged: (v) => setState(() => _private = v)),
              const Divider(),
              Wrap(spacing: 8, runSpacing: 8, children: [
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
                  icon: Icon(_recording ? Icons.stop_circle : Icons.mic_none, color: _recording ? Colors.red : null),
                  label: Text(_recording ? 'Stop recording' : (_voice ? 'Voice note added ✓' : l.recordVoice)),
                ),
              ]),
              const SizedBox(height: 16),
              if (ai != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(12)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const Icon(Icons.auto_awesome, size: 18),
                      const SizedBox(width: 8),
                      const Text('AI suggested criticality: ', style: TextStyle(fontWeight: FontWeight.w600)),
                      CriticalityPill(ai.criticality),
                    ]),
                    const SizedBox(height: 4),
                    Text('Reason: ${ai.reason}. The caretaker or Secretary can change this.', style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 8),
                    Wrap(spacing: 6, children: [
                      const Text('Override: '),
                      for (final c in Criticality.values)
                        ChoiceChip(label: Text(c.label), selected: _override == c, onSelected: (v) => setState(() => _override = v ? c : null)),
                    ]),
                  ]),
                ),
              const SizedBox(height: 16),
              FilledButton(onPressed: _submit, child: Padding(padding: const EdgeInsets.all(12), child: Text(l.submit))),
            ]),
          ),
        ),
      ]),
    );
  }
}
