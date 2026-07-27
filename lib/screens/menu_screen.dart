import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/app_state.dart';
import '../widgets/widgets.dart';

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  final scroll = ScrollController();
  final filterScroll = ScrollController();
  final search = TextEditingController();
  String? selectedCategory;
  MenuSort sort = MenuSort.popularity;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<AppState>().loadMenu();
      }
    });
  }

  @override
  void dispose() {
    scroll.dispose();
    filterScroll.dispose();
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final store = state.selectedStore;
    final categories = state.menuCategories;
    final visibleCategories = _visibleCategories(categories);

    if (store == null) {
      return const Scaffold(
          body: Center(child: Text('Choose a restaurant first.')));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(store.name),
        actions: [
          IconButton(
              onPressed: () => state.loadMenu(force: true),
              icon: const Icon(Icons.refresh)),
          IconButton(
              onPressed: () => context.push('/account'),
              icon: const Icon(Icons.person_outline)),
        ],
      ),
      body: Column(
        children: [
          if (categories.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: search,
                          onChanged: (_) => setState(() {}),
                          textInputAction: TextInputAction.search,
                          decoration: const InputDecoration(
                            hintText: 'Search dishes...',
                            prefixIcon: Icon(Icons.search),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      PopupMenuButton<MenuSort>(
                        initialValue: sort,
                        onSelected: (value) => setState(() => sort = value),
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                            value: MenuSort.popularity,
                            child: Text('Popularity'),
                          ),
                          PopupMenuItem(
                            value: MenuSort.priceLow,
                            child: Text('Price: Low to High'),
                          ),
                          PopupMenuItem(
                            value: MenuSort.priceHigh,
                            child: Text('Price: High to Low'),
                          ),
                          PopupMenuItem(
                            value: MenuSort.name,
                            child: Text('Alphabetical'),
                          ),
                        ],
                        child: Container(
                          width: 158,
                          height: 48,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Theme.of(context)
                                  .colorScheme
                                  .outline
                                  .withValues(alpha: .65),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  sort.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800),
                                ),
                              ),
                              const Icon(Icons.keyboard_arrow_down),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 112),
                    child: Scrollbar(
                      controller: filterScroll,
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        controller: filterScroll,
                        padding: const EdgeInsets.only(right: 8),
                        child: Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            ChoiceChip(
                              label: const Text('All Items'),
                              selected: selectedCategory == null,
                              onSelected: (_) {
                                setState(() {
                                  selectedCategory = null;
                                });
                              },
                            ),
                            ...categories.map((category) {
                              final selected =
                                  selectedCategory == category.name;
                              return ChoiceChip(
                                label: Text(category.name),
                                selected: selected,
                                onSelected: (_) {
                                  setState(() {
                                    selectedCategory =
                                        selected ? null : category.name;
                                  });
                                },
                              );
                            }),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: state.menuLoading
                ? const LoadingCards()
                : state.menuError != null
                    ? _MenuError(
                        message: state.menuError!,
                        onRetry: () => state.loadMenu(force: true))
                    : visibleCategories.isEmpty
                        ? _NoMenuMatches(search: search.text)
                        : ListView(
                            controller: scroll,
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                            children: [
                              for (final category in visibleCategories) ...[
                                Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(4, 18, 4, 12),
                                  child: Text(category.name,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge),
                                ),
                                ...category.items.map((i) => MenuItemCard(
                                    item: i,
                                    onAdd: () => showItemSheet(context, i))),
                              ],
                            ],
                          ),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: state.itemCount == 0
          ? null
          : FilledButton.icon(
              style: FilledButton.styleFrom(
                  minimumSize: const Size(270, 56),
                  backgroundColor: Colors.black),
              onPressed: () => context.push('/cart'),
              icon: Badge(
                  label: Text('${state.itemCount}'),
                  child: const Icon(Icons.shopping_bag_outlined)),
              label: Text('View cart - ${currency.format(state.subtotal)}'),
            ),
    );
  }

  List<MenuCategory> _visibleCategories(List<MenuCategory> categories) {
    final query = search.text.trim().toLowerCase();
    final selected = selectedCategory;
    return categories
        .where((category) => selected == null || category.name == selected)
        .map((category) {
          var items = category.items;
          if (query.isNotEmpty) {
            items = items.where((item) {
              return item.name.toLowerCase().contains(query) ||
                  item.description.toLowerCase().contains(query);
            }).toList();
          }
          items = [...items]..sort(_compareMenuItems);
          return MenuCategory(category.name, items);
        })
        .where((category) => category.items.isNotEmpty)
        .toList();
  }

  int _compareMenuItems(MenuItem a, MenuItem b) {
    switch (sort) {
      case MenuSort.popularity:
        return (b.isPopular ? 1 : 0).compareTo(a.isPopular ? 1 : 0);
      case MenuSort.priceLow:
        return a.price.compareTo(b.price);
      case MenuSort.priceHigh:
        return b.price.compareTo(a.price);
      case MenuSort.name:
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    }
  }
}

enum MenuSort {
  popularity('Popularity'),
  priceLow('Price: Low'),
  priceHigh('Price: High'),
  name('Alphabetical');

  const MenuSort(this.label);

  final String label;
}

class _MenuError extends StatelessWidget {
  const _MenuError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off, size: 52),
            const SizedBox(height: 12),
            Text('Could not load the RMS menu',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry')),
          ]),
        ),
      );
}

class _NoMenuMatches extends StatelessWidget {
  const _NoMenuMatches({required this.search});

  final String search;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.search_off, size: 52),
              const SizedBox(height: 12),
              Text(
                'No dishes match your filters',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              if (search.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Try another search for "${search.trim()}".',
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      );
}

Future<void> showItemSheet(BuildContext context, MenuItem item) async {
  int qty = 1;
  final selections = <String, List<ModifierOption>>{};
  final instructions = TextEditingController();

  void initGroup(ModifierGroup group) {
    final defaults = group.options.where((option) => option.isDefault).toList();
    final selected = defaults.isNotEmpty
        ? defaults
        : group.required && group.maxSelection == 1 && group.options.isNotEmpty
            ? [group.options.first]
            : <ModifierOption>[];
    selections[group.id] = selected;
    for (final option in selected) {
      for (final childGroup in option.modifierGroups) {
        initGroup(childGroup);
      }
    }
  }

  for (final group in item.modifierGroups) {
    initGroup(group);
  }

  List<ModifierGroup> activeGroups() {
    final result = <ModifierGroup>[];
    final visited = <String>{};

    void collect(List<ModifierGroup> groups) {
      for (final group in groups) {
        if (!visited.add(group.id)) continue;
        result.add(group);
        for (final option in selections[group.id] ?? const <ModifierOption>[]) {
          collect(option.modifierGroups);
        }
      }
    }

    collect(item.modifierGroups);
    return result;
  }

  bool valid() => activeGroups().every((group) {
        final count = selections[group.id]?.length ?? 0;
        return count >= group.minSelection && count <= group.maxSelection;
      });

  double selectedPrice() => activeGroups().fold(0.0, (sum, group) {
        final options = selections[group.id] ?? const <ModifierOption>[];
        return sum + options.fold(0.0, (s, option) => s + option.price);
      });

  List<SelectedModifier> selectedModifiers() {
    final rootIds = item.modifierGroups.map((group) => group.id).toSet();
    return [
      for (final group in activeGroups())
        for (final option in selections[group.id] ?? const <ModifierOption>[])
          SelectedModifier(
            groupId: group.id,
            groupName: group.name,
            optionId: option.id,
            optionName: option.name,
            price: option.price,
            isRoot: rootIds.contains(group.id),
          )
    ];
  }

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => StatefulBuilder(builder: (context, setLocal) {
      final unit = item.price + selectedPrice();

      void toggle(ModifierGroup group, ModifierOption option) {
        final current = List<ModifierOption>.of(
            selections[group.id] ?? const <ModifierOption>[]);
        final exists = current.any((entry) => entry.id == option.id);
        List<ModifierOption> next;
        if (group.maxSelection == 1) {
          next = exists && !group.required ? <ModifierOption>[] : [option];
        } else if (exists) {
          next = current.where((entry) => entry.id != option.id).toList();
        } else if (current.length < group.maxSelection) {
          next = [...current, option];
        } else {
          return;
        }

        void initNested(ModifierOption option) {
          for (final childGroup in option.modifierGroups) {
            if (!selections.containsKey(childGroup.id)) initGroup(childGroup);
            for (final childOption
                in selections[childGroup.id] ?? const <ModifierOption>[]) {
              initNested(childOption);
            }
          }
        }

        setLocal(() {
          selections[group.id] = next;
          for (final selected in next) {
            initNested(selected);
          }
        });
      }

      Widget modifierGroup(ModifierGroup group) {
        final selected = selections[group.id] ?? const <ModifierOption>[];
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
                child: Text(group.name,
                    style: Theme.of(context).textTheme.titleMedium)),
            Text('${selected.length}/${group.maxSelection}',
                style: Theme.of(context).textTheme.bodySmall),
          ]),
          Wrap(
            spacing: 7,
            children: group.options.map((option) {
              final on = selected.any((entry) => entry.id == option.id);
              final price =
                  option.price > 0 ? ' +${currency.format(option.price)}' : '';
              return ChoiceChip(
                label: Text('${option.name}$price'),
                selected: on,
                onSelected: (_) => toggle(group, option),
              );
            }).toList(),
          ),
        ]);
      }

      return Padding(
        padding: EdgeInsets.fromLTRB(
            20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
        child: SingleChildScrollView(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.name,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w900)),
            Text(item.description),
            ...activeGroups().map(modifierGroup),
            const SizedBox(height: 18),
            TextField(
                controller: instructions,
                maxLines: 2,
                decoration: const InputDecoration(
                    labelText: 'Special instructions',
                    hintText: 'Example: sauce on the side')),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton.filledTonal(
                  onPressed: qty > 1 ? () => setLocal(() => qty--) : null,
                  icon: const Icon(Icons.remove)),
              Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text('$qty',
                      style: Theme.of(context).textTheme.titleLarge)),
              IconButton.filledTonal(
                  onPressed: () => setLocal(() => qty++),
                  icon: const Icon(Icons.add)),
            ]),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(
                  disabledBackgroundColor: Colors.grey.shade300),
              onPressed: !valid()
                  ? null
                  : () {
                      context.read<AppState>().add(
                            item,
                            qty,
                            selectedModifiers(),
                            instructions.text,
                            unit,
                          );
                      Navigator.pop(context);
                    },
              child: Text('Add to cart - ${currency.format(unit * qty)}'),
            ),
          ]),
        ),
      );
    }),
  );
  instructions.dispose();
}
