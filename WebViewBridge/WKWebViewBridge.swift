import Foundation
import WebKit

final class WKWebViewBridge: NSObject {
    private enum Constants {
        static let messageHandler = "bridgeMessageHandler"
        static let appStateHandler = "window.eventDispatcher" //javascript function to handle app state event
        static let foregroundState = "applicationEnterForeground"
        static let backgroundState = "applicationEnterBackground"
    }
    
    typealias Handler = (JSMessageBody) -> ()
    
    private let webView: WKWebView
    private var handlerMap = Dictionary<String, Handler>()
    
    init(webview: WKWebView) {
        self.webView = webview
        super.init()
        self.webView.uiDelegate = self
        let userContentController = self.webView.configuration.userContentController
        userContentController.add(self, name: Constants.messageHandler)
    }
    
    func register(action: String, with handler: @escaping Handler) {
        self.handlerMap.updateValue(handler, forKey: action)
    }
    
    func removeHandler(action: String) {
        self.handlerMap.removeValue(forKey: action)
    }
    
    func injectMessage(callBackId: String, callBackFunction: String, params: Dictionary<String, Any>, handler: ((Any?, Error?) -> ())? = nil) {
        
        guard let paramsString = serializeMessage(params: params) else { return }
        let correctParams = recorrectJavascriptMessage(paramsString)
        let javascriptCommand = String(format: "%@('%@', '%@');", callBackFunction, callBackId, correctParams)

        if Thread.isMainThread {
            self.webView.evaluateJavaScript(javascriptCommand, completionHandler: handler)
            
        } else {
            DispatchQueue.main.async {
                self.webView.evaluateJavaScript(javascriptCommand, completionHandler: handler)
            }
        }
    }
    
    func serializeMessage(params: Dictionary<String, Any>) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: params, options: .prettyPrinted), let result = String(data: data, encoding: .utf8) else { return nil }
        return result
    }
    
    func recorrectJavascriptMessage(_ message: String) -> String {
        var encodedMessage = message
        encodedMessage = encodedMessage.replacingOccurrences(of: "\\", with: "\\\\")
        encodedMessage = encodedMessage.replacingOccurrences(of: "\"", with: "\\\"")
        encodedMessage = encodedMessage.replacingOccurrences(of: "\'", with: "\\\'")
        encodedMessage = encodedMessage.replacingOccurrences(of: "\n", with: "\\n")
        encodedMessage = encodedMessage.replacingOccurrences(of: "\r", with: "\\r")
//        encodedMessage = encodedMessage.replacingOccurrences(of: "\f", with: "\\f")//"\f" is form feed character can not directly use in swift
        encodedMessage = encodedMessage.replacingOccurrences(of: "\u{000C}", with: "\\f")
        encodedMessage = encodedMessage.replacingOccurrences(of: "\u{2028}", with: "\\u2028")
        encodedMessage = encodedMessage.replacingOccurrences(of: "\u{2029}", with: "\\u2029")
        
        return encodedMessage
    }
    
    func destroyBridge() {
        //need to detroy the messageHandler reference first to reduce the retain cycle between webveiw and bridge
        self.webView.configuration.userContentController.removeAllScriptMessageHandlers()
    }
}

// MARK: - lifecycleevent
extension WKWebViewBridge {
    func addLifeCycleListener() {
        NotificationCenter.default.addObserver(self, selector: #selector(applicationEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(applicationEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
    }
    
    func removeLifeCycleObserver() {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc func applicationEnterForeground() {
        sentEvent(name: Constants.foregroundState)
    }
    
    @objc func applicationEnterBackground() {
        sentEvent(name: Constants.backgroundState)
    }
    
    func sentEvent(name: String, params: Dictionary<String, Any> = ["": ""]) {
        injectMessage(callBackId: name, callBackFunction: Constants.appStateHandler, params: params)
    }
}

// MARK: - asynchronize way for js call native
extension WKWebViewBridge: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == Constants.messageHandler, let body = message.body as? Dictionary<String, Any> else { return }
        let messageBody = JSMessageBody(dictionary: body)
        guard let handler = self.handlerMap[messageBody.actionName] else { return }
        if let callbackID = messageBody.callbackID, let callbackFunction = messageBody.callbackFunction {
            let callBack: CallBack = { (parameters: Dictionary<String, Any>) in
                self.injectMessage(callBackId: callbackID, callBackFunction: callbackFunction, params: parameters)
            }
            messageBody.config(callback: callBack)
        }
        handler(messageBody)
    }
}

// MARK: - synchronize way for js call native
extension WKWebViewBridge: WKUIDelegate {
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        guard let data = prompt.data(using: .utf8),
              let dic = try? JSONSerialization.jsonObject(with: data, options: []) as? Dictionary<String, Any> else { return }
        let messageBody = JSMessageBody(dictionary: dic)
        guard let handler = self.handlerMap[messageBody.actionName] else { return }
        handler(messageBody)
        completionHandler(messageBody.result)
    }
}

typealias CallBack = (Dictionary<String, Any>) -> ()

final class JSMessageBody {
    private enum Constants {
        static let actionName = "action"
        static let parameters = "parameters"
        static let callbackID = "callbackID"
        static let callbackFunction = "callbackFunction"
    }
    
    var actionName: String
    var parameters: Dictionary<String, Any>
    var callbackID: String? //to identify the callback stored at H5 Page
    var callbackFunction: String? //pass by H5 page to give more flexibility
    private var callBackBlock: CallBack?
    var result: String?//only used for the synchronize call from JS, to pass the result to completionHandler
    
    init(dictionary: Dictionary<String, Any>) {
        self.actionName = dictionary[Constants.actionName] as? String ?? ""
        self.parameters = dictionary[Constants.parameters] as? Dictionary<String, Any> ?? Dictionary<String, Any>()
        self.callbackID = dictionary[Constants.callbackID] as? String
        self.callbackFunction = dictionary[Constants.callbackFunction] as? String
    }
    
    func config(callback: @escaping CallBack) {
        callBackBlock = callback
    }
    
    func runCallBack(params: Dictionary<String, Any>) {
        guard let callback = self.callBackBlock else { return }
        callback(params)
    }
}

