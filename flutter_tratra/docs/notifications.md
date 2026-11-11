# Notifications de l'application Tratra

Ce document décrit le comportement réel des notifications dans l'application Flutter, ce qui a été vérifié sur un téléphone, et
les limites imposées par Android et iOS. Côté serveur : `docs/push-fcm.md` du dépôt backend.

## 1. Qui affiche quoi

| État de l'application | Qui affiche | Forme |
|---|---|---|
| Ouverte (premier plan) | Dart — `lib/notifications/` | Ruban flottant en haut de l'écran |
| Ouverte, mission Flash | Dart — `FlashController` | Écran Tratra Flash plein écran, sonnerie dédiée |
| En arrière-plan ou fermée | Android (FCM) ou le code natif `FlashMessageReceiver` / `TratraAlerts` | Notification système |

Une seule source alimente le ruban : le message FCM reçu au premier plan. La WebSocket ne fait que mettre les écrans à jour,
elle n'affiche jamais de ruban. Le code natif n'affiche rien quand l'application est visible. Il n'existe donc qu'un affichage
par évènement.

## 2. Application ouverte : le ruban

Fichiers : `notice_center.dart` (file et règles), `notice_banner.dart` (affichage), `screen_presence.dart` (écran déjà ouvert).

- Contenu : icône de la catégorie, catégorie et heure réelle de l'évènement, titre, message, bouton fermer.
- Un ruban à la fois. Les suivants attendent dans une file de 5 au plus (350 ms entre deux rubans). Jamais de superposition.
- Disparition automatique après 5 secondes ; glisser vers le haut ou toucher la croix le ferme.
- Toucher le ruban ouvre l'écran concerné et marque la notification comme lue.
- Tratra Flash (contre-offre, reprise de recherche, attribution) passe devant la file et remplace le ruban ordinaire en cours,
  qui est rejoué ensuite. Ruban sombre, signal sonore dédié.
- Catégories discrètes (annonces, conseils, informations, avis) : ruban sans signal sonore.
- Rien n'est affiché pour un objet déjà à l'écran (conversation ouverte, demande suivie) ni par-dessus l'écran Tratra Flash :
  les rubans attendent la fin de la décision.
- Un ruban resté plus de 2 minutes en attente n'est plus affiché. Il reste dans le centre de notifications.

### Dédoublonnage

Chaque message porte une clé d'évènement, dans cet ordre : `eid` (évènement), `nid` (numéro de la notification côté serveur),
identifiant d'annonce, identifiant du message FCM. Une clé déjà vue n'est jamais réaffichée, y compris quand la notification
système du même évènement a été touchée.

## 3. Missions Flash

- Application ouverte : écran plein écran, sonnerie `tratra_flash` et vibration selon les réglages de l'application et le mode
  du téléphone. En mode silencieux, l'écran l'indique.
- Application en arrière-plan ou fermée : alerte système avec compte à rebours et les actions Accepter, Refuser, Voir.
- Le compte à rebours est calé sur l'échéance du serveur, pas sur l'heure de réception.
- Mission attribuée à un autre, annulée ou expirée : l'alerte système est retirée, l'écran ouvert affiche que la mission n'est
  plus disponible et ne propose plus que « Fermer ». Le serveur refuse de toute façon une acceptation hors délai.

## 4. Arrière-plan, application fermée, démarrage à froid

- Les notifications arrivent par FCM, que le processus tourne ou non.
- Un appui lance Tratra et ouvre le contenu ciblé. Si la navigation n'est pas encore prête (démarrage à froid, session en cours
  de restauration, écran Flash ouvert), l'appui est gardé 5 minutes au plus puis exécuté dès que possible. Passé ce délai il
  est abandonné : on n'ouvre pas un écran longtemps après le geste.
- Un même appui remis deux fois (lancement à froid) n'est exécuté qu'une fois.
- Sans session, l'appui mène à la connexion, jamais à un contenu privé.

## 5. Notifications manquées

Le centre de notifications interne est la référence : il liste tout ce que le serveur a émis, que le téléphone l'ait reçu ou
non. La pastille de la cloche et la liste sont relues au retour dans l'application et à chaque arrivée.

## 6. Écran verrouillé

- Paiements et messages : texte neutre (« Nouveau message », sans contenu).
- Missions Flash, propositions et contre-offres : la version publique ne montre que « Nouvelle mission Tratra » ; le détail
  n'apparaît qu'une fois le téléphone déverrouillé (visibilité `PRIVATE`).
- Limite : Android n'applique la version publique que si l'utilisateur a choisi de masquer le contenu sensible sur l'écran
  verrouillé. S'il a choisi de tout afficher, le texte des propositions est visible. Les textes neutres, eux, le restent.

## 7. Permissions, canaux, jetons

- Android 13 et plus : la permission est demandée une fois. Après un refus, Android n'affiche plus la demande : l'application
  montre « Notifications désactivées sur ce téléphone » avec un bouton qui ouvre les réglages de notification de Tratra. Au
  retour, la permission est relue et le message disparaît.
- Android 12 et moins : pas de demande ; l'utilisateur peut couper les notifications dans les réglages, même message.
- Notifications coupées : le ruban dans l'application et le centre de notifications continuent de fonctionner.
- Canaux Android : `tratra_activity` (réservations, messages, suivi — priorité haute, son `tratra_notification`),
  `tratra_new_missions` et ses variantes son seul / vibreur seul / silencieux (missions — priorité haute, son `tratra_flash`),
  `tratra_updates` et `tratra_announcements` (priorité normale). Android ne permet pas de modifier le son d'un canal déjà créé :
  un changement de son demande un nouveau canal.
- Jeton FCM : enregistré à la connexion, renouvelé par `onTokenRefresh`, relu à chaque retour dans l'application, retiré à la
  déconnexion.

## 8. Limites connues

### Android

- **Application arrêtée de force** (Paramètres → Forcer l'arrêt, ou certains « nettoyeurs ») : Android ne remet plus aucun
  message à l'application tant que l'utilisateur ne l'a pas rouverte. Aucun contournement n'existe ni ne doit être tenté. Vérifié :
  aucun affichage pendant l'arrêt ; à la réouverture, la pastille et le centre de notifications montrent ce qui a été manqué. Un
  message encore en attente chez FCM peut arriver à ce moment-là : il est affiché en ruban avec son heure réelle s'il a moins de
  2 minutes, sinon seulement dans le centre.
- Fermer l'application depuis les applications récentes n'est pas un arrêt de force sur Android standard : les notifications
  arrivent. Certains constructeurs (Xiaomi, Huawei, Oppo, Tecno, Infinix, parfois Samsung) traitent ce geste comme un arrêt de
  force ou brident l'application en veille : l'utilisateur doit alors exclure Tratra de l'optimisation de batterie.
- Mode économie d'énergie et Doze : les messages de priorité normale peuvent être retardés. Les missions Flash partent en
  priorité haute, mais Android peut rétrograder une application qui abuse de cette priorité.
- Le compte à rebours de l'alerte système utilise l'horloge du téléphone : une horloge fausse décale l'affichage, pas la
  décision, que le serveur tranche. L'écran de l'application, lui, se cale sur l'heure du serveur.
- Mode silencieux ou vibreur : respecté. Une mission Flash ne sonne pas sur un téléphone en silencieux.
- Les messages de données reçus application fermée sont traités par le code natif ; aucun code Dart ne tourne en arrière-plan.
- Un message arrivé pendant le démarrage de l'application n'est pas affiché en ruban ; il est dans le centre.

### iOS

- Non configuré et non testé : il manque la clé APNs dans Firebase, la capacité Push Notifications et un appareil réel (le
  simulateur ne reçoit pas les notifications distantes).
- L'alerte Flash native (compte à rebours, actions) n'existe que sur Android. Sur iOS il faudra une notification classique,
  et une extension de service pour les images.
- Une application fermée depuis le sélecteur d'applications ne reçoit plus les messages de données silencieux ; seules les
  notifications visibles sont remises.
- Le bouton « Ouvrir les réglages » n'est proposé que sur Android.

## 9. Validation réalisée

Galaxy S10+ (Android 12), copie de recette `com.tratra.recette`, serveur local jetable, vrais envois FCM vers cette seule copie.

| Cas | Ouverte | Arrière-plan | Fermée |
|---|---|---|---|
| Notification normale | Ruban, appui → réservation | Notification système, appui → réservation | Reçue, appui → démarrage à froid → réservation |
| Message | Ruban, appui → conversation ; rien si la conversation est ouverte | — | Texte neutre, appui → conversation |
| Mission Flash | Écran plein écran, compte à rebours conforme au serveur | Alerte avec compte à rebours et actions | Alerte, ouverture → écran de la mission |
| Contre-offre | Ruban prioritaire, appui → écran de la contre-offre | Notification privée, appui → même écran | — |
| Désistement | Ruban « Recherche reprise » avant les rubans en attente | Appui → recherche reprise | — |
| Annulation | Écran « Cette mission n'est plus disponible » | Alerte retirée | — |
| Expiration | « Le délai de réponse est écoulé », « Fermer » seul | Alerte retirée à l'échéance | — |

Aussi vérifié : même message rejoué → un seul ruban ; trois messages d'affilée → un par un, dans l'ordre ; arrêt de force ;
notifications coupées dans les réglages puis rétablies.

Non vérifié sur ce téléphone :

- le son et la vibration à l'oreille (téléphone en mode silencieux) : seuls les canaux et leurs sons ont été contrôlés ;
- un appui au doigt sur l'alerte Flash dans le volet : l'alerte a été ouverte par sa propre intention ;
- l'écran verrouillé à l'œil : contrôlé par la visibilité déclarée des notifications ;
- la demande de permission d'Android 13 ;
- iOS.

## 10. Tests automatiques

`test/notice_center_test.dart` (file, priorité, dédoublonnage, expiration, écran déjà ouvert, appui), `test/push_test.dart`
(permission, jeton, renouvellement, appui avant la navigation), `test/notification_links_test.dart` (liens acceptés).
