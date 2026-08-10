import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Un ítem de [AppBottomNavigationBar]: ícono outline para inactivo, filled para activo (§7.6).
@immutable
class NavItem {
  const NavItem({required this.label, required this.icon, required this.selectedIcon});

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// §7.6 — navegación inferior, componente único y reutilizable configurado con una lista de
/// ítems según el rol (§7.6.1 Profesional, §7.6.2 Cliente) — mismo estilo visual (fondo
/// `surface`, ítem activo en `primary` con ícono filled + label, ítems inactivos en
/// `textSecondary` con ícono outline), con conjuntos de ítems distintos por rol.
class AppBottomNavigationBar extends StatelessWidget {
  const AppBottomNavigationBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
  });

  final List<NavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  /// §7.6.1 — 6 ítems, tal como en las capturas reales (orden confirmado en §12.2).
  static const List<NavItem> profesionalItems = [
    NavItem(label: 'Dashboard', icon: Icons.dashboard_outlined, selectedIcon: Icons.dashboard),
    NavItem(label: 'Horarios', icon: Icons.schedule_outlined, selectedIcon: Icons.schedule),
    NavItem(label: 'Pacientes', icon: Icons.people_outline, selectedIcon: Icons.people),
    NavItem(label: 'WhatsApp', icon: Icons.chat_bubble_outline, selectedIcon: Icons.chat_bubble),
    NavItem(label: 'Notificaciones', icon: Icons.notifications_outlined, selectedIcon: Icons.notifications),
    NavItem(label: 'Configuración', icon: Icons.settings_outlined, selectedIcon: Icons.settings),
  ];

  /// §7.6.2 — 4 ítems, decisión de UX/UI para mantener coherencia visual con el lado
  /// Profesional (las capturas del CEO no cubrían el lado Cliente).
  static const List<NavItem> clienteItems = [
    NavItem(label: 'Buscar', icon: Icons.search, selectedIcon: Icons.search),
    NavItem(label: 'Mis Turnos', icon: Icons.calendar_today_outlined, selectedIcon: Icons.calendar_today),
    NavItem(label: 'Notificaciones', icon: Icons.notifications_outlined, selectedIcon: Icons.notifications),
    NavItem(label: 'Configuración', icon: Icons.settings_outlined, selectedIcon: Icons.settings),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return NavigationBar(
      selectedIndex: currentIndex,
      onDestinationSelected: onTap,
      backgroundColor: colors.surface,
      indicatorColor: colors.primaryContainer,
      elevation: 0,
      destinations: [
        for (final item in items)
          NavigationDestination(
            icon: Icon(item.icon, color: colors.textSecondary),
            selectedIcon: Icon(item.selectedIcon, color: colors.primary),
            label: item.label,
          ),
      ],
    );
  }
}
