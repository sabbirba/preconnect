part of 'package:preconnect/pages/bus.dart';

class _OutboundTripsCard extends StatelessWidget {
  const _OutboundTripsCard({required this.outbound});

  final _BusOutbound outbound;

  @override
  Widget build(BuildContext context) {
    return _BusSectionFrame(
      icon: Icons.directions_bus_filled_rounded,
      title: 'Outbound Drop-offs',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (outbound.firstOutbound.isNotEmpty) ...[
            _TripGroupPanel(
              title: '1st Outbound',
              entries: outbound.firstOutbound,
            ),
            const SizedBox(height: 10),
          ],
          if (outbound.secondOutbound.isNotEmpty) ...[
            _TripGroupPanel(
              title: '2nd Outbound',
              entries: outbound.secondOutbound,
            ),
          ],
          if (outbound.firstOutbound.isEmpty && outbound.secondOutbound.isEmpty)
            _BusSectionEmptyText('No outbound drop-off data available.'),
        ],
      ),
    );
  }
}

class _FareCard extends StatelessWidget {
  const _FareCard({required this.fares});

  final List<_BusFare> fares;

  @override
  Widget build(BuildContext context) {
    final textPrimary = BracuPalette.textPrimary(context);
    return _BusSectionFrame(
      icon: Icons.payments_rounded,
      title: 'Fare',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...fares.asMap().entries.map(
            (entry) => _BusSectionSurface(
              margin: EdgeInsets.only(
                bottom: entry.key == fares.length - 1 ? 0 : 8,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fareLabel(entry.value.routeGroup),
                    style: TextStyle(
                      color: textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: _InfoChip(
                          icon: Icons.login_rounded,
                          text: 'Per: ${entry.value.amountPerTrip}',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _InfoChip(
                          icon: Icons.repeat_rounded,
                          text: 'Round: ${entry.value.roundTrip}',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (fares.isEmpty) _BusSectionEmptyText('No fare data available.'),
        ],
      ),
    );
  }
}

class _ContactsCard extends StatelessWidget {
  const _ContactsCard({required this.contacts});

  final List<_BusContact> contacts;

  @override
  Widget build(BuildContext context) {
    final textPrimary = BracuPalette.textPrimary(context);
    final textSecondary = BracuPalette.textSecondary(context);
    return _BusSectionFrame(
      icon: Icons.support_agent_rounded,
      title: 'Transport Contacts',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...contacts.asMap().entries.map(
            (entry) => _BusSectionSurface(
              margin: EdgeInsets.only(
                bottom: entry.key == contacts.length - 1 ? 0 : 8,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: BracuPalette.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.person_rounded,
                      size: 16,
                      color: BracuPalette.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.value.name,
                          style: TextStyle(
                            color: textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (entry.value.role.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              entry.value.role,
                              style: TextStyle(color: textSecondary),
                            ),
                          ),
                        if (entry.value.email.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: InkWell(
                              onTap: () =>
                                  openMailComposer(context, entry.value.email),
                              borderRadius: BorderRadius.circular(999),
                              child: _InfoChip(
                                iconWidget: const Icon(
                                  Icons.email_rounded,
                                  size: 12,
                                  color: BracuPalette.primary,
                                ),
                                text: entry.value.email,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (contacts.isEmpty)
            _BusSectionEmptyText('No contact data available.'),
        ],
      ),
    );
  }
}

class _GeneralInstructionsCard extends StatelessWidget {
  const _GeneralInstructionsCard({required this.instructions});

  final List<String> instructions;

  @override
  Widget build(BuildContext context) {
    final textSecondary = BracuPalette.textSecondary(context);
    return _BusSectionFrame(
      icon: Icons.rule_rounded,
      title: 'General Instructions',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...instructions.asMap().entries.map(
            (entry) => _BusSectionSurface(
              margin: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: BracuPalette.primary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${entry.key + 1}',
                      style: TextStyle(
                        color: BracuPalette.primary,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      entry.value,
                      style: TextStyle(
                        color: textSecondary,
                        fontSize: 14,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (instructions.isEmpty)
            _BusSectionEmptyText('No instruction data available.'),
        ],
      ),
    );
  }
}

class _TripGroupPanel extends StatelessWidget {
  const _TripGroupPanel({required this.title, required this.entries});

  final String title;
  final List<_BusDropoffEntry> entries;

  @override
  Widget build(BuildContext context) {
    final textPrimary = BracuPalette.textPrimary(context);
    final textSecondary = BracuPalette.textSecondary(context);
    return _BusSectionSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          ...entries.asMap().entries.map(
            (entry) => Padding(
              padding: EdgeInsets.only(
                bottom: entry.key == entries.length - 1 ? 0 : 8,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      entry.value.code.isEmpty
                          ? entry.value.route
                          : '${entry.value.route} (${entry.value.code})',
                      style: TextStyle(
                        color: textSecondary,
                        fontSize: 14,
                        height: 1.35,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _InfoChip(
                    icon: Icons.schedule_outlined,
                    text: entry.value.time,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BusSectionFrame extends StatelessWidget {
  const _BusSectionFrame({
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(icon: icon, title: title),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _BusSectionSurface extends StatelessWidget {
  const _BusSectionSurface({
    required this.child,
    this.margin = EdgeInsets.zero,
  });

  final Widget child;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: BracuPalette.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: child,
    );
  }
}

class _BusSectionEmptyText extends StatelessWidget {
  const _BusSectionEmptyText(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      style: TextStyle(color: BracuPalette.textSecondary(context)),
    );
  }
}
