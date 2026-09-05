import SwiftUI
struct AuthView:View {
    @EnvironmentObject var api:API
    @State private var register=false
    @State private var email=""
    @State private var password=""
    @State private var name=""
    @State private var username=""
    @State private var recoveryCode=""
    @State private var recover=false
    @State private var busy=false
    @State private var error:String?
    var body:some View{
        NavigationStack{
            ScrollView{
                VStack(alignment:.leading,spacing:20){
                    Text("openly").font(.system(size:42,design:.serif).weight(.semibold)).foregroundStyle(Ink.blue).padding(.bottom,25)
                    Text(recover ? api.t("Recover your account","استرداد حسابك"):register ? api.t("Find your people.","اعثر على أشخاص يشبهونك."):api.t("Welcome back.","أهلًا بعودتك.")).font(.title2.weight(.semibold))
                    if register{
                        TextField(api.t("Display name","الاسم"),text:$name).textContentType(.name)
                        TextField(api.t("Username","اسم المستخدم"),text:$username).textInputAutocapitalization(.never).autocorrectionDisabled().textContentType(.username)
                    }
                    TextField(api.t("Email","البريد الإلكتروني"),text:$email).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled().textContentType(.emailAddress)
                    if recover{
                        TextField(api.t("Recovery code","رمز الاسترداد"),text:$recoveryCode).textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                    SecureField(api.t("Password — at least 12 characters","كلمة المرور — 12 حرفًا على الأقل"),text:$password).textContentType(register || recover ? .newPassword:.password)
                    if let error{
                        ErrorNotice(message:error)
                    }
                    BusyButton(title:recover ? api.t("Reset password","تغيير كلمة المرور"):register ? api.t("Create account","إنشاء حساب"):api.t("Sign in","تسجيل الدخول"),busy:busy){
                        Task{
                            busy=true
                            defer{
                                busy=false
                            }
                            do{
                                if recover{
                                    let r:RecoveryResponse=try await api.request("auth/recover",method:"POST",body:["email":email,"recovery":recoveryCode,"password":password])
                                    api.recovery=r.recovery
                                    recover=false
                                }
                                else{
                                    try await api.authenticate(register:register,email:email,password:password,name:name,username:username)
                                }
                            }
                            catch{
                                self.error=error.localizedDescription
                            }
                        }
                    }
                    Button(register ? api.t("Already a member? Sign in","لديك حساب؟ سجّل الدخول"):api.t("Create an account","إنشاء حساب")){
                        register.toggle()
                        recover=false
                        error=nil
                    }
                    if !register{
                        Button(api.t("Forgot password?","نسيت كلمة المرور؟")){
                            recover.toggle()
                        }
                    }
                }
                .textFieldStyle(.roundedBorder).padding(28).frame(maxWidth:430).frame(maxWidth:.infinity)
            }
            .scrollDismissesKeyboard(.interactively).dismissKeyboardToolbar(api.t("Done","تم"))
        }
    }
}
struct RecoveryView:View {
    @EnvironmentObject var api:API
    var body:some View{
        VStack(alignment:.leading,spacing:22){
            Image(systemName:"key").font(.largeTitle).foregroundStyle(Ink.blue)
            Text(api.t("Save your recovery code","احفظ رمز الاسترداد")).font(.title2)
            Text(api.t("Keep it private. It is required to reset a forgotten password and is shown only once.","احفظه في مكان خاص. تحتاجه لاسترداد كلمة المرور، ويُعرض مرة واحدة فقط."))
            Text(api.recovery ?? "").font(.system(.body,design:.monospaced)).textSelection(.enabled)
            ShareLink(item:api.recovery ?? ""){
                Label(api.t("Save code","حفظ الرمز"),systemImage:"square.and.arrow.up")
            }
            BusyButton(title:api.t("I’ve saved it","حفظت الرمز")){
                api.recovery=nil
            }
        }
        .padding(30)
    }
}
let interestKeys=["music","art","books","photography","film","everyday","design","science","gaming","travel"]
func interestName(_ key:String,_ api:API)->String{
    let ar=["موسيقى","فن","كتب","تصوير","أفلام","حياة يومية","تصميم","علوم","ألعاب","سفر"]
    guard let i=interestKeys.firstIndex(of:key) else{
        return key
    }
    return api.arabic ? ar[i]:key.capitalized
}
struct OnboardingView:View {
    @EnvironmentObject var api:API
    @State private var chosen:Set<String>=[]
    @State private var bio=""
    @State private var error:String?
    @State private var busy=false
    var body:some View{
        NavigationStack{
            Form{
                Section{
                    Text(api.t("What draws you in?","ما الذي يثير اهتمامك؟")).font(.title2)
                    Text(api.t("Choose interests to discover people and Circles. You can change these anytime.","اختر اهتماماتك لاكتشاف الأشخاص والدوائر. يمكنك تعديلها لاحقًا."))
                }
                Section{
                    ForEach(interestKeys,id:\.self){
                        key in Toggle(interestName(key,api),isOn:Binding(get:{
                            chosen.contains(key)
                        }
                        ,set:{
                            if $0{
                                chosen.insert(key)
                            }
                            else{
                                chosen.remove(key)
                            }
                        }
                        ))
                    }
                }
                Section{
                    TextField(api.t("A little about you (optional)","نبذة عنك (اختياري)"),text:$bio,axis:.vertical)
                }
                if let error{
                    ErrorNotice(message:error)
                }
                BusyButton(title:api.t("Enter your space","ادخل مساحتك"),busy:busy){
                    finish()
                }
                Button(api.t("Skip for now","تخطّ الآن")){
                    chosen=[]
                    bio=""
                    finish()
                }
            }
            .navigationTitle("openly").dismissKeyboardToolbar(api.t("Done","تم"))
        }
    }
    func finish(){
        Task{
            busy=true
            defer{
                busy=false
            }
            do{
                try await api.update(["interests":Array(chosen),"bio":bio,"onboarded":1])
            }
            catch{
                self.error=error.localizedDescription
            }
        }
    }
}
