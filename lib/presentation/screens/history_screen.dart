import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/excluded_number.dart';
import '../../data/models/outgoing_call.dart';
import '../../data/repositories/call_sync_repository.dart';
import '../../data/repositories/calls_repository.dart';
import '../../data/repositories/exclusions_repository.dart';
import '../../utils/debouncer.dart';
import '../../utils/formatters.dart';
import '../../utils/text_normalizer.dart';
import '../widgets/action_bottom_sheet.dart';
import '../widgets/confirm_action_dialog.dart';
import '../widgets/empty_state.dart';
import '../widgets/top_search_header.dart';
import '../../services/call_sync_service.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  static const _channel = MethodChannel('registro_llamadas/call_log');

  final CallsRepository _callsRepository = CallsRepository();
  final ExclusionsRepository _exclusionsRepository = ExclusionsRepository();
  final CallSyncRepository _callSyncRepository = CallSyncRepository();
  final TextEditingController _searchController = TextEditingController();
  final Debouncer _debouncer = Debouncer();

  bool _syncingToCapsule = false;
  List<OutgoingCall> _calls = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _loadCalls();
    _checkLastSyncResult(); // ← lee el resultado del broker al abrir la app
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _debouncer.dispose();
    super.dispose();
  }

  /// Lee el resultado del último sync automático del worker y lo muestra
  Future<void> _checkLastSyncResult() async {
    try {
      final msg = await _channel.invokeMethod<String>('getLastSyncResult');
      if (msg != null && msg.isNotEmpty && mounted) {
        await Future.delayed(const Duration(milliseconds: 800));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            duration: const Duration(seconds: 6),
            backgroundColor: AppTheme.positive,
            behavior: SnackBarBehavior.floating,
          ),
        );
        // Recarga la lista para mostrar llamadas actualizadas
        await _loadCalls();
      }
    } catch (_) {}
  }

  void _onSearchChanged() {
    setState(() {});
    _debouncer.run(() => _loadCalls(query: _searchController.text));
  }

  Future<void> _loadCalls({String? query}) async {
    setState(() => _loading = true);
    final results = await _callsRepository.search(query ?? _searchController.text);
    if (!mounted) return;
    setState(() {
      _calls = results;
      _loading = false;
    });
  }

  Future<void> _handleMenu(String value) async {
    switch (value) {
      case 'sync_calls':
        await _syncOutgoingCalls();
        break;
      case 'sync_capsule':
        await _syncCallsToCapsule();
        break;
      case 'refresh':
        await _loadCalls();
        break;
      case 'clear_history':
        await _confirmClearHistory();
        break;
    }
  }

  Future<void> _syncOutgoingCalls() async {
    _showSnackBar('Sincronizando llamadas salientes...');
    try {
      final result = await _callSyncRepository.syncTodayOutgoingCalls();
      await _loadCalls();
      _showSnackBar(
        'Leídas: ${result.totalRead}. '
        'Guardadas: ${result.inserted}. '
        'Excluidas: ${result.skippedExcluded}. '
        'Duplicadas: ${result.skippedDuplicated}.',
      );
    } on PlatformException catch (error) {
      _showSnackBar(error.message ?? 'No se pudo leer el registro de llamadas.');
    } catch (error) {
      _showSnackBar(error.toString());
    }
  }

  Future<void> _syncCallsToCapsule() async {
    if (_syncingToCapsule) return;
    setState(() => _syncingToCapsule = true);
    try {
      final result = await CallSyncService.syncCalls();
      if (!mounted) return;
      _showSnackBar(
        '✅ Sincronización completada: '
        'Creadas ${result.creadas}, Omitidas ${result.omitidas}',
      );
      await _loadCalls();
    } catch (error) {
      if (!mounted) return;
      _showSnackBar('❌ Error sincronizando: $error');
    } finally {
      if (mounted) setState(() => _syncingToCapsule = false);
    }
  }

  Future<void> _confirmClearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const ConfirmActionDialog(
        title: 'Eliminar historial local',
        message:
            'Esta acción eliminará el historial local. No se eliminarán llamadas del registro de teléfono.',
        confirmText: 'Eliminar',
      ),
    );
    if (confirmed != true) return;
    await _callsRepository.clear();
    await _loadCalls();
    _showSnackBar('Historial local eliminado.');
  }

  void _openCallActions(OutgoingCall call) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return ActionBottomSheet(
          title: call.nombreContacto.isEmpty ? call.numero : call.nombreContacto,
          actions: [
            SheetAction(
              icon: Icons.delete_outline_rounded,
              title: 'Eliminar del historial local',
              subtitle: 'Solo borra este registro de SQLite.',
              isDestructive: true,
              onTap: () {
                Navigator.of(sheetContext).pop();
                _confirmDeleteCall(call);
              },
            ),
            SheetAction(
              icon: Icons.block_rounded,
              title: 'Excluir número',
              subtitle: 'Agrega el número como regla exacta.',
              onTap: () {
                Navigator.of(sheetContext).pop();
                _confirmExcludeCallNumber(call);
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

  Future<void> _confirmDeleteCall(OutgoingCall call) async {
    final id = call.id;
    if (id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const ConfirmActionDialog(
        title: 'Eliminar llamada',
        message:
            'Esta acción eliminará la llamada del historial local. No se eliminará del registro de teléfono.',
        confirmText: 'Eliminar',
      ),
    );
    if (confirmed != true) return;
    await _callsRepository.deleteById(id);
    await _loadCalls();
    _showSnackBar('Llamada eliminada del historial local.');
  }

  Future<void> _confirmExcludeCallNumber(OutgoingCall call) async {
    final numero = normalizeSpaces(call.numero);
    if (numero.isEmpty) {
      _showSnackBar('El número no es válido.');
      return;
    }
    final exists = await _exclusionsRepository.exists(
      numero: numero,
      tipo: ExclusionType.exacto,
    );
    if (!mounted) return;
    if (exists) {
      await showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(
          title: Text('Número ya excluido'),
          content: Text('Ya existe una regla exacta para este número.'),
        ),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => ConfirmActionDialog(
        title: 'Agregar a excluidos',
        message:
            'Esta acción guardará el número $numero en excluidos con tipo exacto. Las futuras extracciones podrán omitirlo.',
        confirmText: 'Agregar',
        isDestructive: false,
      ),
    );
    if (confirmed != true) return;
    await _exclusionsRepository.insert(
      numero: numero,
      tipo: ExclusionType.exacto,
    );
    _showSnackBar('Número agregado a excluidos.');
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

    return Column(
      children: [
        TopSearchHeader(
          title: 'Historial',
          searchController: _searchController,
          hintText: 'Buscar',
          onMenuSelected: _handleMenu,
          menuItems: [
            const PopupMenuItem(
              value: 'sync_calls',
              child: Text('Sincronizar llamadas del teléfono'),
            ),
            const PopupMenuItem(
              value: 'sync_capsule',
              child: Text(' Sincronizar con Capsule'),
            ),
            const PopupMenuItem(
              value: 'refresh',
              child: Text('Recargar'),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: 'clear_history',
              child: Text('Eliminar historial local'),
            ),
          ],
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadCalls,
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _calls.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(
                            height: MediaQuery.sizeOf(context).height * 0.48,
                            child: EmptyState(
                              icon: hasQuery
                                  ? Icons.search_off_rounded
                                  : Icons.call_made_rounded,
                              title: hasQuery
                                  ? 'Sin resultados'
                                  : 'No hay llamadas almacenadas',
                              message: hasQuery
                                  ? 'No se encontraron llamadas que coincidan con tu búsqueda.'
                                  : 'Cuando existan llamadas salientes guardadas localmente, aparecerán aquí.',
                            ),
                          ),
                        ],
                      )
                    : Stack(
                        children: [
                          ListView.separated(
                            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                            itemCount: _calls.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 26),
                            itemBuilder: (context, index) {
                              final call = _calls[index];
                              return _CallCard(
                                call: call,
                                onTap: () => _openCallActions(call),
                              );
                            },
                          ),
                          if (_syncingToCapsule)
                            Positioned(
                              bottom: 20,
                              left: 0,
                              right: 0,
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primary,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                        ),
                                      ),
                                      SizedBox(width: 12),
                                      Text(
                                        'Sincronizando con Capsule...',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
          ),
        ),
      ],
    );
  }
}

class _CallCard extends StatelessWidget {
  const _CallCard({required this.call, required this.onTap});

  final OutgoingCall call;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final statusStyle = _statusVisuals(call.estado);
    final title = call.nombreContacto.trim().isEmpty
        ? 'Sin nombre'
        : call.nombreContacto.trim();

    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 30,
                      height: 1.05,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    call.numero,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 26, color: Colors.white),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(statusStyle.icon, color: statusStyle.color, size: 25),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          call.estado,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                            color: statusStyle.color,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    formatDurationSeconds(call.duracion),
                    style: const TextStyle(fontSize: 22, color: Colors.white),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                formatCallDateOrTime(
                  fecha: call.fecha,
                  hora: call.hora,
                  timestamp: call.timestamp,
                ),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusVisuals {
  const _StatusVisuals(this.icon, this.color);
  final IconData icon;
  final Color color;
}

_StatusVisuals _statusVisuals(String status) {
  final normalized = status.toLowerCase();
  if (normalized.contains('respond') && !normalized.contains('no respond')) {
    return const _StatusVisuals(Icons.arrow_upward_rounded, AppTheme.positive);
  }
  if (normalized.contains('no respond') ||
      normalized.contains('rechaz') ||
      normalized.contains('bloque') ||
      normalized.contains('ocup') ||
      normalized.contains('perdid')) {
    return const _StatusVisuals(Icons.arrow_downward_rounded, AppTheme.danger);
  }
  return const _StatusVisuals(Icons.call_made_rounded, AppTheme.mutedText);
}