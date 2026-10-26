import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide Text;
import '../../widgets/tr_text.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../../backend/attendance_repo.dart';
import '../../backend/upload_preparation.dart' show maxSourceUploadBytes;
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../state/staff_attendance_state.dart';
import '../../widgets/common.dart';

class StaffAttendanceScreen extends ConsumerWidget {
  const StaffAttendanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider)!;
    final role = session.activeRole;
    final state = ref.watch(staffAttendanceProvider);
    final notifier = ref.read(staffAttendanceProvider.notifier);
    final canManageStaff = role == Role.admin || role == Role.president || role == Role.secretary;
    final canEditStaff = role == Role.president || role == Role.secretary;
    final canViewSalary = canManageStaff || role == Role.vicePresident || role == Role.jointSecretary;
    final canMark = role == Role.caretaker;
    final canReview = canManageStaff ||
      role == Role.president ||
        role == Role.vicePresident ||
        role == Role.secretary ||
        role == Role.jointSecretary ||
        role == Role.monitor;

    Future<void> selectDate() async {
      final date = await showDatePicker(
        context: context,
        initialDate: state.date,
        firstDate: DateTime(2020),
        lastDate: DateUtils.dateOnly(DateTime.now()),
      );
      if (date != null) await notifier.refresh(date);
    }

    Future<void> addStaff() async {
      final draft = await _addStaffDialog(context);
      if (draft == null || !context.mounted) return;
      try {
        final proofBytes = await draft.proof.readAsBytes();
        await notifier.addStaff(
          name: draft.name,
          type: draft.type,
          area: draft.area,
          employerType: draft.employerType,
          agencyName: draft.agencyName,
          monthlySalary: draft.monthlySalary,
          proofBytes: proofBytes,
          proofExtension: draft.proof.extension ?? '',
        );
        if (context.mounted) toast(context, '${draft.name} added to staff register');
      } catch (error) {
        if (context.mounted) toast(context, '$error');
      }
    }

    Future<void> editStaff(StaffMember staff) async {
      final draft = await _editStaffDialog(context, staff);
      if (draft == null || !context.mounted) return;
      if (staff.active && !draft.active) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text('Archive ${staff.name}?'),
            content: const Text('Attendance history will be retained, and this staff member can be reactivated later.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Archive staff')),
            ],
          ),
        );
        if (confirmed != true || !context.mounted) return;
      }
      try {
        await notifier.updateStaff(
          staff: staff,
          name: draft.name,
          type: draft.type,
          area: draft.area,
          employerType: draft.employerType,
          agencyName: draft.agencyName,
          monthlySalary: draft.monthlySalary,
          active: draft.active,
        );
        if (context.mounted) toast(context, draft.active ? '${draft.name} updated' : '${draft.name} moved to staff archive');
      } catch (error) {
        if (context.mounted) toast(context, '$error');
      }
    }

    Future<void> mark(StaffMember staff, AttendanceStatus status) async {
      var note = '';
      if (status != AttendanceStatus.present) {
        note = await promptText(
              context,
              title: '${status.label}: ${staff.name}',
              hint: 'Optional note',
              required: false,
            ) ??
            '';
      }
      if (!context.mounted) return;
      try {
        await notifier.mark(staff, status, note: note);
      } catch (error) {
        if (context.mounted) toast(context, '$error');
      }
    }

    final activeStaff = state.staff.where((staff) => staff.active).toList();
    final registerStaff = canEditStaff ? state.staff : activeStaff;
    String attendanceSubtitle(StaffMember staff) {
      final record = state.records[staff.id];
      if (record == null) return '${staff.area}\nNot marked';
      return '${staff.area}\n${record.status.label} · marked by ${record.markedBy}'
          '${record.note.isEmpty ? '' : ' · ${record.note}'}';
    }
    final approvedExpenses = ref.watch(expensesProvider).where((expense) => expense.status == ExpenseStatus.approved).toList();
    final now = DateTime.now();
    String salaryCheck(StaffMember staff) {
      final matched = approvedExpenses.where((expense) {
        if (expense.category.toLowerCase() != 'staff salary' || expense.date.year != now.year || expense.date.month != now.month) {
          return false;
        }
        final text = '${expense.vendor} ${expense.description}'.toLowerCase();
        return text.contains(staff.name.toLowerCase());
      }).fold(0, (sum, expense) => sum + expense.amount);
      if (matched == 0) return 'No matching approved salary expense this month';
      return matched == staff.monthlySalary
          ? 'Salary matches approved finance entry'
          : 'Finance: ${inr.format(matched)} · declared: ${inr.format(staff.monthlySalary ?? 0)}';
    }

    Future<void> viewProof(StaffMember staff) async {
      if (staff.idProofPath == null) return;
      try {
        final url = await AttendanceRepo.staffProofUrl(staff.idProofPath!);
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      } catch (error) {
        if (context.mounted) toast(context, '$error');
      }
    }
    return PageBody(
      maxWidth: 1000,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final controls = <Widget>[
              IconButton(
                tooltip: 'Refresh staff register',
                onPressed: state.loading ? null : () => notifier.refresh(state.date),
                icon: const Icon(Icons.refresh),
              ),
              if (!canMark)
                TextButton.icon(
                  onPressed: selectDate,
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: Text(dateFmt.format(state.date)),
                )
              else
                Chip(avatar: const Icon(Icons.today_outlined, size: 18), label: Text(dateFmt.format(state.date))),
              if (canManageStaff)
                FilledButton.icon(onPressed: addStaff, icon: const Icon(Icons.person_add_alt), label: const Text('Add staff')),
            ];
            if (constraints.maxWidth < 620) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Staff attendance', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                  Align(alignment: Alignment.centerRight, child: Wrap(alignment: WrapAlignment.end, crossAxisAlignment: WrapCrossAlignment.center, children: controls)),
                ],
              );
            }
            return Row(
              children: [
                Expanded(
                  child: Text('Staff attendance', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                ),
                ...controls,
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        Text(
          canMark
              ? 'Mark today’s attendance for Housekeeping, STP operators and Security.'
              : 'Attendance is limited to your association and assigned monitor areas.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (state.error != null)
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: ListTile(leading: const Icon(Icons.error_outline), title: Text(state.error!)),
          ),
        if (state.loading && activeStaff.isNotEmpty) const LinearProgressIndicator(),
        if (canManageStaff) ...[
          const SizedBox(height: 12),
          SectionCard(
            title: 'Staff register · ${activeStaff.length} active',
            child: registerStaff.isEmpty
                ? const EmptyState('No staff have been added yet.', icon: Icons.badge_outlined)
                : Column(
                    children: [
                      for (final staff in registerStaff)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(child: Text(staff.name.isEmpty ? '?' : staff.name[0].toUpperCase())),
                          title: Text(staff.name),
                          subtitle: Text(
                            '${staff.type.label} · ${staff.area} · '
                            '${staff.employerType == StaffEmployerType.agency ? staff.agencyName : 'Association'}'
                            '${staff.monthlySalary == null ? '' : ' · ${inr.format(staff.monthlySalary)} / month'}'
                            '${canViewSalary ? '\n${salaryCheck(staff)}' : ''}',
                          ),
                          isThreeLine: canViewSalary,
                          trailing: Wrap(children: [
                            if (!staff.active) const Pill('Archived', color: AppColors.amber),
                            if (staff.idProofPath != null)
                              IconButton(
                                tooltip: 'View staff ID proof',
                                onPressed: () => viewProof(staff),
                                icon: const Icon(Icons.badge_outlined),
                              ),
                            if (canEditStaff)
                              IconButton(
                                tooltip: 'Edit or archive staff member',
                                onPressed: () => editStaff(staff),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                          ]),
                        ),
                    ],
                  ),
          ),
        ],
        const SizedBox(height: 12),
        if (activeStaff.isEmpty)
          const EmptyState('No staff are assigned to areas you can view.', icon: Icons.groups_outlined)
        else
          for (final type in StaffType.values)
            if (activeStaff.any((staff) => staff.type == type)) ...[
              const SizedBox(height: 8),
              SectionCard(
                title: type.label,
                child: Column(
                  children: [
                    for (final staff in activeStaff.where((staff) => staff.type == type))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(child: Text(staff.name.isEmpty ? '?' : staff.name[0].toUpperCase())),
                        title: Text(staff.name),
                        subtitle: Text(attendanceSubtitle(staff)),
                        isThreeLine: state.records[staff.id] != null,
                        trailing: canMark
                            ? DropdownButton<AttendanceStatus>(
                                value: state.records[staff.id]?.status,
                                hint: const Text('Mark'),
                                items: [
                                  for (final status in AttendanceStatus.values)
                                    DropdownMenuItem(value: status, child: Text(status.label)),
                                ],
                                onChanged: state.date == DateUtils.dateOnly(DateTime.now()) && !state.loading
                                    ? (status) {
                                        if (status != null) mark(staff, status);
                                      }
                                    : null,
                              )
                            : state.records[staff.id] == null
                            ? const Pill('Not marked', color: Colors.blueGrey)
                            : Pill(
                                state.records[staff.id]!.status.label,
                                color: switch (state.records[staff.id]!.status) {
                                  AttendanceStatus.present => AppColors.green,
                                  AttendanceStatus.absent => AppColors.red,
                                  AttendanceStatus.leave => AppColors.amber,
                                },
                              ),
                      ),
                  ],
                ),
              ),
            ],
        if (!canMark && !canReview)
          const EmptyState('Your role cannot view staff attendance.', icon: Icons.lock_outline),
      ],
    );
  }
}

class _StaffDraft {
  const _StaffDraft({
    required this.name,
    required this.type,
    required this.area,
    required this.employerType,
    required this.agencyName,
    required this.monthlySalary,
    required this.proof,
  });
  final String name;
  final StaffType type;
  final String area;
  final StaffEmployerType employerType;
  final String agencyName;
  final int monthlySalary;
  final PlatformFile proof;
}

class _StaffEditDraft {
  const _StaffEditDraft({
    required this.name,
    required this.type,
    required this.area,
    required this.employerType,
    required this.agencyName,
    required this.monthlySalary,
    required this.active,
  });

  final String name;
  final StaffType type;
  final String area;
  final StaffEmployerType employerType;
  final String agencyName;
  final int monthlySalary;
  final bool active;
}

Future<_StaffEditDraft?> _editStaffDialog(BuildContext context, StaffMember staff) =>
    showDialog<_StaffEditDraft>(context: context, builder: (_) => _EditStaffDialog(staff: staff));

class _EditStaffDialog extends StatefulWidget {
  const _EditStaffDialog({required this.staff});
  final StaffMember staff;

  @override
  State<_EditStaffDialog> createState() => _EditStaffDialogState();
}

class _EditStaffDialogState extends State<_EditStaffDialog> {
  late final _name = TextEditingController(text: widget.staff.name);
  late final _agency = TextEditingController(text: widget.staff.agencyName ?? '');
  late final _salary = TextEditingController(text: '${widget.staff.monthlySalary ?? ''}');
  late StaffType _type = widget.staff.type;
  late String _area = widget.staff.area;
  late StaffEmployerType _employerType = widget.staff.employerType;
  late bool _active = widget.staff.active;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _agency.dispose();
    _salary.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('Edit ${widget.staff.name}'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (_error != null) _validationMessage(_error!),
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Full name *')),
            const SizedBox(height: 12),
            DropdownButtonFormField<StaffType>(
              initialValue: _type,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Staff type'),
              items: [for (final option in StaffType.values) DropdownMenuItem(value: option, child: Text(option.label))],
              onChanged: (value) => setState(() {
                _type = value ?? _type;
                _area = switch (_type) {
                  StaffType.housekeeping => 'Cleaning',
                  StaffType.stpOperator => 'STP',
                  StaffType.security => 'Security',
                };
              }),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _area,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Monitor area'),
              items: [for (final option in monitorAreas) DropdownMenuItem(value: option, child: Text(option))],
              onChanged: (value) => setState(() => _area = value ?? _area),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<StaffEmployerType>(
              initialValue: _employerType,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Employer'),
              items: const [
                DropdownMenuItem(value: StaffEmployerType.association, child: Text('Association-employed')),
                DropdownMenuItem(value: StaffEmployerType.agency, child: Text('Agency-employed')),
              ],
              onChanged: (value) => setState(() => _employerType = value ?? _employerType),
            ),
            if (_employerType == StaffEmployerType.agency) ...[
              const SizedBox(height: 12),
              TextField(controller: _agency, decoration: const InputDecoration(labelText: 'Agency name *')),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _salary,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Monthly salary *', prefixText: '₹ '),
            ),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Active staff member'), value: _active, onChanged: (value) => setState(() => _active = value)),
          ])),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: _save, child: const Text('Save changes')),
        ],
      );

  void _save() {
    final salary = int.tryParse(_salary.text.trim());
    if (_name.text.trim().isEmpty) return setState(() => _error = 'Name is required');
    if (_employerType == StaffEmployerType.agency && _agency.text.trim().isEmpty) {
      return setState(() => _error = 'Agency name is required');
    }
    if (salary == null || salary <= 0) return setState(() => _error = 'Enter monthly salary');
    Navigator.pop(context, _StaffEditDraft(
      name: _name.text.trim(),
      type: _type,
      area: _area,
      employerType: _employerType,
      agencyName: _agency.text.trim(),
      monthlySalary: salary,
      active: _active,
    ));
  }
}

Future<_StaffDraft?> _addStaffDialog(BuildContext context) async {
  return showDialog<_StaffDraft>(context: context, builder: (_) => const _AddStaffDialog());
}

class _AddStaffDialog extends StatefulWidget {
  const _AddStaffDialog();

  @override
  State<_AddStaffDialog> createState() => _AddStaffDialogState();
}

class _AddStaffDialogState extends State<_AddStaffDialog> {
  final _name = TextEditingController();
  final _agency = TextEditingController();
  final _salary = TextEditingController();
  StaffType _type = StaffType.housekeeping;
  String _area = 'Cleaning';
  StaffEmployerType _employerType = StaffEmployerType.association;
  PlatformFile? _proof;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _agency.dispose();
    _salary.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Add staff member'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_error != null) _validationMessage(_error!),
                TextField(controller: _name, decoration: const InputDecoration(labelText: 'Full name *')),
                const SizedBox(height: 12),
                DropdownButtonFormField<StaffType>(
                  initialValue: _type,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Staff type'),
                  items: [for (final option in StaffType.values) DropdownMenuItem(value: option, child: Text(option.label))],
                  onChanged: (value) => setState(() {
                    _type = value ?? _type;
                    _area = switch (_type) {
                      StaffType.housekeeping => 'Cleaning',
                      StaffType.stpOperator => 'STP',
                      StaffType.security => 'Security',
                    };
                  }),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _area,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Monitor area'),
                  items: [for (final option in monitorAreas) DropdownMenuItem(value: option, child: Text(option))],
                  onChanged: (value) => setState(() => _area = value ?? _area),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<StaffEmployerType>(
                  initialValue: _employerType,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Employer'),
                  items: const [
                    DropdownMenuItem(value: StaffEmployerType.association, child: Text('Association-employed')),
                    DropdownMenuItem(value: StaffEmployerType.agency, child: Text('Agency-employed')),
                  ],
                  onChanged: (value) => setState(() => _employerType = value ?? _employerType),
                ),
                if (_employerType == StaffEmployerType.agency) ...[
                  const SizedBox(height: 12),
                  TextField(controller: _agency, decoration: const InputDecoration(labelText: 'Agency name *')),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: _salary,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Monthly salary *', prefixText: '₹ '),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _pickProof,
                  icon: Icon(_proof == null ? Icons.upload_file_outlined : Icons.verified_outlined),
                  label: Text(_proof?.name ?? 'Attach staff ID proof * (photos auto-compressed)'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: _save, child: const Text('Add staff')),
        ],
      );

  Future<void> _pickProof() async {
    final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'pdf']);
    if (files.isEmpty || !mounted) return;
    final size = await files.first.length();
    if (!mounted) return;
    if (size == null || size > maxSourceUploadBytes(files.first.extension ?? '')) {
      setState(() => _error = 'File exceeds the supported source size');
      return;
    }
    setState(() { _proof = files.first; _error = null; });
  }

  void _save() {
    if (_name.text.trim().isEmpty) return setState(() => _error = 'Name is required');
    if (_proof == null) return setState(() => _error = 'Staff ID proof is required');
    if (_employerType == StaffEmployerType.agency && _agency.text.trim().isEmpty) {
      return setState(() => _error = 'Agency name is required');
    }
    final parsedSalary = int.tryParse(_salary.text.trim());
    if (parsedSalary == null || parsedSalary <= 0) return setState(() => _error = 'Enter monthly salary');
    Navigator.pop(context, _StaffDraft(
      name: _name.text.trim(),
      type: _type,
      area: _area,
      employerType: _employerType,
      agencyName: _agency.text.trim(),
      monthlySalary: parsedSalary,
      proof: _proof!,
    ));
  }
}

Widget _validationMessage(String message) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Align(alignment: Alignment.centerLeft, child: Text(message, style: const TextStyle(color: Colors.red))),
    );
