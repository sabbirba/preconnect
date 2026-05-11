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
          BracuActionCard(
            title: 'Open Bus',
            leadingIcon: Icons.directions_bus_rounded,
            onTap: () {
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const BusPage()));
            },
          ),
        ],
      ),
    );
  }
}
