import 'package:flutter/material.dart';
import 'package:preconnect/pages/bus.dart';
import 'package:preconnect/pages/ui_kit.dart';

class BusRouteMap extends StatelessWidget {
  const BusRouteMap({super.key});

  @override
  Widget build(BuildContext context) {
    return BracuPageScaffold(
      title: 'Bus',
      subtitle: 'Route Map',
      icon: Icons.map_outlined,
      body: BracuRefreshList(
        onRefresh: () async {},
        children: [
          BracuCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Route map view is now integrated into the Bus page.',
                  style: TextStyle(
                    color: BracuPalette.textPrimary(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(
                      context,
                    ).push(MaterialPageRoute(builder: (_) => const BusPage()));
                  },
                  icon: const Icon(Icons.directions_bus_rounded),
                  label: const Text('Open Bus'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
