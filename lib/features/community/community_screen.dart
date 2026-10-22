import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../../backend/backend.dart';
import '../../backend/community_repo.dart';
import '../../backend/finance_repo.dart';
import '../../backend/upload_preparation.dart' show maxSourceUploadBytes;
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

final emergencyContactsProvider = FutureProvider.autoDispose<List<EmergencyContact>>((ref) => CommunityRepo.emergencyContacts());
final communityEventsProvider = FutureProvider.autoDispose<List<CommunityEvent>>((ref) => CommunityRepo.events());
final meetingActionsProvider = FutureProvider.autoDispose<List<MeetingAction>>((ref) => CommunityRepo.actions());
final marketplaceProvider = FutureProvider.autoDispose<List<MarketplacePost>>((ref) => CommunityRepo.marketplace());
final communityFundRequestsProvider = FutureProvider.autoDispose<List<FundRequestRecord>>((ref) async =>
  backendEnabled ? (await FinanceRepo.fundRequests()).where((request) => request.status == 'active').toList() : const []);

class CommunityScreen extends ConsumerWidget {
  const CommunityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(sessionProvider)!.activeRole;
    final canManage = role == Role.admin || role == Role.president || role == Role.secretary;
    final canOrganize = canManage || role == Role.jointSecretary;
    final canPost = role == Role.owner;
    final financeVisible = role.seesFinance;
    final approvedExpenses = financeVisible
      ? ref.watch(expensesProvider).where((expense) => expense.status == ExpenseStatus.approved).toList()
      : const <Expense>[];
    final contacts = ref.watch(emergencyContactsProvider);
    final events = ref.watch(communityEventsProvider);
    final actions = ref.watch(meetingActionsProvider);
    final posts = ref.watch(marketplaceProvider);

    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surface,
            child: const TabBar(
              isScrollable: true,
              tabs: [Tab(text: 'Emergency'), Tab(text: 'Events'), Tab(text: 'MOM actions'), Tab(text: 'Marketplace')],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                PageBody(
                  children: [
                    _header('Emergency contacts', canManage ? 'Add contact' : null, canManage ? () => _addContact(context, ref) : null),
                    if (contacts.isLoading) const LinearProgressIndicator(),
                    if (contacts.hasError) _errorCard(contacts.error),
                    if (contacts.hasValue && contacts.value!.isEmpty)
                      const EmptyState('No emergency contacts published.', icon: Icons.emergency_outlined),
                    if (contacts.hasValue)
                      for (final contact in contacts.value!)
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.emergency_outlined, color: AppColors.red),
                            title: Text(contact.label),
                            subtitle: Text('${contact.name} · ${contact.phone}${contact.notes.isEmpty ? '' : '\n${contact.notes}'}'),
                            isThreeLine: contact.notes.isNotEmpty,
                          ),
                        ),
                  ],
                ),
                PageBody(
                  children: [
                    _header('Community events', canOrganize ? 'Add event' : null, canOrganize ? () => _addEvent(context, ref) : null),
                    if (events.isLoading) const LinearProgressIndicator(),
                    if (events.hasError) _errorCard(events.error),
                    if (events.hasValue && events.value!.isEmpty)
                      const EmptyState('No community events published.', icon: Icons.celebration_outlined),
                    if (events.hasValue)
                      for (final event in events.value!)
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.celebration_outlined),
                            title: Text(event.title),
                            subtitle: Text(
                              '${event.type} · ${dateTimeFmt.format(event.startsAt)} · ${event.location}'
                              '${event.budget == null ? '' : ' · Budget ${inr.format(event.budget)}'}'
                                '${event.fundRequestTitle == null ? '' : ' · Fund: ${event.fundRequestTitle}'}'
                                '${financeVisible ? ' · Approved spend: ${inr.format(approvedExpenses.where((expense) => expense.eventId == event.id).fold(0, (sum, expense) => sum + expense.amount))}' : ''}'
                              '${event.description.isEmpty ? '' : '\n${event.description}'}',
                            ),
                            isThreeLine: event.description.isNotEmpty,
                            trailing: Pill(event.status, color: event.status == 'scheduled' ? AppColors.green : Colors.blueGrey),
                          ),
                        if (event.photoPaths.isNotEmpty)
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: () async {
                                final url = await CommunityRepo.eventPhotoUrl(event.photoPaths.first);
                                await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                              },
                              icon: const Icon(Icons.photo_outlined),
                              label: Text('${event.photoPaths.length} event photo(s)'),
                            ),
                          ),
                        ),
                  ],
                ),
                PageBody(
                  children: [
                    _header('Action tracker', canOrganize ? 'Add action' : null, canOrganize ? () => _addAction(context, ref) : null),
                    if (actions.isLoading) const LinearProgressIndicator(),
                    if (actions.hasError) _errorCard(actions.error),
                    if (actions.hasValue && actions.value!.isEmpty)
                      const EmptyState('No MOM actions recorded.', icon: Icons.task_alt),
                    if (actions.hasValue)
                      for (final action in actions.value!)
                        Card(
                          child: ListTile(
                            leading: Icon(action.status == 'done' ? Icons.task_alt : Icons.pending_actions_outlined),
                            title: Text(action.title),
                            subtitle: Text('MOM ${action.momRef} · ${action.owner}${action.dueDate == null ? '' : ' · due ${dateFmt.format(action.dueDate!)}'}'),
                            trailing: canOrganize
                                ? DropdownButton<String>(
                                    value: action.status,
                                    underline: const SizedBox.shrink(),
                                    items: const [
                                      DropdownMenuItem(value: 'open', child: Text('Open')),
                                      DropdownMenuItem(value: 'in_progress', child: Text('In progress')),
                                      DropdownMenuItem(value: 'blocked', child: Text('Blocked')),
                                      DropdownMenuItem(value: 'done', child: Text('Done')),
                                    ],
                                    onChanged: (value) async {
                                      if (value == null) return;
                                      try {
                                        await CommunityRepo.updateAction(action.id, value);
                                        ref.invalidate(meetingActionsProvider);
                                      } catch (error) {
                                        if (context.mounted) toast(context, '$error');
                                      }
                                    },
                                  )
                                : Pill(action.status, color: action.status == 'done' ? AppColors.green : AppColors.amber),
                          ),
                        ),
                  ],
                ),
                PageBody(
                  children: [
                    _header('Owner marketplace', canPost ? 'Create post' : null, canPost ? () => _addPost(context, ref) : null),
                    const Text('Owner posts are visible to members of this association and expire after 30 days.'),
                    if (posts.isLoading) const LinearProgressIndicator(),
                    if (posts.hasError) _errorCard(posts.error),
                    if (posts.hasValue && posts.value!.isEmpty)
                      const EmptyState('No active marketplace posts.', icon: Icons.storefront_outlined),
                    if (posts.hasValue)
                      for (final post in posts.value!)
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.storefront_outlined),
                            title: Text(post.title),
                            subtitle: Text('${post.type.replaceAll('_', ' ')} · ${post.author} · ${post.contact}\n${post.description}'),
                            isThreeLine: true,
                            trailing: post.price == null ? null : Text(inr.format(post.price)),
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

Widget _header(String title, String? actionLabel, VoidCallback? action) => Row(
  children: [
    Expanded(child: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
    if (actionLabel != null) FilledButton.icon(onPressed: action, icon: const Icon(Icons.add), label: Text(actionLabel)),
  ],
);

Widget _errorCard(Object? error) => Card(child: ListTile(leading: const Icon(Icons.error_outline), title: Text('$error')));

Future<void> _addContact(BuildContext context, WidgetRef ref) async {
  final label = TextEditingController();
  final name = TextEditingController();
  final phone = TextEditingController();
  final notes = TextEditingController();
  final result = await _simpleDialog(context, title: 'Emergency contact', fields: [
    TextField(controller: label, decoration: const InputDecoration(labelText: 'Service / label *')),
    TextField(controller: name, decoration: const InputDecoration(labelText: 'Contact name *')),
    TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone *')),
    TextField(controller: notes, decoration: const InputDecoration(labelText: 'Notes')),
  ]);
  if (result == true) {
    try {
      await CommunityRepo.addEmergencyContact(label: label.text, name: name.text, phone: phone.text, category: 'Emergency', notes: notes.text);
      ref.invalidate(emergencyContactsProvider);
    } catch (error) {
      if (context.mounted) toast(context, '$error');
    }
  }
  label.dispose(); name.dispose(); phone.dispose(); notes.dispose();
}

Future<void> _addEvent(BuildContext context, WidgetRef ref) async {
  final fundRequests = backendEnabled
      ? (await FinanceRepo.fundRequests()).where((request) => request.status == 'active').toList()
      : <FundRequestRecord>[];
  final title = TextEditingController();
  final description = TextEditingController();
  final location = TextEditingController();
  final budget = TextEditingController();
  var type = 'Festival';
  var startsAt = DateTime.now().add(const Duration(days: 7));
  var endsAt = startsAt.add(const Duration(hours: 3));
  PlatformFile? photo;
  String? fundRequestId;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: const Text('Schedule community event'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: title, decoration: const InputDecoration(labelText: 'Event name *')),
            DropdownButtonFormField<String>(initialValue: type, decoration: const InputDecoration(labelText: 'Type'),
              items: const [for (final t in ['Festival','Kids activity','Republic Day','Onam','Christmas','Other']) DropdownMenuItem(value: t, child: Text(t))], onChanged: (v) => set(() => type = v ?? type)),
            TextField(controller: location, decoration: const InputDecoration(labelText: 'Location')),
            TextField(controller: budget, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], decoration: const InputDecoration(labelText: 'Budget (optional)', prefixText: '₹ ')),
            TextField(controller: description, maxLines: 2, decoration: const InputDecoration(labelText: 'Details')),
              if (fundRequests.isNotEmpty)
                DropdownButtonFormField<String?>(
                  initialValue: fundRequestId,
                  decoration: const InputDecoration(labelText: 'Approved fund request (optional)'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('No fund request linked')),
                    for (final request in fundRequests)
                      DropdownMenuItem<String?>(value: request.id, child: Text(request.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (value) => set(() => fundRequestId = value),
                ),
            OutlinedButton.icon(onPressed: () async {
              final files=await FilePicker.pickFiles(type:FileType.custom,allowedExtensions:const ['jpg','jpeg','png','webp']);
              if(files.isEmpty||!ctx.mounted)return;
              final size=await files.first.length();
              if(!ctx.mounted)return;
              if(size==null||size>maxSourceUploadBytes(files.first.extension??''))return;
              set(()=>photo=files.first);
            }, icon: const Icon(Icons.photo_camera_outlined), label: Text(photo?.name ?? 'Add event photo (auto-compressed)')),
            TextButton.icon(onPressed: () async {
              final date=await showDatePicker(context: ctx, initialDate: startsAt, firstDate: DateUtils.dateOnly(DateTime.now()), lastDate: DateTime.now().add(const Duration(days: 730)));
              if(date==null||!ctx.mounted)return;
              final time=await showTimePicker(context: ctx, initialTime: TimeOfDay.fromDateTime(startsAt));
              if(time!=null)set(()=>startsAt=DateTime(date.year,date.month,date.day,time.hour,time.minute));
            }, icon: const Icon(Icons.event), label: Text('Starts ${dateTimeFmt.format(startsAt)}')),
            TextButton.icon(onPressed: () async {
              final date=await showDatePicker(context: ctx, initialDate: endsAt, firstDate: DateUtils.dateOnly(startsAt), lastDate: DateTime.now().add(const Duration(days: 730)));
              if(date==null||!ctx.mounted)return;
              final time=await showTimePicker(context: ctx, initialTime: TimeOfDay.fromDateTime(endsAt));
              if(time!=null)set(()=>endsAt=DateTime(date.year,date.month,date.day,time.hour,time.minute));
            }, icon: const Icon(Icons.event_available), label: Text('Ends ${dateTimeFmt.format(endsAt)}')),
          ])),
        ),
        actions: [TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Schedule'))],
      ),
    ),
  );
  if(ok==true){try{await CommunityRepo.addEvent(title:title.text,type:type,startsAt:startsAt,endsAt:endsAt,location:location.text,budget:int.tryParse(budget.text),description:description.text,photo:photo==null?null:await photo!.readAsBytes(),photoExtension:photo?.extension,fundRequestId:fundRequestId);ref.invalidate(communityEventsProvider);}catch(error){if(context.mounted)toast(context,'$error');}}
  title.dispose();description.dispose();location.dispose();budget.dispose();
}

Future<void> _addAction(BuildContext context, WidgetRef ref) async {
  final mom=TextEditingController();final title=TextEditingController();DateTime? due;
  final ok=await showDialog<bool>(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,set)=>AlertDialog(
    title:const Text('Add action from MOM'),content:SizedBox(width:420,child:Column(mainAxisSize:MainAxisSize.min,children:[
      TextField(controller:mom,decoration:const InputDecoration(labelText:'MOM reference *')),
      TextField(controller:title,decoration:const InputDecoration(labelText:'Action *')),
      TextButton.icon(onPressed:()async{final d=await showDatePicker(context:ctx,initialDate:DateTime.now().add(const Duration(days:7)),firstDate:DateTime.now(),lastDate:DateTime.now().add(const Duration(days:730)));if(d!=null)set(()=>due=d);},icon:const Icon(Icons.calendar_today),label:Text(due==null?'Due date (optional)':dateFmt.format(due!))),
    ])),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Add action'))],
  )));
  if(ok==true){try{await CommunityRepo.addAction(momRef:mom.text,title:title.text,dueDate:due);ref.invalidate(meetingActionsProvider);}catch(error){if(context.mounted)toast(context,'$error');}}
  mom.dispose();title.dispose();
}

Future<void> _addPost(BuildContext context, WidgetRef ref) async {
  final title=TextEditingController();final description=TextEditingController();final contact=TextEditingController();final price=TextEditingController();var type='for_sale';
  final ok=await showDialog<bool>(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,set)=>AlertDialog(
    title:const Text('Marketplace post'),content:SizedBox(width:420,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
      DropdownButtonFormField<String>(initialValue:type,decoration:const InputDecoration(labelText:'Post type'),items:const [DropdownMenuItem(value:'for_sale',child:Text('For sale')),DropdownMenuItem(value:'wanted',child:Text('Wanted')),DropdownMenuItem(value:'service_recommendation',child:Text('Service recommendation'))],onChanged:(v)=>set(()=>type=v??type)),
      TextField(controller:title,decoration:const InputDecoration(labelText:'Title *')),
      TextField(controller:description,maxLines:3,decoration:const InputDecoration(labelText:'Description *')),
      TextField(controller:price,keyboardType:TextInputType.number,inputFormatters:[FilteringTextInputFormatter.digitsOnly],decoration:const InputDecoration(labelText:'Price (optional)',prefixText:'₹ ')),
      TextField(controller:contact,decoration:const InputDecoration(labelText:'Contact *')),
    ]))),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Post'))],
  )));
  if(ok==true){try{await CommunityRepo.addMarketplacePost(type:type,title:title.text,description:description.text,contact:contact.text,price:int.tryParse(price.text));ref.invalidate(marketplaceProvider);}catch(error){if(context.mounted)toast(context,'$error');}}
  title.dispose();description.dispose();contact.dispose();price.dispose();
}

Future<bool?> _simpleDialog(BuildContext context,{required String title,required List<Widget> fields})=>showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:Text(title),content:SizedBox(width:420,child:Column(mainAxisSize:MainAxisSize.min,children:fields)),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Save'))]));
