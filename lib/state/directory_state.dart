import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/backend.dart';
import '../backend/directory_repo.dart';
import '../models/models.dart';
import 'app_state.dart';
import 'demo_data.dart';

class DirectoryState {
  const DirectoryState({this.flats = const [], this.people = const [], this.loading = false, this.error});
  final List<FlatInfo> flats;
  final List<Person> people;
  final bool loading;
  final String? error;

  List<Person> at(String flat, Role role) => people.where((p) => p.flatNumber == flat && p.role == role).toList();

  FlatInfo? flat(String? number) => flats.where((f) => f.number == number).firstOrNull;
}

final directoryProvider = NotifierProvider<DirectoryNotifier, DirectoryState>(DirectoryNotifier.new);

/// Demo mode keeps everything in memory; cloud mode reads/writes Supabase (server re-checks every change).
class DirectoryNotifier extends Notifier<DirectoryState> {
  final _demoDocs = <String, List<IdDocument>>{};

  @override
  DirectoryState build() {
    if (!backendEnabled) return DirectoryState(flats: _demoFlatInfos(), people: _demoPeople());
    if (ref.watch(sessionProvider.select((s) => s?.user.id)) != null) refresh();
    return const DirectoryState(loading: true);
  }

  Future<void> refresh() async {
    if (!backendEnabled) return;
    try {
      final flats = await DirectoryRepo.flats();
      final people = await DirectoryRepo.people();
      state = DirectoryState(flats: flats, people: people);
    } catch (e) {
      state = DirectoryState(flats: state.flats, people: state.people, error: friendlyError(e));
    }
  }

  void _set({List<FlatInfo>? flats, List<Person>? people}) =>
      state = DirectoryState(flats: flats ?? state.flats, people: people ?? state.people);

  Future<void> saveFlat(FlatInfo f) async {
    if (backendEnabled) {
      await DirectoryRepo.saveFlat(f);
      return refresh();
    }
    final list = [
      for (final x in state.flats)
        if (x.id != f.id) x,
      FlatInfo(
        id: f.id ?? f.number,
        number: f.number,
        block: f.block,
        type: f.type,
        sqft: f.sqft,
        occupancy: f.occupancy,
      ),
    ]..sort((a, b) => a.number.compareTo(b.number));
    _set(flats: list);
  }

  /// Returns 'member' or 'invited'.
  Future<String> addPerson(Person p) async {
    if (backendEnabled) {
      final r = await DirectoryRepo.add(p);
      await refresh();
      return r;
    }
    final existing = state.people.any((x) => x.email.toLowerCase() == p.email.toLowerCase() && !x.invited);
    final added = Person(
      id: 'p${DateTime.now().microsecondsSinceEpoch}',
      name: p.name,
      email: p.email,
      mobile: p.mobile,
      role: p.role,
      flatNumber: p.flatNumber,
      designations: p.designations,
      monitorCategories: p.monitorCategories,
      monitorFrom: p.monitorFrom,
      monitorUntil: p.monitorUntil,
      assignedBy: p.monitorCategories.isEmpty ? null : 'You',
      invited: !existing,
      since: DateTime.now(),
    );
    _set(people: [...state.people, added]);
    return existing ? 'member' : 'invited';
  }

  Future<void> setDetails(
    Person p,
    List<String> designations,
    List<String> areas, {
    DateTime? from,
    DateTime? until,
  }) async {
    if (backendEnabled) {
      await DirectoryRepo.setDetails(p, designations, areas, from: from, until: until);
      return refresh();
    }
    _set(
      people: [
        for (final x in state.people)
          if (x.id == p.id)
            Person(
              id: x.id,
              name: x.name,
              email: x.email,
              mobile: x.mobile,
              role: x.role,
              flatNumber: x.flatNumber,
              invited: x.invited,
              since: x.since,
              designations: designations,
              monitorCategories: areas,
              monitorFrom: from,
              monitorUntil: until,
              assignedBy: areas.isEmpty ? null : 'You',
            )
          else
            x,
      ],
    );
  }

  Future<void> removePerson(Person p) async {
    if (backendEnabled) {
      await DirectoryRepo.remove(p);
      return refresh();
    }
    _set(people: state.people.where((x) => x.id != p.id).toList());
  }

  Future<List<IdDocument>> docs(Person p) async {
    if (backendEnabled) return DirectoryRepo.docs(p.email);
    return _demoDocs[p.email.toLowerCase()] ?? const [];
  }

  Future<void> uploadDoc(Person p, String type, String last4, Uint8List bytes, String ext) async {
    if (backendEnabled) {
      return DirectoryRepo.uploadDoc(
        person: p,
        flatId: state.flat(p.flatNumber)?.id,
        type: type,
        last4: last4,
        bytes: bytes,
        ext: ext,
      );
    }
    final key = p.email.toLowerCase();
    _demoDocs[key] = [
      IdDocument(id: 'd${DateTime.now().microsecondsSinceEpoch}', type: type, last4: last4, uploadedAt: DateTime.now()),
      ...?_demoDocs[key],
    ];
  }

  /// Null in demo mode (files are not stored).
  Future<String?> viewUrl(IdDocument d) async => backendEnabled && d.path != null ? DirectoryRepo.viewUrl(d) : null;
}

List<FlatInfo> _demoFlatInfos() => [
  for (final f in demoFlats)
    FlatInfo(id: f.number, number: f.number, block: f.block, type: f.type, sqft: f.sqft, occupancy: f.occupancy),
];

String _demoEmail(String name) => '${name.replaceAll('CA ', '').split(' ').first.toLowerCase()}@demo.flatsphere.in';

List<Person> _demoPeople() {
  final people = <Person>[
    for (final u in demoUsers)
      for (final r in u.roles)
        Person(
          id: '${u.id}-${r.name}',
          name: u.name,
          email: _demoEmail(u.name),
          mobile: u.mobile,
          role: r,
          flatNumber: r == Role.owner || r == Role.resident ? u.flatNumber : null,
          designations: r == Role.ecMember ? u.designations : const [],
          monitorCategories: r == Role.monitor ? u.monitorCategories : const [],
          monitorFrom: r == Role.monitor ? DateTime(2026, 4, 1) : null,
          monitorUntil: r == Role.monitor ? DateTime(2026, 12, 31) : null,
          assignedBy: r == Role.monitor ? 'President' : null,
        ),
  ];
  bool has(String name, Role r, String flat) =>
      people.any((p) => p.name == name && p.role == r && p.flatNumber == flat);
  for (final f in demoFlats) {
    if (!has(f.ownerName, Role.owner, f.number)) {
      people.add(
        Person(
          id: 'o-${f.number}',
          name: f.ownerName,
          email: _demoEmail(f.ownerName),
          role: Role.owner,
          flatNumber: f.number,
        ),
      );
    }
    final res = f.residentName;
    if (res != null && !has(res, Role.resident, f.number)) {
      people.add(
        Person(id: 'r-${f.number}', name: res, email: _demoEmail(res), role: Role.resident, flatNumber: f.number),
      );
    }
  }
  return people;
}
