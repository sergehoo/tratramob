// screens/search_screen.dart
import 'package:flutter/material.dart';
import '../core/constants.dart';
import '../widgets/custom_app_bar.dart';
import '../widgets/artisan_card.dart';
import '../widgets/service_card.dart';
import '../models/artisan.dart';
import '../models/service.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  int _selectedCategory = 0;

  final List<String> _categories = [
    'Tous',
    'Plomberie',
    'Électricité',
    'Peinture',
    'Menuiserie',
    'Nettoyage',
  ];

  final List<Artisan> _artisans = []; // Remplir avec des données réelles
  final List<Service> _services = []; // Remplir avec des données réelles

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.backgroundColor,
      appBar: CustomAppBar(
        title: 'Recherche',
        showBackButton: true,
        leading: null,
      ),
      body: Column(
        children: [
          // Barre de recherche
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Rechercher un service ou un artisan...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),
          // Catégories
          SizedBox(
            height: 50,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _categories.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: ChoiceChip(
                    label: Text(_categories[index]),
                    selected: _selectedCategory == index,
                    onSelected: (selected) =>
                        setState(() => _selectedCategory = index),
                    selectedColor: AppConstants.primaryColor,
                    labelStyle: TextStyle(
                      color: _selectedCategory == index
                          ? Colors.white
                          : AppConstants.textPrimary,
                    ),
                  ),
                );
              },
            ),
          ),
          // Résultats
          Expanded(
            child: _searchQuery.isEmpty
                ? _buildRecentSearches()
                : _buildSearchResults(),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentSearches() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        Text('Recherches récentes',
            style: TextStyle(fontWeight: FontWeight.bold)),
        // Ajouter les recherches récentes
      ],
    );
  }

  Widget _buildSearchResults() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Artisans',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        const SizedBox(height: 16),
        SizedBox(
          height: 200,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _artisans.length,
            itemBuilder: (context, index) => ArtisanCard(
              artisan: _artisans[index],
              isFavorite: false,
              onFavoriteToggle: () {},
              onTap: () {},
            ),
          ),
        ),
        const SizedBox(height: 24),
        const Text('Services',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        const SizedBox(height: 16),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.8,
          ),
          itemCount: _services.length,
          itemBuilder: (context, index) => ServiceCard(
            service: _services[index],
            isFavorite: false,
            onFavoriteToggle: () {},
            onTap: () {},
          ),
        ),
      ],
    );
  }
}
