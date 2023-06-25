import Foundation
import WebKit

extension WKWebView {
    //handle the wkwebview miss the cookies from the app, cause they manage the cookies seperately
    func loadPerfectRequest(url: URL) {
        var request = URLRequest(url: url)
        if let cookies = HTTPCookieStorage.shared.cookies(for: url) {
            let headers = HTTPCookie.requestHeaderFields(with: cookies)
            let cookieStr = headers.values.joined(separator: "; ")
            request.setValue(cookieStr, forHTTPHeaderField: "Cookie")
        }
        
        load(request)
    }
    
    //add the cookies for the javascript H5 to use
    func addCookiesToJS(url: URL) {
        guard let cookies = HTTPCookieStorage.shared.cookies(for: url) else { return }
        var filteredCookies: [HTTPCookie] = []
        for cookie in cookies {
            if !cookie.isHTTPOnly {
                filteredCookies.append(cookie)
            }
        }
        
        guard filteredCookies.count > 0 else { return }
        let headers = HTTPCookie.requestHeaderFields(with: cookies)
        let cookieStr = headers.values.joined(separator: "; ")
        let jsCommand = "document.cookie = '\(cookieStr)';"
        let jsScript = WKUserScript(source: jsCommand, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        self.configuration.userContentController.addUserScript(jsScript)
    }
}

