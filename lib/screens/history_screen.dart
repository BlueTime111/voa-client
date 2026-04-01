/// 历史记录页面：展示输入文本历史，支持复制、删除与清空。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/app_provider.dart';
import '../utils/constants.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  static const String routeName = '/history';

  @override
  Widget build(BuildContext context) {
    final appProvider = context.watch<AppProvider>();
    final items = appProvider.history;
    final canClear = items.isNotEmpty;
    final topInset = MediaQuery.of(context).padding.top + kToolbarHeight + 10;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 66,
        centerTitle: true,
        leadingWidth: 72,
        title: const Text(
          '历史记录',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 22,
            letterSpacing: 0.2,
          ),
        ),
        leading: Align(
          alignment: Alignment.center,
          child: _TopBarActionButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: Icons.arrow_back_rounded,
            iconColor: Colors.white,
          ),
        ),
        actions: <Widget>[
          SizedBox(
            width: 72,
            child: Align(
              alignment: Alignment.center,
              child: _TopBarActionButton(
                onPressed: !canClear
                    ? null
                    : () async {
                        final shouldClear = await showDialog<bool>(
                          context: context,
                          builder: (dialogContext) {
                            return AlertDialog(
                              title: const Text('要清空全部历史吗？'),
                              content: const Text('清空后就无法恢复了。'),
                              actions: <Widget>[
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(dialogContext).pop(false),
                                  child: const Text('先不'),
                                ),
                                FilledButton(
                                  onPressed: () =>
                                      Navigator.of(dialogContext).pop(true),
                                  child: const Text('确认清空'),
                                ),
                              ],
                            );
                          },
                        );

                        if (shouldClear == true && context.mounted) {
                          await context.read<AppProvider>().clearHistory();
                        }
                      },
                icon: Icons.delete_sweep_rounded,
                iconColor: canClear
                    ? Colors.white.withOpacity(0.86)
                    : Colors.white.withOpacity(0.35),
                tooltip: '清空全部',
              ),
            ),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              Color(0xFF0A1E33),
              Color(0xFF05101F),
              Color(0xFF000000),
            ],
            stops: <double>[0.0, 0.55, 1.0],
          ),
        ),
        child: items.isEmpty
            ? _EmptyStateView()
            : ListView.separated(
                padding: EdgeInsets.fromLTRB(16, topInset, 16, 24),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final item = items[index];
                  final text = item.text.trim();

                  return Dismissible(
                    key: ValueKey<String>(item.id),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 24),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.75),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child:
                          const Icon(Icons.delete_rounded, color: Colors.white),
                    ),
                    onDismissed: (_) {
                      context.read<AppProvider>().removeConversation(item.id);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(18),
                        border:
                            Border.all(color: Colors.white.withOpacity(0.08)),
                      ),
                      child: ListTile(
                        contentPadding:
                            const EdgeInsets.fromLTRB(16, 14, 12, 14),
                        title: Text(
                          text,
                          softWrap: true,
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    height: 1.35,
                                  ),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            DateFormat('yyyy-MM-dd HH:mm')
                                .format(item.createdAt),
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: AppColors.navIcon,
                                    ),
                          ),
                        ),
                        trailing: IconButton(
                          tooltip: '复制文本',
                          icon: const Icon(Icons.copy_rounded,
                              color: Colors.white70),
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: text));
                            if (!context.mounted) {
                              return;
                            }
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('已复制')),
                            );
                          },
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _EmptyStateView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.history_rounded,
            size: 70,
            color: Colors.white.withOpacity(0.34),
          ),
          const SizedBox(height: 18),
          Text(
            '还没有历史记录',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.white.withOpacity(0.46),
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 10),
          Text(
            '先去首页发一条任务试试吧。',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white.withOpacity(0.34),
                  fontWeight: FontWeight.w500,
                ),
          ),
        ],
      ),
    );
  }
}

class _TopBarActionButton extends StatelessWidget {
  const _TopBarActionButton({
    required this.onPressed,
    required this.icon,
    required this.iconColor,
    this.tooltip,
  });

  final VoidCallback? onPressed;
  final IconData icon;
  final Color iconColor;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
        ),
        child: IconButton(
          onPressed: onPressed,
          icon: Icon(icon, color: iconColor, size: 27),
          tooltip: tooltip,
          splashRadius: 22,
          constraints: const BoxConstraints.tightFor(width: 48, height: 48),
          padding: EdgeInsets.zero,
        ),
      ),
    );
  }
}
