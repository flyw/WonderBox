import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)
    (UIApplication.shared.delegate as? AppDelegate)?.ensureServerRunning()
  }

  override func sceneWillEnterForeground(_ scene: UIScene) {
    super.sceneWillEnterForeground(scene)
    (UIApplication.shared.delegate as? AppDelegate)?.ensureServerRunning()
  }
}
