# Publication Google Play — Tratra (`com.tratra`)

Compte développeur : Serge OGAH (personnel). Piste de départ : Test interne. Bundle : `tool/build_play_aab.sh --build N` (clé d'upload hors Git : `~/.tratra-play/`).

## Éléments de la fiche (français — fr-FR)
- Nom : `Tratra` — icône `icon-512.png` — image de présentation `feature-graphic-1024x500.png`.
- Description courte : `description-courte.txt` (≤ 80 car.) ; description complète : `description-complete.txt` (≤ 4000 car.).
- Captures téléphone (9:16, 1350×2400) : `screenshots/`. Prises sur l'émulateur Pixel 8 avec la base de recette locale (comptes de test) : à REMPLACER par des écrans de production quand des données réelles existent.
- E-mail d'assistance : support@tratra.net — site : https://tratra.net — confidentialité : https://tratra.net/confidentialite — suppression de compte : https://tratra.net/suppression-compte (à déployer avant l'examen).

## Note de version (v1.0.0, build 2)
> Première version de Tratra : trouvez des artisans de confiance près de chez vous, réservez, échangez par messages et suivez vos interventions. Vous pouvez supprimer votre compte à tout moment depuis Profil → Supprimer mon compte.

## Réponses prévues aux déclarations (à confirmer par le propriétaire avant envoi)
| Déclaration | Réponse |
|---|---|
| Règles de confidentialité | https://tratra.net/confidentialite |
| Annonces | Aucune publicité |
| Accès à l'appli | Compte requis (téléphone + mot de passe) : fournir un compte de test dédié aux relecteurs |
| Classification du contenu | Questionnaire « utilitaire / mise en relation » : pas de violence, pas de contenu sexuel, pas de jeux d'argent ; messagerie entre utilisateurs = contenu généré par les utilisateurs |
| Public cible | 18 ans et plus |
| Sécurité des données | Collecte : nom, téléphone, e-mail (facultatif), localisation approximative/précise (au premier plan, avec accord), photos/vidéos, messages, pièces d'identité (artisans), identifiants d'appareil (jeton de notification), historique des transactions. Chiffré en transit ; suppression possible par l'utilisateur (URL ci-dessus) ; aucune vente de données |
| Application gouvernementale / santé / COVID / actualités | Non |
| Fonctionnalités financières | Non (réservations et paiements entre membres, pas d'opérations bancaires ni de prêt dans l'appli) — à vérifier selon l'offre de retrait/portefeuille |
| Permissions | Localisation (premier plan), appareil photo, notifications ; pas de micro, pas de galerie complète |

## Avant la production
Play exige un test fermé (≥ 12 testeurs pendant 14 jours, compte personnel) puis une demande d'accès à la production. Le backend (migrations `handy` 0049, statuts, messagerie, biométrie) doit être déployé AVANT d'ouvrir l'application à des testeurs, sinon les nouveaux écrans reçoivent des 404.
