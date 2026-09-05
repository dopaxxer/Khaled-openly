import SwiftUI
import UserNotifications
@main struct OpenlyApp:App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var api=API()
    var body:some Scene{
        WindowGroup{
            RootView().environmentObject(api).tint(Ink.blue).environment(\.layoutDirection,api.arabic ? .rightToLeft:.leftToRight).environment(\.locale,Locale(identifier:api.arabic ? "ar":"en")).preferredColorScheme(api.user?.theme=="dark" ? .dark:api.user?.theme=="light" ? .light:nil).task{
                appDelegate.api=api
                await api.start()
            }
            .onOpenURL{
                url in let params=URLComponents(url:url,resolvingAgainstBaseURL:false)?.queryItems
                for item in params ?? [] {
                    guard let id=item.value else{
                        continue
                    }
                    if item.name=="post"{
                        api.route = .post(id)
                    }
                    if item.name=="profile"{
                        api.route = .profile(id)
                    }
                    if item.name=="conversation"{
                        api.route = .conversation(id)
                    }
                }
                if url.scheme=="openly",let id=url.pathComponents.last{
                    switch url.host{
                        case "post":api.route = .post(id)
                        case "profile":api.route = .profile(id)
                        case "conversation":api.route = .conversation(id)
                        default:break
                    }
                }
            }
            .sheet(item:$api.route){
                route in NavigationStack{
                    Group{
                        switch route{
                            case .post(let id):PostDetailView(id:id)
                            case .profile(let id):ProfileView(id:id)
                            case .conversation(let id):ChatView(cid:id,name:api.t("Conversation","محادثة"))
                        }
                    }
                    .toolbar{
                        ToolbarItem(placement:.cancellationAction){
                            Button(api.t("Close","إغلاق")){
                                api.route=nil
                            }
                        }
                    }
                }
            }
        }
    }
}
final class AppDelegate:NSObject,UIApplicationDelegate,UNUserNotificationCenterDelegate {
    weak var api:API?
    func application(_ application:UIApplication,didFinishLaunchingWithOptions launchOptions:[UIApplication.LaunchOptionsKey:Any]?=nil)->Bool{
        UNUserNotificationCenter.current().delegate=self
        return true
    }
    func application(_ application:UIApplication,didRegisterForRemoteNotificationsWithDeviceToken deviceToken:Data){
        let token=deviceToken.map{
            String(format:"%02x",$0)
        }
        .joined()
        Task{
            @MainActor in guard let api else{
                return
            }
            do{
                let _:OK=try await api.request("devices",method:"POST",body:["token":token,"platform":"ios"])
            }
            catch{
                api.error=error.localizedDescription
            }
        }
    }
    func application(_ application:UIApplication,didFailToRegisterForRemoteNotificationsWithError error:Error){
        Task{
            @MainActor in api?.error=error.localizedDescription
        }
    }
    func userNotificationCenter(_ center:UNUserNotificationCenter,didReceive response:UNNotificationResponse,withCompletionHandler completionHandler:@escaping()->Void){
        let info=response.notification.request.content.userInfo
        Task{
            @MainActor in if let target=info["target"] as? String,let type=info["type"] as? String {
                api?.route = ["message","message_request"].contains(type) ? .conversation(target):["like","comment"].contains(type) ? .post(target):.profile(target)
            }
            completionHandler()
        }
    }
}
struct RootView:View {
    @EnvironmentObject var api:API
    var body:some View{
        Group{
            if api.loading{
                ProgressView("Openly")
            }
            else if api.recovery != nil{
                RecoveryView()
            }
            else if api.user==nil{
                AuthView()
            }
            else if api.user?.onboarded != 1{
                OnboardingView()
            }
            else{
                MainView()
            }
        }
    }
}
struct MainView:View {
    @EnvironmentObject var api:API
    @Environment(\.horizontalSizeClass) var sizeClass
    @State private var selection=0
    @State private var composer=false
    @State private var notices=false
    var names:[String]{
        [api.t("Home","الرئيسية"),api.t("Discover","اكتشف"),api.t("Circles","دوائر"),api.t("Messages","الرسائل"),api.t("My Space","مساحتي")]
    }
    let symbols=["house","magnifyingglass","person.2","bubble.left.and.bubble.right","person.crop.circle"]
    @ViewBuilder func screen(_ index:Int)->some View {
        switch index{
            case 0:HomeView()
            case 1:DiscoverView()
            case 2:CirclesView()
            case 3:ConversationsView()
            default:ProfileView(id:api.user!.id)
        }
    }
    var body:some View{
        Group{
            if sizeClass == .regular{
                NavigationSplitView{
                    List(selection:$selection){
                        ForEach(0..<5){
                            i in Label(names[i],systemImage:symbols[i]).tag(i)
                        }
                    }
                    .navigationTitle("openly")
                } detail:{
                    NavigationStack{
                        screen(selection).frame(maxWidth:760).frame(maxWidth:.infinity).navigationTitle(names[selection]).toolbar{
                            topToolbar
                        }
                    }
                }
            }
            else{
                TabView(selection:$selection){
                    ForEach(0..<5){
                        i in NavigationStack{
                            screen(i).navigationTitle(names[i]).navigationBarTitleDisplayMode(.inline).toolbar{
                                topToolbar
                            }
                        }
                        .tabItem{
                            Label(names[i],systemImage:symbols[i])
                        }
                        .tag(i)
                    }
                }
            }
        }
        .sheet(isPresented:$composer){
            ComposerView()
        }
        .sheet(isPresented:$notices){
            NavigationStack{
                NotificationsView().toolbar{
                    ToolbarItem(placement:.cancellationAction){
                        Button(api.t("Close","إغلاق")){
                            notices=false
                        }
                    }
                }
            }
        }
    }
    @ToolbarContentBuilder var topToolbar:some ToolbarContent {
        ToolbarItemGroup(placement:.topBarTrailing){
            Button{
                composer=true
            } label:{
                Image(systemName:"square.and.pencil")
            }
            .accessibilityLabel(api.t("Create post","إنشاء منشور"))
            Button{
                notices=true
            } label:{
                Image(systemName:"bell")
            }
            .accessibilityLabel(api.t("Notifications","الإشعارات"))
        }
    }
}
