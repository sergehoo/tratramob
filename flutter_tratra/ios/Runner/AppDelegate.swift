import AVFoundation
import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var flashChannel: FlutterMethodChannel?
  /// Action d'une notification Tratra Flash qui a lancé l'application : remise à Dart à sa demande (une seule fois).
  private var pendingFlashAction: [String: Any]?
  private var player: AVAudioPlayer?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    registerFlashCategory()
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(name: "tratra/flash", binaryMessenger: controller.binaryMessenger)
      channel.setMethodCallHandler { [weak self] call, result in self?.handle(call, result: result) }
      flashChannel = channel
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// Nouvelles missions : actions Accepter / Refuser / Voir. Toutes ouvrent l'application (session authentifiée, appareil déverrouillé) :
  /// aucune réponse n'est envoyée depuis l'écran verrouillé.
  private func registerFlashCategory() {
    let accept = UNNotificationAction(identifier: "ACCEPT", title: "Accepter", options: [.foreground, .authenticationRequired])
    let decline = UNNotificationAction(identifier: "DECLINE", title: "Refuser", options: [.foreground, .authenticationRequired])
    let view = UNNotificationAction(identifier: "VIEW", title: "Voir", options: [.foreground])
    let category = UNNotificationCategory(identifier: "NEW_MISSION", actions: [accept, decline, view], intentIdentifiers: [],
                                          hiddenPreviewsBodyPlaceholder: "Nouvelle mission Tratra", options: [])
    UNUserNotificationCenter.current().setNotificationCategories([category])
  }

  override func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                       withCompletionHandler completionHandler: @escaping () -> Void) {
    let info = response.notification.request.content.userInfo
    let action: String? = switch response.actionIdentifier {
      case "ACCEPT": "accept"
      case "DECLINE": "decline"
      case "VIEW": "view"
      default: nil
    }
    if let action = action, (info["t"] as? String) == "new_mission", let raw = info["id"], let offer = Int("\(raw)") {
      let payload: [String: Any] = ["action": action, "offer": offer]
      // Lancement à froid : Dart n'écoute pas encore → gardée pour `takeLaunchAction`. Application ouverte : remise tout de suite.
      // Dart ignore un éventuel doublon (même action, même proposition).
      pendingFlashAction = payload
      flashChannel?.invokeMethod("onAction", arguments: payload)
      completionHandler()
      return
    }
    super.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)
  }

  private func handle(_ call: FlutterMethodCall, result: FlutterResult) {
    let defaults = UserDefaults.standard
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "takeLaunchAction":
      result(pendingFlashAction)
      pendingFlashAction = nil
    case "getPrefs":
      result(["sound": defaults.object(forKey: "tratra_flash_sound") as? Bool ?? true,
              "vibration": defaults.object(forKey: "tratra_flash_vibration") as? Bool ?? true])
    case "setPrefs":
      defaults.set(args["sound"] as? Bool ?? true, forKey: "tratra_flash_sound")
      defaults.set(args["vibration"] as? Bool ?? true, forKey: "tratra_flash_vibration")
      result(true)
    case "play":
      result(play(sound: args["sound"] as? String ?? "tratra_flash", withSound: args["withSound"] as? Bool ?? true,
                  withVibration: args["withVibration"] as? Bool ?? true))
    case "stop":
      player?.stop()
      player = nil
      result(true)
    case "cancel":
      if let offer = args["offer"] as? Int { removeDelivered(offer: offer) }
      result(true)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Catégorie « ambiante » : le commutateur silencieux de l'iPhone est respecté (aucun son en mode silencieux).
  private func play(sound: String, withSound: Bool, withVibration: Bool) -> [String: Any] {
    var played = false
    if withSound, let url = Bundle.main.url(forResource: sound, withExtension: "caf") {
      try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
      player = try? AVAudioPlayer(contentsOf: url)
      played = player?.play() ?? false
    }
    if withVibration {
      AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    }
    return ["played": played, "vibrated": withVibration, "ringer": "normal", "dnd": false]
  }

  private func removeDelivered(offer: Int) {
    let center = UNUserNotificationCenter.current()
    center.getDeliveredNotifications { notes in
      let ids = notes.filter { "\($0.request.content.userInfo["id"] ?? "")" == "\(offer)" &&
        ($0.request.content.userInfo["t"] as? String) == "new_mission" }.map { $0.request.identifier }
      center.removeDeliveredNotifications(withIdentifiers: ids)
    }
  }
}
