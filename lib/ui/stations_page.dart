import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'catalog.dart';
import 'favourites.dart';

/// Stations: the glass's tabs — Favourites · Top · Countries · Genres · Search (the web's
/// StationsPage). Favourites edit the list on the streamer; the others are the catalogue.
class StationsPage extends StatelessWidget {
  const StationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l.pageStations),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: l.stTabFav),
              Tab(text: l.stTabTop),
              Tab(text: l.stTabCountries),
              Tab(text: l.stTabGenres),
              Tab(text: l.stTabSearch),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            FavouritesTab(),
            CatalogPage(tab: CatalogTab.top),
            CatalogPage(tab: CatalogTab.countries),
            CatalogPage(tab: CatalogTab.genres),
            CatalogPage(tab: CatalogTab.search),
          ],
        ),
      ),
    );
  }
}
