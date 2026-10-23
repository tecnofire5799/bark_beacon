import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';

typedef PetDoc = QueryDocumentSnapshot<Map<String, dynamic>>;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const BarkBeaconApp());
}

class BarkBeaconApp extends StatelessWidget {
  const BarkBeaconApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BarkBeacon',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: const Shell(),
    );
  }
}

// ---------------------------------------------------------------------------
// Shell: bottom bar (Home / Map / Radar). Profile opens inside the same shell
// so the bottom bar stays visible, as in the wireframe.
// ---------------------------------------------------------------------------

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0;
  bool _showProfile = false;

  void _goTo(int i) => setState(() {
    _index = i;
    _showProfile = false;
  });

  void _openProfile() => setState(() => _showProfile = true);

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // The phone's back button closes Profile before it closes the app.
      canPop: !_showProfile,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) setState(() => _showProfile = false);
      },
      child: Scaffold(
        // IndexedStack keeps every page alive, so each keeps its state.
        body: IndexedStack(
          index: _showProfile ? 3 : _index,
          children: [
            HomeScreen(onOpenMap: () => _goTo(1), onOpenProfile: _openProfile),
            const PlaceholderScreen(
              icon: Icons.map,
              title: 'Map',
              note:
                  'Coming in Milestone 2: your location and Lost Pet markers.',
            ),
            const PlaceholderScreen(
              icon: Icons.radar,
              title: 'Radar',
              note: 'Coming in Milestone 3: Bluetooth signal strength and compass.',
            ),
            const ProfileScreen(),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _goTo,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.map), label: 'Map'),
            NavigationDestination(icon: Icon(Icons.radar), label: 'Radar'),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

/// Returns the text in [value], or [fallback] when it is missing or blank.
String _orDefault(dynamic value, String fallback) {
  final s = value is String ? value.trim() : '';
  return s.isEmpty ? fallback : s;
}

/// The single account document (there is no login yet, so one profile).
DocumentReference<Map<String, dynamic>> get _profileRef =>
    FirebaseFirestore.instance.collection('users').doc('profile');

String _fullName(Map<String, dynamic>? data) {
  final first = _orDefault(data?['firstName'], '');
  final last = _orDefault(data?['lastName'], '');
  return '$first $last'.trim();
}

String _timeAgo(Timestamp? ts) {
  // A just-saved document has no server time yet, so ts can be null.
  if (ts == null) return 'just now';
  final diff = DateTime.now().difference(ts.toDate());
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  return '${diff.inDays} d ago';
}

/// Shows the "Add a pet" form and saves the pet to Firestore.
/// Returns the new document's id, or null if the user cancelled or it failed.
Future<String?> addPetFlow(BuildContext context) async {
  final result = await showDialog<Map<String, String>>(
    context: context,
    builder: (_) => const _AddPetDialog(),
  );
  if (result == null) return null;
  try {
    final ref = await FirebaseFirestore.instance.collection('pets').add({
      ...result,
      'status': 'Safe',
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
    return null;
  }
}

class _AddPetDialog extends StatefulWidget {
  const _AddPetDialog();

  @override
  State<_AddPetDialog> createState() => _AddPetDialogState();
}

class _AddPetDialogState extends State<_AddPetDialog> {
  final _name = TextEditingController();
  final _type = TextEditingController();
  final _address = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _type.dispose();
    _address.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return; // a pet needs at least a name
    Navigator.pop(context, {
      'name': name,
      'type': _type.text.trim(),
      'address': _address.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add a pet'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Pet name'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _type,
              decoration: const InputDecoration(
                labelText: 'Pet type (dog, cat...)',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _address,
              decoration: const InputDecoration(labelText: 'Return address'),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Home screen (matches the Home wireframe)
// ---------------------------------------------------------------------------

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.onOpenMap,
    required this.onOpenProfile,
  });

  final VoidCallback onOpenMap;
  final VoidCallback onOpenProfile;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _pets = FirebaseFirestore.instance.collection('pets');
  final _chipScroll = ScrollController();
  String? _selectedId;

  @override
  void dispose() {
    _chipScroll.dispose();
    super.dispose();
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  void _scrollChips(double delta) {
    if (!_chipScroll.hasClients) return;
    final target = (_chipScroll.offset + delta)
        .clamp(0.0, _chipScroll.position.maxScrollExtent)
        .toDouble();
    _chipScroll.animateTo(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  Future<void> _addPet() async {
    final id = await addPetFlow(context);
    if (id != null && mounted) setState(() => _selectedId = id);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return SafeArea(
      // One stream feeds both the pet selector and the pet card.
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _pets.orderBy('createdAt', descending: true).snapshots(),
        builder: (context, snap) {
          final docs = snap.data?.docs ?? <PetDoc>[];

          PetDoc? selected;
          for (final d in docs) {
            if (d.id == _selectedId) selected = d;
          }
          selected ??= docs.isNotEmpty ? docs.first : null;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Top bar: profile avatar (left) and notifications (right)
              Row(
                children: [
                  InkWell(
                    customBorder: const CircleBorder(),
                    onTap: widget.onOpenProfile,
                    child: const CircleAvatar(
                      radius: 22,
                      child: Icon(Icons.person),
                    ),
                  ),
                  const Spacer(),
                  IconButton.filledTonal(
                    onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('No new notifications yet.'),
                      ),
                    ),
                    icon: const Icon(Icons.notifications_outlined),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: _profileRef.snapshots(),
                builder: (context, profileSnap) {
                  final first = _orDefault(
                    profileSnap.data?.data()?['firstName'],
                    'user',
                  );
                  return Text(
                    '${_greeting()}, $first',
                    style: textTheme.headlineMedium,
                  );
                },
              ),
              const SizedBox(height: 12),

              // Pet selector: arrows scroll the row of chips
              Row(
                children: [
                  IconButton(
                    onPressed: () => _scrollChips(-140),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: _chipScroll,
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final d in docs)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(
                                  _orDefault(d.data()['name'], '(no name)'),
                                ),
                                selected: d.id == selected?.id,
                                onSelected: (_) =>
                                    setState(() => _selectedId = d.id),
                              ),
                            ),
                          ActionChip(
                            avatar: const Icon(Icons.add, size: 18),
                            label: const Text('Add pet'),
                            onPressed: _addPet,
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => _scrollChips(140),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              if (snap.hasError)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Could not load pets: ${snap.error}'),
                ),
              const SizedBox(height: 12),

              _PetCard(pet: selected),
              const SizedBox(height: 24),

              // Alerts
              Text('Alerts', style: textTheme.titleLarge),
              const SizedBox(height: 2),
              Text(
                'Sample alerts. Live ones arrive with the map in Milestone 2.',
                style: textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              for (final distance in const ['0.8 km', '1.4 km', '2.1 km'])
                _AlertTile(distance: distance, onMap: widget.onOpenMap),
            ],
          );
        },
      ),
    );
  }
}

class _PetCard extends StatelessWidget {
  const _PetCard({required this.pet});

  final PetDoc? pet;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final data = pet?.data();

    final name = _orDefault(data?['name'], '(no name)');
    final status = _orDefault(data?['status'], 'Safe');
    final battery = _orDefault(data?['battery'], '--');
    final updated = _timeAgo(data?['createdAt'] as Timestamp?);

    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Placeholder for the pet photo
            Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                color: scheme.outlineVariant,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.pets, size: 48),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: data == null
                  ? const Text(
                      'No pets yet. Tap "Add pet" to save your first one.',
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        _InfoRow(
                          icon: Icons.shield_outlined,
                          text: 'Status: $status',
                        ),
                        _InfoRow(
                          icon: Icons.battery_full,
                          text: 'Tracker battery: $battery',
                        ),
                        _InfoRow(
                          icon: Icons.update,
                          text: 'Last updated: $updated',
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlertTile extends StatelessWidget {
  const _AlertTile({required this.distance, required this.onMap});

  final String distance;
  final VoidCallback onMap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: scheme.outlineVariant,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.pets),
        ),
        title: const Text('Pet missing'),
        subtitle: Text(distance),
        trailing: FilledButton.tonal(
          onPressed: onMap,
          child: const Text('Map'),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Profile screen (matches the Profile wireframe)
// ---------------------------------------------------------------------------

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  Future<void> _removePet(BuildContext context, List<PetDoc> docs) async {
    if (docs.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No pets to remove.')));
      return;
    }

    // Step 1: pick which pet.
    final chosen = await showDialog<PetDoc>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Remove which pet?'),
        children: [
          for (final d in docs)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, d),
              child: Text(_orDefault(d.data()['name'], '(no name)')),
            ),
        ],
      ),
    );
    if (chosen == null || !context.mounted) return;

    // Step 2: confirm, because a delete cannot be undone.
    final name = _orDefault(chosen.data()['name'], '(no name)');
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove $name?'),
        content: const Text(
          'This deletes the pet from the cloud. It cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (sure != true) return;

    try {
      await chosen.reference.delete();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not remove: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return SafeArea(
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('pets')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snap) {
          final docs = snap.data?.docs ?? <PetDoc>[];

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: IconButton.filledTonal(
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('No new notifications yet.')),
                  ),
                  icon: const Icon(Icons.notifications_outlined),
                ),
              ),
              const Center(
                child: CircleAvatar(
                  radius: 56,
                  child: Icon(Icons.person, size: 56),
                ),
              ),
              const SizedBox(height: 12),
              const _AccountSection(),
              const SizedBox(height: 24),
              Text('Pets', style: textTheme.headlineSmall),
              const SizedBox(height: 8),
              if (snap.hasError) Text('Could not load pets: ${snap.error}'),
              if (docs.isEmpty && !snap.hasError)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('No pets yet. Tap "Add pet" below.'),
                ),
              for (final d in docs) _ProfilePetCard(pet: d),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _removePet(context, docs),
                    icon: const Icon(Icons.remove),
                    label: const Text('Remove pet'),
                  ),
                  FilledButton.icon(
                    onPressed: () => addPetFlow(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Add pet'),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ProfilePetCard extends StatelessWidget {
  const _ProfilePetCard({required this.pet});

  final PetDoc pet;

  Future<void> _toggleMissing(BuildContext context, bool isMissing) async {
    try {
      await pet.reference.update({'status': isMissing ? 'Safe' : 'Missing'});
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isMissing ? 'Marked as safe.' : 'Reported missing.'),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not update: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final data = pet.data();

    final name = _orDefault(data['name'], '(no name)');
    final type = _orDefault(data['type'], 'Not set');
    final address = _orDefault(data['address'], 'Not set');
    final isMissing = data['status'] == 'Missing';

    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Placeholder for the pet photo
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: scheme.outlineVariant,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.pets, size: 36),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      if (isMissing)
                        Text(
                          'MISSING',
                          style: TextStyle(
                            color: scheme.error,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                    ],
                  ),
                  _InfoRow(icon: Icons.category_outlined, text: type),
                  _InfoRow(icon: Icons.home_outlined, text: address),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.tonal(
                      onPressed: () => _toggleMissing(context, isMissing),
                      child: Text(
                        isMissing ? 'Mark as safe' : 'Report missing',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Account details (first name, last name, address, phone)
// ---------------------------------------------------------------------------

class _AccountSection extends StatelessWidget {
  const _AccountSection();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _profileRef.snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data();
        final name = _fullName(data);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Text(
                name.isEmpty ? 'Add your name' : name,
                style: textTheme.headlineSmall,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: Text('Account', style: textTheme.headlineSmall),
                ),
                TextButton.icon(
                  onPressed: () => editProfileFlow(context, data),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Edit'),
                ),
              ],
            ),
            Card(
              elevation: 0,
              color: scheme.surfaceContainerHighest,
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    _DetailRow(
                      label: 'First name',
                      value: _orDefault(data?['firstName'], 'Not set'),
                    ),
                    _DetailRow(
                      label: 'Last name',
                      value: _orDefault(data?['lastName'], 'Not set'),
                    ),
                    _DetailRow(
                      label: 'Address',
                      value: _orDefault(data?['address'], 'Not set'),
                    ),
                    _DetailRow(
                      label: 'Phone',
                      value: _orDefault(data?['phone'], 'Not set'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

/// Shows the account form, prefilled with [current], and saves the result.
Future<void> editProfileFlow(
  BuildContext context,
  Map<String, dynamic>? current,
) async {
  final result = await showDialog<Map<String, String>>(
    context: context,
    builder: (_) => _EditProfileDialog(current: current),
  );
  if (result == null) return;
  try {
    // merge: true changes only these fields and keeps anything else stored.
    await _profileRef.set(result, SetOptions(merge: true));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Account details saved.')));
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Could not save: $e')));
  }
}

class _EditProfileDialog extends StatefulWidget {
  const _EditProfileDialog({required this.current});

  final Map<String, dynamic>? current;

  @override
  State<_EditProfileDialog> createState() => _EditProfileDialogState();
}

class _EditProfileDialogState extends State<_EditProfileDialog> {
  late final _first = TextEditingController(
    text: _orDefault(widget.current?['firstName'], ''),
  );
  late final _last = TextEditingController(
    text: _orDefault(widget.current?['lastName'], ''),
  );
  late final _address = TextEditingController(
    text: _orDefault(widget.current?['address'], ''),
  );
  late final _phone = TextEditingController(
    text: _orDefault(widget.current?['phone'], ''),
  );

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _address.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.pop(context, {
      'firstName': _first.text.trim(),
      'lastName': _last.text.trim(),
      'address': _address.text.trim(),
      'phone': _phone.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Account details'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _first,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'First name'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _last,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Last name'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _address,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Address'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone number'),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Placeholder for screens that arrive in later milestones
// ---------------------------------------------------------------------------

class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({
    super.key,
    required this.icon,
    required this.title,
    required this.note,
  });

  final IconData icon;
  final String title;
  final String note;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 56),
              const SizedBox(height: 12),
              Text(title, style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text(note, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}
