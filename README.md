# Metriport-IOS

A Swift Library for access to Apple Healthkit.

## Installation

To add a package dependency to your Xcode project, select File > Swift Packages > Add Package Dependency and enter `https://github.com/metriport/metriport-ios-sdk`. For more reference visit apple's [docs here.](https://developer.apple.com/documentation/xcode/adding-package-dependencies-to-your-app)

#### Setup

Add this snippet to the root of your project:

```swift
import MetriportSDK

var healthStore = MetriportHealthStoreManager(clientApiKey: "CLIENT_API_KEY", sandbox: false);
```

Next, initialize the `MetriportWidget` inside of a view to display it. See the following
snippet for an example initialization from a button tap, that then displays the Connect Widget
in a sheet:

```swift
class WidgetController: ObservableObject {
    @Published var showWidget = false;
    var token = "";

    func openWidget(token: String) {
        self.showWidget = true
        self.token = token
    }

}

struct ContentView: View {
    // Manages the Metriport Widget
    @ObservedObject var widgetController = WidgetController()

    var body: some View {
        VStack {
            Button {
                // This is an example, you'll need to get a session token from your server.
                let token = "TOKEN"
                widgetController.openWidget(token: token);
            } label: {
                Text("Open Metriport Widget")
            }
            .sheet(isPresented: $widgetController.showWidget) {
                MetriportWidget(
                    healthStore: healthStore,
                    token: widgetController.token,
                    sandbox: false)
            }
        }
        .padding()
    }
}
```

```
            ,▄,
          ▄▓███▌
      ▄▀╙   ▀▓▀    ²▄
    ▄└               ╙▌
  ,▀                   ╨▄
  ▌                     ║
                         ▌
                         ▌
,▓██▄                 ╔███▄
╙███▌                 ▀███▀
    ▀▄
      ▀╗▄         ,▄
         '╙▀▀▀▀▀╙''


      by Metriport Inc.

```
