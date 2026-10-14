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

## Réponses saisies dans la console le 14 oct. 2026 (formulaires remplis, ENREGISTREMENT final à faire par le propriétaire)
- **Classification du contenu** (catégorie « autres types d'applications », contact support@tratra.net) : contenu embarqué sensible = Non ; échange de contenu entre utilisateurs = OUI (messages, statuts) ; contenu utilisateur = source principale = Non ; partage public de nudité = Non ; de violence = Non ; blocage = Oui ; signalement = Oui ; modération = Oui ; interactions limitées aux contacts = Oui ; contenu en ligne (catalogue/profils) = Oui, sans violence/sexualité/langage/drogues ; produits soumis à l'âge = Non ; position précise partagée avec un autre utilisateur = OUI (suivi en direct consenti) ; achats numériques = Non ; récompenses/crypto = Non ; navigateur/moteur = Non ; actualités/éducation = Non.
- **Fonctionnalités financières** : « Paiements mobiles et portefeuilles numériques » (Orange Money, MTN MoMo, carte, portefeuille) ; aucun document demandé pour le moment.
- **Déjà enregistrées** : confidentialité, annonces (aucune), identifiant publicitaire (non), applis gouvernementales (non), applis de santé (aucune).

## Sécurité des données — réponses à saisir (non commencée)
Chiffrement en transit : oui. Suppression à la demande de l'utilisateur : oui (dans l'appli et https://tratra.net/suppression-compte). Aucune vente, aucune publicité ; les prestataires techniques (SMS, paiement, hébergement) agissent comme sous-traitants.
Données collectées (toutes facultatives = non, sauf mention) : nom, téléphone, e-mail (facultatif), identifiant de compte, adresses ; position approximative et précise (premier plan, avec accord) ; messages dans l'appli ; photos et vidéos ; documents (PDF, pièces d'identité des artisans) ; historique de transactions ; jeton de notification (identifiant d'appareil) ; journaux d'erreurs (diagnostics) ; images du visage pour la vérification faciale (facultative, consentie, 30 jours). Finalités : fonctionnement de l'appli, gestion du compte, prévention de la fraude et sécurité, communications.

## Informations de connexion (à faire par le propriétaire)
Compte de relecture : `python manage.py create_review_account` sur le serveur de production (après redéploiement de l'image). Saisir le numéro et le mot de passe affichés dans la console, avec la consigne « connexion par numéro de téléphone + mot de passe, aucun code SMS requis ».
