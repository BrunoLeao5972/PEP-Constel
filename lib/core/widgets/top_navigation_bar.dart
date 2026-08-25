import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_colors.dart';
import '../config/theme_mode_provider.dart';

class TopNavigationBar extends ConsumerWidget {
  final String activeTab;
  final Function(String) onTabChanged;
  final bool isCollapsed;
  final VoidCallback onToggleCollapse;
  final String userName;
  final VoidCallback onLogout;

  const TopNavigationBar({
    super.key,
    required this.activeTab,
    required this.onTabChanged,
    required this.isCollapsed,
    required this.onToggleCollapse,
    this.userName = '',
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sidebarWidth = isCollapsed ? 88.0 : 290.0;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: sidebarWidth,
      decoration: BoxDecoration(
        color: context.colors.cardColor,
        border: Border(
          right: BorderSide(color: context.colors.borderColor, width: 1),
        ),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
              child: isCollapsed
                  ? Column(
                      children: [
                        Icon(
                          Icons.auto_awesome,
                          color: context.colors.accentColor,
                          size: 28,
                        ),
                        const SizedBox(height: 8),
                        IconButton(
                          onPressed: onToggleCollapse,
                          constraints: const BoxConstraints.tightFor(
                            width: 32,
                            height: 32,
                          ),
                          padding: EdgeInsets.zero,
                          iconSize: 20,
                          icon: Icon(
                            Icons.chevron_right,
                            color: context.colors.textSecondaryColor,
                          ),
                          tooltip: 'Expandir menu',
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Icon(Icons.auto_awesome,
                            color: context.colors.accentColor, size: 28),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'PEP Constel',
                            style: TextStyle(
                              color: context.colors.textColor,
                              fontWeight: FontWeight.w700,
                              fontSize: 22,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          onPressed: onToggleCollapse,
                          icon: Icon(
                            Icons.chevron_left,
                            color: context.colors.textSecondaryColor,
                          ),
                          tooltip: 'Recolher menu',
                        ),
                      ],
                    ),
            ),
            Divider(height: 1, color: context.colors.borderColor),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildSectionTitle(context, 'MENU PRINCIPAL'),
                    _buildTab(context, 'Administrativo',
                        Icons.dashboard_outlined, 'admin'),
                    _buildTab(
                        context, 'Cozinha', Icons.restaurant_menu, 'cozinha'),
                    _buildTab(context, 'Painel', Icons.tv_outlined, 'painel'),
                    _buildTab(context, 'Configurações', Icons.settings_outlined,
                        'config'),
                  ],
                ),
              ),
            ),
            Divider(height: 1, color: context.colors.borderColor),
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isCollapsed ? 10 : 14,
                vertical: 6,
              ),
              child: Row(
                mainAxisAlignment: isCollapsed
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.start,
                children: [
                  IconButton(
                    icon: Icon(
                      isDark
                          ? Icons.light_mode_outlined
                          : Icons.dark_mode_outlined,
                      color: context.colors.textSecondaryColor,
                    ),
                    onPressed: () =>
                        ref.read(themeModeProvider.notifier).toggle(),
                    tooltip: isDark ? 'Modo claro' : 'Modo escuro',
                  ),
                  if (!isCollapsed)
                    Text(
                      isDark ? 'Modo claro' : 'Modo escuro',
                      style: TextStyle(
                          color: context.colors.textSecondaryColor,
                          fontWeight: FontWeight.w500),
                    ),
                ],
              ),
            ),
            Divider(height: 1, color: context.colors.borderColor),
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isCollapsed ? 10 : 14,
                vertical: 10,
              ),
              child: Row(
                mainAxisAlignment: isCollapsed
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.spaceBetween,
                children: [
                  if (!isCollapsed)
                    Expanded(
                      child: Text(
                        userName.isNotEmpty ? userName : 'Usuário',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.colors.textSecondaryColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  IconButton(
                    icon: Icon(Icons.logout,
                        color: context.colors.textSecondaryColor),
                    onPressed: onLogout,
                    tooltip: 'Sair',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    if (isCollapsed) {
      return const SizedBox(height: 6);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          color: context.colors.textSecondaryColor,
          letterSpacing: 1.1,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildTab(
      BuildContext context, String label, IconData icon, String tabId) {
    final isActive = activeTab == tabId;

    return _buildItem(
      context,
      label: label,
      icon: icon,
      isActive: isActive,
      onTap: () => onTabChanged(tabId),
    );
  }

  Widget _buildItem(
    BuildContext context, {
    required String label,
    required IconData icon,
    required bool isActive,
    required VoidCallback? onTap,
  }) {
    final itemContent = Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      padding: EdgeInsets.symmetric(
        horizontal: isCollapsed ? 10 : 12,
        vertical: 11,
      ),
      decoration: BoxDecoration(
        color: isActive
            ? context.colors.accentColor.withValues(alpha: 0.18)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment:
            isCollapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 20,
            color: isActive
                ? context.colors.accentColor
                : context.colors.textSecondaryColor,
          ),
          if (!isCollapsed) ...[
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: isActive
                      ? context.colors.textColor
                      : context.colors.textSecondaryColor,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 16,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );

    final result = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: itemContent,
    );

    if (isCollapsed) {
      return Tooltip(message: label, child: result);
    }

    return result;
  }
}
