# Règles R8 propres à Tratra, ajoutées par le plugin Gradle de Flutter après proguard-android-optimize.txt et ses propres règles.
#
# Regroupe dans un seul paquet les classes que R8 renomme (recommandation Google Play « optimisation R8 », comportement par défaut
# d'AGP 9) : DEX plus petit et chargement plus rapide. Les classes conservées par une règle -keep (plugins, Firebase, code appelé par
# réflexion) ne sont jamais déplacées.
-repackageclasses
