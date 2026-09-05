import Foundation
import Security
import SwiftUI
struct OpenlyError: LocalizedError {
    let code:String
    var errorDescription:String? {
        code
    }
}
enum Keychain {
    static let service="Openly.Session"
    static func read()->String? {
        let query:[String:Any]=[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:"session",kSecReturnData as String:true,kSecMatchLimit as String:kSecMatchLimitOne]
        var value:CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary,&value)==errSecSuccess,let data=value as? Data else{
            return nil
        }
        return String(data:data,encoding:.utf8)
    }
    static func save(_ token:String?) {
        let query:[String:Any]=[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:"session"]
        SecItemDelete(query as CFDictionary)
        guard let token else{
            return
        }
        var value=query
        value[kSecValueData as String]=Data(token.utf8)
        value[kSecAttrAccessible as String]=kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(value as CFDictionary,nil)
    }
}
@MainActor final class API: ObservableObject {
    @Published var pushConfigured=false
    @Published var user:Person?
    @Published var loading=true
    @Published var error:String?
    @Published var recovery:String?
    @Published var route:DeepRoute?
    let origin:URL
    let session=URLSession(configuration:.default)
    init(){
        let configured=Bundle.main.object(forInfoDictionaryKey:"OpenlyAPIOrigin") as? String ?? ""
        origin=URL(string:configured) ?? URL(string:"https://openly.invalid")!
    }
    var arabic:Bool {
        user?.language == "ar" || (user==nil && Locale.current.language.languageCode?.identifier == "ar")
    }
    func t(_ en:String,_ ar:String)->String {
        arabic ? ar : en
    }
    func request<T:Decodable>(_ path:String,method:String="GET",body:[String:Any]?=nil) async throws -> T {
        guard origin.scheme=="https",origin.host != "openly.invalid" else{
            throw OpenlyError(code:t("Configure the secure API origin before using this build.","يجب إعداد عنوان الخادم الآمن لهذا الإصدار."))
        }
        var req=URLRequest(url:URL(string:"/api/"+path,relativeTo:origin)!)
        req.httpMethod=method
        req.timeoutInterval=25
        req.setValue("ios",forHTTPHeaderField:"x-openly-client")
        if let token=Keychain.read(){
            req.setValue("Bearer "+token,forHTTPHeaderField:"Authorization")
        }
        if let body{
            req.httpBody=try JSONSerialization.data(withJSONObject:body)
            req.setValue("application/json",forHTTPHeaderField:"Content-Type")
        }
        let (data,response)=try await session.data(for:req)
        guard let http=response as? HTTPURLResponse else{
            throw OpenlyError(code:"server_error")
        }
        guard (200..<300).contains(http.statusCode) else{
            let object=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any]
            throw OpenlyError(code:message(object?["error"] as? String ?? "server_error"))
        }
        return try JSONDecoder().decode(T.self,from:data)
    }
    func message(_ code:String)->String {
        switch code {
            case "invalid_credentials":return t("The email or password is incorrect.","البريد الإلكتروني أو كلمة المرور غير صحيحة.")
            case "account_exists":return t("This email or username is already in use.","البريد الإلكتروني أو اسم المستخدم مستخدم بالفعل.")
            case "unavailable":return t("This content is no longer available to you.","لم يعد هذا المحتوى متاحًا لك.")
            case "request_pending":return t("Wait for your message request to be accepted.","انتظر قبول طلب المحادثة.")
            case "messages_closed":return t("This person isn’t accepting messages.","هذا الشخص لا يستقبل رسائل حاليًا.")
            case "rate_limited":return t("Please wait a minute and try again.","انتظر دقيقة وحاول مجددًا.")
            case "validation":return t("Please check your information.","تحقق من المعلومات المدخلة.")
            case "invalid_recovery":return t("The recovery code is incorrect.","رمز الاسترداد غير صحيح.")
            case "too_large":return t("Choose a file smaller than 10 MB.","اختر ملفًا أصغر من 10 ميغابايت.")
            case "sign_in":return t("Sign in to continue.","سجّل الدخول للمتابعة.")
            default:return t("The action could not be completed. Please try again.","تعذّر إكمال الإجراء. حاول مجددًا.")
        }
    }
    func start() async {
        defer{
            loading=false
        }
        guard Keychain.read() != nil else{
            return
        }
        do{
            let r:UserResponse=try await request("me")
            user=r.user
            pushConfigured=r.capabilities?.push ?? false
        }
        catch{
            self.error=error.localizedDescription
        }
    }
    func authenticate(register:Bool,email:String,password:String,name:String,username:String) async throws {
        let r:UserResponse=try await request(register ? "auth/register":"auth/login",method:"POST",body:register ? ["email":email,"password":password,"name":name,"username":username]:["email":email,"password":password])
        Keychain.save(r.token)
        user=r.user
        recovery=r.recovery
        if let current: UserResponse = try? await request("me") { pushConfigured=current.capabilities?.push ?? false }
    }
    func update(_ values:[String:Any]) async throws {
        let r:UserResponse=try await request("me",method:"PATCH",body:values)
        user=r.user
    }
    func logout() async throws {
        let _:OK=try await request("auth/logout",method:"POST")
        Keychain.save(nil)
        user=nil
    }
    func media(_ id:String) async throws ->(Data,String) {
        var req=URLRequest(url:origin.appendingPathComponent("api/media/"+id))
        if let token=Keychain.read(){
            req.setValue("Bearer "+token,forHTTPHeaderField:"Authorization")
        }
        let (data,response)=try await session.data(for:req)
        guard (response as? HTTPURLResponse)?.statusCode==200 else{
            throw OpenlyError(code:message("unavailable"))
        }
        return(data,response.mimeType ?? "application/octet-stream")
    }
    func upload(_ data:Data,type:String) async throws ->String {
        guard data.count<=10*1024*1024 else{
            throw OpenlyError(code:message("too_large"))
        }
        var req=URLRequest(url:origin.appendingPathComponent("api/media"))
        req.httpMethod="POST"
        req.httpBody=data
        req.setValue(type,forHTTPHeaderField:"Content-Type")
        req.setValue("Bearer "+(Keychain.read() ?? ""),forHTTPHeaderField:"Authorization")
        let (bytes,response)=try await session.data(for:req)
        guard (response as? HTTPURLResponse)?.statusCode==201 else{
            throw OpenlyError(code:message("server_error"))
        }
        return try JSONDecoder().decode(UploadResponse.self,from:bytes).id
    }
    func updates(_ cid:String) -> AsyncStream<Void> {
        AsyncStream{
            continuation in let task=Task{
                while !Task.isCancelled {
                    do {
                        var req=URLRequest(url:origin.appendingPathComponent("api/conversations/\(cid)/events"))
                        req.setValue("Bearer "+(Keychain.read() ?? ""),forHTTPHeaderField:"Authorization")
                        let (bytes,response)=try await session.bytes(for:req)
                        guard (response as? HTTPURLResponse)?.statusCode==200 else{
                            break
                        }
                        for try await line in bytes.lines {
                            if Task.isCancelled{
                                break
                            }
                            if line=="event: update"{
                                continuation.yield(Void())
                            }
                        }
                    }
                    catch{
                        if Task.isCancelled{
                            break
                        }
                        try? await Task.sleep(for:.seconds(3))
                    }
                }
                continuation.finish()
            }
            continuation.onTermination={
                _ in task.cancel()
            }
        }
    }
}
enum DeepRoute:Identifiable {
    case post(String),profile(String),conversation(String)
    var id:String{
        switch self{
            case .post(let id),.profile(let id),.conversation(let id):return id
        }
    }
}
