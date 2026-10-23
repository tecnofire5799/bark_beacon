import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';

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
// Shell: bottom bar with Home / Map / Radar, as in the wireframe
// ---------------------------------------------------------------------------

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0;

  void _goTo(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // IndexedStack keeps every tab alive, so Home keeps its state.
      body: IndexedStack(
        index: _index,
        children: [
          HomeScreen(onOpenMap: () => _goTo(1)),
          const PlaceholderScreen(
            icon: Icons.map,
            title: 'Map',
            note: 'Coming in Milestone 2: your location and Lost Pet markers.',
          ),
          const PlaceholderScreen(
            icon: Icons.radar,
            title: 'Radar',
            note:
                'Coming in Milestone 3: Bluetooth signal strength and compass.',
          ),
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
    );
  }
}

// ---------------------------------------------------------------------------
// Home screen (matches the wireframe)
// ---------------------------------------------------------------------------

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.onOpenMap});

  final VoidCallback onOpenMap;

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
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add a pet'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Pet name'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      final ref = await _pets.add({
        'name': name,
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      setState(() => _selectedId = ref.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return SafeArea(
      // One stream feeds both the pet selector and the pet card.
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _pets.orderBy('createdAt', descending: true).snapshots(),
        builder: (context, snap) {
          final docs =
              snap.data?.docs ??
              <QueryDocumentSnapshot<Map<String, dynamic>>>[];

          QueryDocumentSnapshot<Map<String, dynamic>>? selected;
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
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ProfileScreen()),
                    ),
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
              Text('${_greeting()}, user', style: textTheme.headlineMedium),
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
                                  (d.data()['name'] as String?) ?? '(no name)',
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

// ---------------------------------------------------------------------------
// Pieces used by the Home screen
// ---------------------------------------------------------------------------

String _timeAgo(Timestamp? ts) {
  // A just-saved document has no server time yet, so ts can be null.
  if (ts == null) return 'just now';
  final diff = DateTime.now().difference(ts.toDate());
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  return '${diff.inDays} d ago';
}

class _PetCard extends StatelessWidget {
  const _PetCard({required this.pet});

  final QueryDocumentSnapshot<Map<String, dynamic>>? pet;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final data = pet?.data();

    final name = (data?['name'] as String?) ?? '(no name)';
    final status = (data?['status'] as String?) ?? 'Safe';
    final battery = (data?['battery'] as String?) ?? '--';
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
// Profile screen: opened by tapping the avatar on Home
// ---------------------------------------------------------------------------

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CircleAvatar(radius: 36, child: Icon(Icons.person, size: 36)),
            const SizedBox(height: 12),
            Text(
              'Your profile',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 4),
            const Text('Owner name goes here'),
            const SizedBox(height: 24),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance.collection('pets').snapshots(),
              builder: (context, snap) {
                final n = snap.data?.docs.length ?? 0;
                return Text(
                  'Pets saved to the cloud: $n',
                  style: Theme.of(context).textTheme.titleMedium,
                );
              },
            ),
          ],
        ),
      ),
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
