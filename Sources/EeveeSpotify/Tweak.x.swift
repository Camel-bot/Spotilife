import Orion
import UIKit

func exitApplication() {

    UIControl().sendAction(#selector(URLSessionTask.suspend), to: UIApplication.shared, for: nil)
    Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { _ in
        exit(EXIT_SUCCESS)
    }
}

struct EeveeSpotify: Tweak {
    
    static let version = "4.1"
    
    init() {

        do {

            defer {

                if UserDefaults.darkPopUps {
                    DarkPopUps().activate()
                }
                
                let patchType = UserDefaults.patchType
                
                if patchType.isPatching {
                    
                    if patchType == .offlineBnk {
                        NSFileCoordinator.addFilePresenter(OfflineObserver())
                    }
                    
                    ServerSidedReminder().activate()
                }
            }

            switch UserDefaults.patchType {
            
            case .disabled:
                
                NSLog("[EeveeSpotify] Not activating: patchType is disabled")
                return
            
            case .offlineBnk:
                
                do {
                    try OfflineHelper.restoreFromEeveeBnk()
                    
                    NSLog("[EeveeSpotify] Restored from eevee.bnk")
                    return
                }
                
                catch CocoaError.fileReadNoSuchFile {
                    NSLog("[EeveeSpotify] Not restoring from eevee.bnk: doesn't exist")
                }
                
                do {
                    try OfflineHelper.patchOfflineBnk()
                    try OfflineHelper.backupToEeveeBnk()
                }
                
                catch CocoaError.fileReadNoSuchFile {
                    
                    NSLog("[EeveeSpotify] Not activating: offline.bnk doesn't exist")
                    
                    PopUpHelper.showPopUp(
                        delayed: true,
                        message: "Please log in and restart the app to get Premium.",
                        buttonText: "OK"
                    )
                }
            
            default:
                break
            }
        }

        catch {
            
            NSLog("[EeveeSpotify] Unable to apply tweak: \(error)")

            PopUpHelper.showPopUp(
                delayed: true,
                message: "Unable to apply tweak: \(error)", 
                buttonText: "OK"
            )
        }
    }
}
