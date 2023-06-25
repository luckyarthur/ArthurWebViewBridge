import UIKit
import WebKit

class ViewController: UIViewController {

    private var webView: WKWebView = {
        let webView = WKWebView()
        webView.scrollView.backgroundColor = .cyan
        webView.allowsBackForwardNavigationGestures = true
        return webView
    }()
            
    private var webBridge: WKWebViewBridge?
    
    
    override func loadView() {
        view = webView
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        webBridge = WKWebViewBridge(webview: webView)
        webView.loadPerfectRequest(url: URL(string: "https://goldprice.org")!)
        runJavascript()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        print("disappear")
        webBridge?.destroyBridge()
    }

    func runJavascript() {
        //test code 
        let javascriptStr = "window.webkit.messageHandlers.bridgeMessageHandler.postMessage('message')"
        webView.evaluateJavaScript(javascriptStr)
        print("run javascript")
        
        let prompt = "prompt('hello')"
        webView.evaluateJavaScript(prompt)
        print("run prompt")
    }
    
}
