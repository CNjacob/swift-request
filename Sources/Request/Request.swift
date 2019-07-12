//
//  File.swift
//  
//
//  Created by Carson Katri on 6/30/19.
//

import Foundation
import SwiftUI
import Combine

public class Request: BindableObject {
    public var didChange = PassthroughSubject<Request, Never>()
    
    private var params: CombinedParams
    
    private var onData: ((Data?) -> Void)?
    private var onString: ((String?) -> Void)?
    private var onJson: ((Json?) -> Void)?
    private var onError: ((RequestError) -> Void)?
    
    var response: Response = Response() {
        didSet {
            didChange.send(self)
        }
    }
    
    init(@RequestBuilder builder: () -> RequestParam) {
        let params = builder()
        if !(params is CombinedParams) {
            self.params = CombinedParams(children: [params])
        } else {
            self.params = builder() as! CombinedParams
        }
        self.response = Response()
    }
    
    internal init(params: CombinedParams) {
        self.params = params
        self.response = Response()
    }
    
    func onData(_ callback: @escaping (Data?) -> Void) -> Request {
        self.onData = callback
        return self
    }
    
    func onString(_ callback: @escaping (String?) -> Void) -> Request {
        self.onString = callback
        return self
    }
    
    func onJson(_ callback: @escaping (Json?) -> Void) -> Request {
        self.onJson = callback
        return self
    }
    
    func onError(_ callback: @escaping (RequestError) -> Void) -> Request {
        self.onError = callback
        return self
    }
    
    func call() {
        // Url
        guard var components = URLComponents(string: params.children!.filter({ $0.type == .url })[0].value as! String) else {
            fatalError("Missing Url in Request body")
        }
        
        // Query, QueryParam
        let query = params.children!.filter({ $0.type == .query }).reduce([QueryParam]()) { (prev, param) in
            if param.children != nil {
                return prev + (param.children as! [QueryParam])
            } else {
                return prev + ([param] as! [QueryParam])
            }
        }
        components.queryItems = query.map { param in
            return URLQueryItem(name: param.key!, value: (param.value as! String))
        }
        
        // BUILD REQUEST
        var request = URLRequest(url: components.url!)
        let method = params.children!.filter({ $0.type == .method })
        if method.count > 0 {
            request.httpMethod = (method[0].value as! MethodType).rawValue
        }
        
        // Headers, Header
        let headers = params.children!.filter({ $0.type == .header }).reduce([HeaderParam]()) { (prev, param) in
            if param.children != nil {
                return prev + (param.children as! [HeaderParam])
            } else if param is HeaderParam {
                return prev + ([param] as! [HeaderParam])
            }
            return prev
        }
        headers.forEach { header in
            request.addValue(header.value as! String, forHTTPHeaderField: header.key!)
        }
        
        // Body
        let body = params.children!.filter({ $0.type == .body })
        if body.count > 0 {
            request.httpBody = body[0].value as? Data
        }
        
        // PERFORM REQUEST
        URLSession.shared.dataTask(with: request) { data, res, err in
            if res != nil {
                let statusCode = (res as! HTTPURLResponse).statusCode
                if statusCode < 200 || statusCode >= 300 {
                    if self.onError != nil {
                        self.onError!(RequestError(statusCode: statusCode, error: data))
                        return
                    }
                }
            }
            if data != nil {
                if self.onData != nil {
                    self.onData!(data)
                }
                if self.onString != nil {
                    self.onString!(String(data: data!, encoding: .utf8))
                }
                if self.onJson != nil {
                    self.onJson!(Json.Parse(String(data: data!, encoding: .utf8)!))
                    /*do {
                        let json = try JSONSerialization.jsonObject(with: data!)
                        self.onJson!(json)
                    } catch {
                        fatalError(error.localizedDescription)
                    }*/
                }
                self.response.data = data
            }
        }.resume()
    }
}
