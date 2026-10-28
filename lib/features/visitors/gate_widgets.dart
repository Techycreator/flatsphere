import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../../backend/directory_repo.dart' show friendlyError;
import '../../backend/gate_offline.dart';
import '../../backend/gate_repo.dart';
import '../../widgets/common.dart';

// Large, simple screens for gate staff (many guards are older and use basic phones).

const _big = TextStyle(fontSize: 22);

String normFlat(String v) => v.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

/// Flat numbers from the server, or the copy saved on this phone when offline.
Future<List<String>> loadGateFlats() async {
  try {
    final f = await GateRepo.flatNumbers();
    await GateOffline.cacheFlats(f);
    return f;
  } catch (_) {
    return GateOffline.cachedFlats();
  }
}

Future<T?> openGatePage<T>(BuildContext context, Widget page) =>
    Navigator.of(context, rootNavigator: true).push<T>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => page));

InputDecoration bigField(String label, {String? hint, IconData? icon}) => InputDecoration(
  labelText: label,
  hintText: hint,
  prefixIcon: icon == null ? null : Icon(icon, size: 28),
  border: const OutlineInputBorder(),
  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
);

/// Full-screen page with a big title, close button and one big action at the bottom.
class GatePage extends StatelessWidget {
  const GatePage({super.key, required this.title, required this.children, this.action});
  final String title;
  final List<Widget> children;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      toolbarHeight: 64,
      leading: IconButton(
        iconSize: 32,
        tooltip: 'Close',
        icon: const Icon(Icons.close),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(padding: const EdgeInsets.all(16), children: children),
        ),
      ),
    ),
    bottomNavigationBar: action == null
        ? null
        : SafeArea(
            child: Center(
              heightFactor: 1,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: SizedBox(height: 64, width: double.infinity, child: action),
                ),
              ),
            ),
          ),
  );
}

Widget _label(String text) => Padding(
  padding: const EdgeInsets.only(top: 18, bottom: 8),
  child: Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
);

/// UPI-PIN style entry: digit boxes and a large number pad. Returns the code or null.
Future<String?> showCodePad(
  BuildContext context, {
  required String title,
  String? subtitle,
  int length = 6,
  bool obscure = false,
  String action = 'Check',
}) => openGatePage<String>(
  context,
  CodePad(title: title, subtitle: subtitle, length: length, obscure: obscure, action: action),
);

class CodePad extends StatefulWidget {
  const CodePad({
    super.key,
    required this.title,
    this.subtitle,
    this.length = 6,
    this.obscure = false,
    this.action = 'Check',
  });
  final String title, action;
  final String? subtitle;
  final int length;
  final bool obscure;

  @override
  State<CodePad> createState() => _CodePadState();
}

class _CodePadState extends State<CodePad> {
  String _code = '';
  bool _hide = true;

  void _add(String d) {
    if (_code.length < widget.length) setState(() => _code += d);
  }

  void _back() {
    if (_code.isNotEmpty) setState(() => _code = _code.substring(0, _code.length - 1));
  }

  bool get _full => _code.length == widget.length;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final masked = widget.obscure && _hide;
    Widget key(Widget child, VoidCallback onTap) => Expanded(
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: SizedBox(
          height: 68,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              side: BorderSide(color: scheme.outlineVariant, width: 1.5),
              backgroundColor: scheme.surfaceContainerHighest.withValues(alpha: .4),
            ),
            onPressed: onTap,
            child: child,
          ),
        ),
      ),
    );
    Widget digit(String d) => key(
      Text(
        d,
        style: TextStyle(fontSize: 30, fontWeight: FontWeight.w600, color: scheme.onSurface),
      ),
      () => _add(d),
    );
    return Focus(
      autofocus: true,
      onKeyEvent: (_, e) {
        if (e is! KeyDownEvent) return KeyEventResult.ignored;
        final c = e.character;
        if (c != null && RegExp(r'^[0-9]$').hasMatch(c)) {
          _add(c);
        } else if (e.logicalKey == LogicalKeyboardKey.backspace) {
          _back();
        } else if (e.logicalKey == LogicalKeyboardKey.enter && _full) {
          Navigator.pop(context, _code);
        } else {
          return KeyEventResult.ignored;
        }
        return KeyEventResult.handled;
      },
      child: GatePage(
        title: widget.title,
        action: FilledButton.icon(
          onPressed: _full ? () => Navigator.pop(context, _code) : null,
          icon: const Icon(Icons.check_circle, size: 30),
          label: Text(widget.action, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        ),
        children: [
          if (widget.subtitle != null)
            Text(widget.subtitle!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < widget.length; i++)
                Container(
                  width: 46,
                  height: 60,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: i < _code.length ? scheme.primaryContainer : null,
                    border: Border.all(
                      color: i == _code.length ? scheme.primary : scheme.outline,
                      width: i == _code.length ? 3 : 1.5,
                    ),
                  ),
                  child: Text(
                    i < _code.length ? (masked ? '●' : _code[i]) : '',
                    style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
                  ),
                ),
            ],
          ),
          if (widget.obscure)
            Center(
              child: TextButton.icon(
                onPressed: () => setState(() => _hide = !_hide),
                icon: Icon(_hide ? Icons.visibility : Icons.visibility_off),
                label: Text(_hide ? 'Show digits' : 'Hide digits', style: const TextStyle(fontSize: 16)),
              ),
            ),
          const SizedBox(height: 24),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                children: [
                  for (final row in const [
                    ['1', '2', '3'],
                    ['4', '5', '6'],
                    ['7', '8', '9'],
                  ])
                    Row(children: [for (final d in row) digit(d)]),
                  Row(
                    children: [
                      key(
                        Text('Clear', style: TextStyle(fontSize: 20, color: scheme.onSurface)),
                        () => setState(() => _code = ''),
                      ),
                      digit('0'),
                      key(Icon(Icons.backspace_outlined, size: 30, color: scheme.onSurface), _back),
                    ],
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

/// Big tick or cross so the result is clear at a glance.
Future<void> showGateResult(BuildContext context, {required bool ok, required String message}) => showDialog<void>(
  context: context,
  builder: (ctx) => AlertDialog(
    icon: Icon(ok ? Icons.check_circle : Icons.cancel, size: 80, color: ok ? AppColors.green : AppColors.red),
    content: Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22)),
    actions: [
      SizedBox(
        width: double.infinity,
        height: 56,
        child: FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('OK', style: TextStyle(fontSize: 22)),
        ),
      ),
    ],
  ),
);

/// Type a few letters; matching flats appear as big buttons to tap.
class FlatPicker extends StatefulWidget {
  const FlatPicker({super.key, required this.flats, required this.onChanged, this.initial});
  final List<String> flats;
  final ValueChanged<String?> onChanged;
  final String? initial;

  @override
  State<FlatPicker> createState() => _FlatPickerState();
}

class _FlatPickerState extends State<FlatPicker> {
  final _c = TextEditingController();
  late String? _picked = widget.initial;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _pick(String? f) {
    setState(() => _picked = f);
    if (f == null) _c.clear();
    widget.onChanged(f);
  }

  @override
  Widget build(BuildContext context) {
    if (_picked != null) {
      return Card(
        margin: EdgeInsets.zero,
        color: AppColors.green.withValues(alpha: .15),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          leading: const Icon(Icons.home, size: 36, color: AppColors.green),
          title: Text('Flat $_picked', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
          trailing: OutlinedButton(
            onPressed: () => _pick(null),
            child: const Text('Change', style: TextStyle(fontSize: 18)),
          ),
        ),
      );
    }
    final q = normFlat(_c.text);
    final matches = q.isEmpty
        ? const <String>[]
        : [
            ...widget.flats.where((f) => normFlat(f).startsWith(q)),
            ...widget.flats.where((f) => !normFlat(f).startsWith(q) && normFlat(f).contains(q)),
          ].take(12).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _c,
          textCapitalization: TextCapitalization.characters,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
          decoration: bigField('Flat number', hint: 'Type e.g. A1 or 101', icon: Icons.home_outlined),
          onChanged: (v) {
            setState(() {});
            if (widget.flats.isEmpty) widget.onChanged(v.trim().isEmpty ? null : v.trim().toUpperCase());
          },
          onSubmitted: (_) {
            if (matches.length == 1) _pick(matches.first);
          },
        ),
        if (matches.isNotEmpty) ...[
          const SizedBox(height: 10),
          const Text('Tap the flat:', style: TextStyle(fontSize: 16)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final f in matches)
                SizedBox(
                  height: 56,
                  child: FilledButton.tonal(
                    onPressed: () => _pick(f),
                    child: Text(f, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                  ),
                ),
            ],
          ),
        ] else if (q.isNotEmpty && widget.flats.isNotEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('No flat matches. Check the number.', style: TextStyle(fontSize: 17, color: AppColors.red)),
          ),
      ],
    );
  }
}

typedef WalkInData = ({String flat, String name, String phone, String type, String vehicle, Uint8List? photo});

class WalkInPage extends StatefulWidget {
  const WalkInPage({super.key, required this.flats});
  final List<String> flats;

  @override
  State<WalkInPage> createState() => _WalkInPageState();
}

class _WalkInPageState extends State<WalkInPage> {
  final _name = TextEditingController(), _phone = TextEditingController(), _vehicle = TextEditingController();
  String _type = 'guest';
  String? _flat;
  Uint8List? _photo;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _vehicle.dispose();
    super.dispose();
  }

  Future<void> _takePhoto() async {
    final f = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 800, imageQuality: 60);
    if (f == null) return;
    final b = await f.readAsBytes();
    if (mounted) setState(() => _photo = b);
  }

  void _submit() {
    if (_flat == null) return toast(context, 'Choose the flat first.');
    if (_name.text.trim().isEmpty) return toast(context, 'Enter the visitor name.');
    Navigator.pop<WalkInData>(context, (
      flat: _flat!,
      name: _name.text.trim(),
      phone: _phone.text.trim(),
      type: _type,
      vehicle: _vehicle.text.trim(),
      photo: _photo,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget typeTile(String value, IconData icon, String label) {
      final on = _type == value;
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: SizedBox(
            height: 88,
            child: (on ? FilledButton.new : OutlinedButton.new)(
              onPressed: () => setState(() => _type = value),
              style: ButtonStyle(
                padding: const WidgetStatePropertyAll(EdgeInsets.all(4)),
                shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 32),
                  const SizedBox(height: 4),
                  FittedBox(
                    child: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return GatePage(
      title: 'Walk-in visitor',
      action: FilledButton.icon(
        onPressed: _submit,
        icon: const Icon(Icons.send, size: 28),
        label: const Text('Ask flat to approve', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700)),
      ),
      children: [
        _label('1. Who is it?'),
        Row(
          children: [
            typeTile('guest', Icons.person, 'Guest'),
            typeTile('delivery', Icons.local_shipping, 'Delivery'),
            typeTile('cab', Icons.local_taxi, 'Cab'),
            typeTile('service', Icons.handyman, 'Service'),
          ],
        ),
        _label('2. Which flat?'),
        FlatPicker(flats: widget.flats, onChanged: (f) => setState(() => _flat = f)),
        _label('3. Visitor details'),
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          style: _big,
          decoration: bigField('Name / company *', icon: Icons.badge_outlined),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))],
          style: _big,
          decoration: bigField('Phone (optional)', icon: Icons.phone_outlined),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _vehicle,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [VehicleNumberFormatter()],
          style: const TextStyle(fontSize: 22, letterSpacing: 1.5),
          decoration: bigField(
            'Vehicle number (optional)',
            hint: 'KL07AB1234 – no spaces needed',
            icon: Icons.directions_car_outlined,
          ),
        ),
        _label('4. Photo (optional)'),
        if (_photo != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(_photo!, height: 160, fit: BoxFit.cover),
          ),
        const SizedBox(height: 8),
        SizedBox(
          height: 60,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(side: BorderSide(color: scheme.primary, width: 1.5)),
            onPressed: _takePhoto,
            icon: Icon(_photo == null ? Icons.photo_camera : Icons.refresh, size: 28),
            label: Text(_photo == null ? 'Take visitor photo' : 'Retake photo', style: const TextStyle(fontSize: 20)),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

/// Pick a flat (or start with one) and show big call buttons for its owners and residents.
class CallFlatPage extends StatefulWidget {
  const CallFlatPage({super.key, required this.flats, this.initial});
  final List<String> flats;
  final String? initial;

  @override
  State<CallFlatPage> createState() => _CallFlatPageState();
}

class _CallFlatPageState extends State<CallFlatPage> {
  String? _flat;
  bool _loading = false;
  String? _error;
  List<({String name, String role, String mobile})> _people = const [];

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) _select(widget.initial);
  }

  Future<void> _select(String? f) async {
    setState(() {
      _flat = f;
      _people = const [];
      _error = null;
      _loading = f != null;
    });
    if (f == null) return;
    try {
      final people = await GateRepo.flatContacts(f);
      if (mounted && _flat == f) {
        setState(() {
          _people = people;
          _loading = false;
          if (people.isEmpty) _error = 'No phone number saved for flat $f.';
        });
      }
    } catch (e) {
      if (mounted && _flat == f) {
        setState(() {
          _loading = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => GatePage(
    title: 'Call a flat',
    children: [
      FlatPicker(
        flats: widget.flats,
        initial: widget.initial,
        onChanged: (f) {
          if (widget.flats.isNotEmpty || f == null) _select(f);
        },
      ),
      if (widget.flats.isEmpty && _flat == null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text('Type the full flat number and press Enter.', style: TextStyle(fontSize: 16)),
        ),
      const SizedBox(height: 16),
      if (_loading) const Center(child: CircularProgressIndicator()),
      if (_error != null) Text(_error!, style: const TextStyle(fontSize: 19, color: AppColors.red)),
      for (final p in _people)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: SizedBox(
            height: 80,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.green,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              onPressed: () => launchUrl(Uri(scheme: 'tel', path: p.mobile)),
              child: Row(
                children: [
                  const Icon(Icons.call, size: 36),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
                        ),
                        Text('${p.role} · ${p.mobile}', style: const TextStyle(fontSize: 17)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
    ],
  );
}

/// Big list of guards; returns the one who taps their name.
class GuardPickPage extends StatelessWidget {
  const GuardPickPage({super.key, required this.guards});
  final List<({String id, String name})> guards;

  @override
  Widget build(BuildContext context) => GatePage(
    title: 'Who is on duty?',
    children: [
      const Text('Tap your name', style: TextStyle(fontSize: 18)),
      const SizedBox(height: 12),
      for (final g in guards)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: SizedBox(
            height: 68,
            child: FilledButton.tonalIcon(
              style: FilledButton.styleFrom(alignment: Alignment.centerLeft),
              onPressed: () => Navigator.pop(context, g),
              icon: const Icon(Icons.person, size: 32),
              label: Text(g.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
            ),
          ),
        ),
    ],
  );
}
