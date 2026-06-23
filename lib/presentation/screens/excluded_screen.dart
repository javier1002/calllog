import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/excluded_number.dart';
import '../../data/repositories/exclusions_repository.dart';
import '../../utils/debouncer.dart';
import '../../utils/text_normalizer.dart';
import '../widgets/action_bottom_sheet.dart';
import '../widgets/confirm_action_dialog.dart';
import '../widgets/empty_state.dart';
import '../widgets/top_search_header.dart';

class ExcludedScreen extends StatefulWidget {
  const ExcludedScreen({super.key});

  @override
  State<ExcludedScreen> createState() => _ExcludedScreenState();
}

class _ExcludedScreenState extends State<ExcludedScreen> {
  final ExclusionsRepository _repository = ExclusionsRepository();
  final TextEditingController _searchController = TextEditingController();
  final Debouncer _debouncer = Debouncer();

  List<ExcludedNumber> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _loadItems();
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _debouncer.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {});
    _debouncer.run(() => _loadItems(query: _searchController.text));
  }

  Future<void> _loadItems({String? query}) async {
    setState(() => _loading = true);
    final results = await _repository.search(query ?? _searchController.text);
    if (!mounted) return;
    setState(() {
      _items = results;
      _loading = false;
    });
  }

  Future<void> _handleMenu(String value) async {
    if (value == 'refresh') await _loadItems();
  }

  void _openRuleActions(ExcludedNumber item) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return ActionBottomSheet(
          title: item.numero,
          actions: [
            SheetAction(
              icon: Icons.remove_circle_outline_rounded,
              title: 'Quitar de excluidos',
              subtitle: 'Elimina esta regla de la tabla local.',
              isDestructive: true,
              onTap: () {
                Navigator.of(sheetContext).pop();
                _confirmRemove(item);
              },
            ),
            SheetAction(
              icon: Icons.close_rounded,
              title: 'Cancelar',
              onTap: () => Navigator.of(sheetContext).pop(),
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirmRemove(ExcludedNumber item) async {
    final id = item.id;
    if (id == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => ConfirmActionDialog(
        title: 'Quitar de excluidos',
        message:
            'Esta acción eliminará la regla local para ${item.numero}. Las llamadas futuras de este número o prefijo ya no serán filtradas por esta regla.',
        confirmText: 'Eliminar',
      ),
    );

    if (confirmed != true) return;
    await _repository.deleteById(id);
    await _loadItems();
    _showSnackBar('Regla eliminada de excluidos.');
  }

  Future<void> _openAddRuleSheet() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _AddExcludedSheet(repository: _repository),
    );

    if (created == true) {
      await _loadItems();
      _showSnackBar('Regla agregada a excluidos.');
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasQuery = _searchController.text.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddRuleSheet,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Agregar número o prefijo'),
      ),
      body: Column(
        children: [
          TopSearchHeader(
            title: 'Excluidos',
            searchController: _searchController,
            hintText: 'Buscar',
            onMenuSelected: _handleMenu,
            menuItems: const [
              PopupMenuItem(
                value: 'refresh',
                child: Text('Recargar'),
              ),
            ],
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadItems,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _items.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            SizedBox(
                              height: MediaQuery.sizeOf(context).height * 0.48,
                              child: EmptyState(
                                icon: hasQuery
                                    ? Icons.search_off_rounded
                                    : Icons.block_rounded,
                                title: hasQuery
                                    ? 'Sin resultados'
                                    : 'No hay reglas de exclusión',
                                message: hasQuery
                                    ? 'No se encontraron reglas que coincidan con tu búsqueda.'
                                    : 'Agrega números exactos o prefijos para omitirlos en futuras extracciones.',
                              ),
                            ),
                          ],
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(24, 8, 24, 112),
                          itemCount: _items.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 26),
                          itemBuilder: (context, index) {
                            final item = _items[index];
                            return _ExcludedCard(
                              item: item,
                              onTap: () => _openRuleActions(item),
                            );
                          },
                        ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExcludedCard extends StatelessWidget {
  const _ExcludedCard({
    required this.item,
    required this.onTap,
  });

  final ExcludedNumber item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.numero,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 30,
                height: 1.1,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Tipo: ${item.tipo.label}',
              style: const TextStyle(
                fontSize: 23,
                color: AppTheme.mutedText,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddExcludedSheet extends StatefulWidget {
  const _AddExcludedSheet({required this.repository});

  final ExclusionsRepository repository;

  @override
  State<_AddExcludedSheet> createState() => _AddExcludedSheetState();
}

class _AddExcludedSheetState extends State<_AddExcludedSheet> {
  final TextEditingController _numberController = TextEditingController();
  ExclusionType _selectedType = ExclusionType.exacto;
  String? _numberError;
  bool _saving = false;

  @override
  void dispose() {
    _numberController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final normalizedNumber = normalizeSpaces(_numberController.text);

    setState(() => _numberError = null);

    if (normalizedNumber.isEmpty) {
      setState(() => _numberError = 'Ingresa un número o prefijo.');
      return;
    }

    setState(() => _saving = true);
    final exists = await widget.repository.exists(
      numero: normalizedNumber,
      tipo: _selectedType,
    );

    if (!mounted) return;
    if (exists) {
      setState(() {
        _saving = false;
        _numberError = 'Ya existe una regla igual.';
      });
      return;
    }

    await widget.repository.insert(
      numero: normalizedNumber,
      tipo: _selectedType,
    );

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(24, 4, 24, bottomInset + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Agregar a excluidos',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _numberController,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                hintText: 'Número o prefijo',
                errorText: _numberError,
              ),
              onChanged: (_) {
                if (_numberError != null) setState(() => _numberError = null);
              },
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 24),
            const Text(
              'Tipo de exclusión',
              style: TextStyle(fontSize: 20, color: AppTheme.mutedText),
            ),
            const SizedBox(height: 8),
            RadioListTile<ExclusionType>(
              contentPadding: EdgeInsets.zero,
              value: ExclusionType.exacto,
              groupValue: _selectedType,
              onChanged: (value) {
                if (value != null) setState(() => _selectedType = value);
              },
              title: const Text(
                'Exacto',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              subtitle: const Text(
                'Solo se excluye el número completo ingresado.',
                style: TextStyle(color: AppTheme.mutedText),
              ),
            ),
            RadioListTile<ExclusionType>(
              contentPadding: EdgeInsets.zero,
              value: ExclusionType.prefijo,
              groupValue: _selectedType,
              onChanged: (value) {
                if (value != null) setState(() => _selectedType = value);
              },
              title: const Text(
                'Prefijo',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              subtitle: const Text(
                'Se excluyen los números que empiezan con este valor.',
                style: TextStyle(color: AppTheme.mutedText),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : () => Navigator.of(context).pop(false),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Agregar'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
