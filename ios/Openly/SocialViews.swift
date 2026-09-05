import SwiftUI
import PhotosUI
import UserNotifications
struct DiscoverView:View {
    @EnvironmentObject var api:API
    @State private var query=""
    @State private var filter="people"
    @State private var people:[Person]=[]
    @State private var circles:[Circle]=[]
    @State private var songs:[Song]=[]
    @State private var error:String?
    var body:some View{
        VStack{
            Picker(api.t("Search type","نوع البحث"),selection:$filter){
                Text(api.t("People","أشخاص")).tag("people")
                Text(api.t("Posts","منشورات")).tag("posts")
                Text(api.t("Songs","أغانٍ")).tag("songs")
                Text(api.t("Circles","دوائر")).tag("circles")
            }
            .pickerStyle(.segmented).padding(.horizontal)
            if filter=="posts"{
                FeedView(path:"search?q="+encoded)
            }
            else{
                List{
                    if let error{
                        ErrorNotice(message:error)
                    }
                    if filter=="people"{
                        ForEach(people){
                            p in NavigationLink{
                                ProfileView(id:p.id)
                            } label:{
                                PersonLabel(person:p)
                            }
                        }
                        if people.isEmpty{
                            QuietEmpty(icon:"person.2",title:api.t("Find your people.","اعثر على أشخاص يشبهونك."),detail:api.t("No matching accounts yet.","لا توجد حسابات مطابقة بعد."))
                        }
                    }
                    if filter=="circles"{
                        ForEach(circles){
                            c in NavigationLink{
                                CircleView(circle:c)
                            } label:{
                                CircleLabel(circle:c)
                            }
                        }
                    }
                    if filter=="songs"{
                        ForEach(songs){
                            SongView(song:$0)
                        }
                    }
                }
            }
        }
        .searchable(text:$query,prompt:api.t("Follow your curiosity…","اتبع فضولك…")).task(id:filter+query){
            do{
                try await Task.sleep(for:.milliseconds(350))
                switch filter{
                    case "people":let r:Page<Person>=try await api.request("people?q="+encoded)
                    people=r.items
                    case "circles":let r:Page<Circle>=try await api.request("circles?q="+encoded)
                    circles=r.items
                    case "songs":if query.count>1{
                        let r:Page<Song>=try await api.request("music?q="+encoded)
                        songs=r.items
                    }
                    default:break
                }
                error=nil
            }
            catch{
                if !Task.isCancelled{
                    self.error=error.localizedDescription
                }
            }
        }
    }
    var encoded:String{
        query.addingPercentEncoding(withAllowedCharacters:.urlQueryAllowed.subtracting(CharacterSet(charactersIn:"&+=?#"))) ?? ""
    }
}
struct PersonLabel:View {
    @EnvironmentObject var api:API
    let person:Person
    var body:some View{
        HStack{
            AvatarView(person:person.name,media:person.avatar)
            VStack(alignment:.leading,spacing:5){
                Text(person.name).font(.subheadline.bold())
                Text("@"+person.username).font(.caption).foregroundStyle(.secondary)
                if let common=person.shared,!common.isEmpty{
                    Text(api.t("You both enjoy ","يجمعكما الاهتمام بـ ")+common.map{
                        interestName($0,api)
                    }
                    .joined(separator:api.t(", ","، "))).font(.caption).foregroundStyle(Ink.blue)
                }
            }
        }
    }
}
struct ProfileView:View {
    @EnvironmentObject var api:API
    let id:String
    @State private var person:Person?
    @State private var error:String?
    @State private var edit=false
    @State private var settings=false
    @State private var saved=false
    @State private var report=false
    @State private var block=false
    var body:some View{
        ScrollView{
            VStack(alignment:.leading,spacing:16){
                if let p=person{
                    Rectangle().fill(Ink.accent(p.accent).opacity(0.14)).frame(height:95).overlay(alignment:.bottomLeading){
                        AvatarView(person:p.name,media:p.avatar,size:72).padding(.leading,20).offset(y:25)
                    }
                    .padding(.bottom,24)
                    HStack{
                        VStack(alignment:.leading){
                            Text(p.name).font(.title2.bold())
                            Text("@"+p.username).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if p.private==1{
                            Image(systemName:"lock")
                        }
                    }
                    if id==api.user?.id{
                        HStack{
                            Button(api.t("Edit profile","تعديل الملف")){
                                edit=true
                            }
                            .buttonStyle(.bordered)
                            Button{
                                settings=true
                            } label:{
                                Image(systemName:"gearshape")
                            }
                            Button{
                                saved=true
                            } label:{
                                Image(systemName:"bookmark")
                            }
                        }
                    }
                    else{
                        HStack{
                            Button(p.following=="accepted" ? api.t("Following","تتابعه"):p.following=="pending" ? api.t("Requested","تم الطلب"):api.t("Follow","متابعة")){
                                Task{
                                    do{
                                        let _:LooseResponse=try await api.request("people/\(id)/follow",method:p.following==nil ? "POST":"DELETE")
                                        await load()
                                    }
                                    catch{
                                        self.error=error.localizedDescription
                                    }
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            Button(api.t("Message","رسالة")){
                                Task{
                                    do{
                                        let c:ConversationResponse=try await api.request("conversations",method:"POST",body:["userId":id])
                                        api.route = .conversation(c.conversation.id)
                                    }
                                    catch{
                                        self.error=error.localizedDescription
                                    }
                                }
                            }
                            Menu{
                                Button(api.t("Report","إبلاغ")){
                                    report=true
                                }
                                Button(api.t("Block","حظر"),role:.destructive){
                                    block=true
                                }
                            } label:{
                                Image(systemName:"ellipsis")
                            }
                        }
                    }
                    if let bio=p.bio,!bio.isEmpty{
                        Text(bio)
                    }
                    Text((p.interests ?? []).map{
                        interestName($0,api)
                    }
                    .joined(separator:" · ")).font(.subheadline).foregroundStyle(Ink.blue)
                    if let song=p.song{
                        SongView(song:song)
                    }
                    NavigationLink(api.t("View posts","عرض المنشورات")){
                        FeedView(path:"feed?author="+id).navigationTitle(p.name)
                    }
                }
                else if error==nil{
                    ProgressView()
                }
                if let error{
                    ErrorNotice(message:error,retry:{
                        Task{
                            await load()
                        }
                    }
                    )
                }
            }
        }
        .padding().task{
            await load()
        }
        .refreshable{
            await load()
        }
        .sheet(isPresented:$edit,onDismiss:{
            Task{
                await load()
            }
        }
        ){
            EditProfileView()
        }
        .sheet(isPresented:$settings){
            SettingsView()
        }
        .sheet(isPresented:$saved){
            CollectionsView()
        }
        .sheet(isPresented:$report){
            ReportView(kind:"person",target:id)
        }
        .confirmationDialog(api.t("Block this account?","حظر هذا الحساب؟"),isPresented:$block,titleVisibility:.visible){
            Button(api.t("Block","حظر"),role:.destructive){
                Task{
                    do{
                        let _:OK=try await api.request("people/\(id)/block",method:"POST")
                        await load()
                    }
                    catch{
                        self.error=error.localizedDescription
                    }
                }
            }
        }
    }
    func load()async{
        do{
            let r:UserResponse=try await api.request("people/"+id)
            person=r.user
            error=nil
        }
        catch{
            self.error=error.localizedDescription
        }
    }
}
struct EditProfileView:View {
    @EnvironmentObject var api:API
    @Environment(\.dismiss) var dismiss
    @State private var name=""
    @State private var bio=""
    @State private var accent="blue"
    @State private var selected:Set<String>=[]
    @State private var song:Song?
    @State private var picker=false
    @State private var photo:PhotosPickerItem?
    @State private var avatar:String?
    @State private var busy=false
    @State private var error:String?
    var body:some View{
        NavigationStack{
            Form{
                TextField(api.t("Name","الاسم"),text:$name)
                TextField(api.t("Bio","نبذة"),text:$bio,axis:.vertical).lineLimit(3...5)
                PhotosPicker(selection:$photo,matching:.images){
                    Text(api.t("Profile photo","الصورة الشخصية"))
                }
                Section(api.t("Interests","الاهتمامات")){
                    ForEach(interestKeys,id:\.self){
                        key in Toggle(interestName(key,api),isOn:Binding(get:{
                            selected.contains(key)
                        }
                        ,set:{
                            if $0{
                                selected.insert(key)
                            }
                            else{
                                selected.remove(key)
                            }
                        }
                        ))
                    }
                }
                Picker(api.t("Cover color","لون الغلاف"),selection:$accent){
                    Text(api.t("Ink blue","أزرق الحبر")).tag("blue")
                    Text(api.t("Indigo","نيلي")).tag("indigo")
                    Text(api.t("Slate","رمادي أزرق")).tag("slate")
                }
                if let song{
                    SongView(song:song)
                    Button(api.t("Remove song","إزالة الأغنية")){
                        self.song=nil
                    }
                }
                Button(api.t("Featured song","الأغنية المميزة")){
                    picker=true
                }
                if let error{
                    ErrorNotice(message:error)
                }
                BusyButton(title:api.t("Save changes","حفظ التغييرات"),busy:busy){
                    Task{
                        busy=true
                        defer{
                            busy=false
                        }
                        do{
                            var values:[String:Any]=["name":name,"bio":bio,"accent":accent,"interests":Array(selected),"song":NSNull(),"avatar":avatar as Any? ?? NSNull()]
                            if let song{
                                values["song"]=try JSONSerialization.jsonObject(with:JSONEncoder().encode(song))
                            }
                            try await api.update(values)
                            dismiss()
                        }
                        catch{
                            self.error=error.localizedDescription
                        }
                    }
                }
            }
            .navigationTitle(api.t("Edit profile","تعديل الملف")).toolbar{
                ToolbarItem(placement:.cancellationAction){
                    Button(api.t("Cancel","إلغاء")){
                        dismiss()
                    }
                }
            }
            .dismissKeyboardToolbar(api.t("Done","تم"))
        }
        .onAppear{
            name=api.user?.name ?? ""
            bio=api.user?.bio ?? ""
            accent=api.user?.accent ?? "blue"
            selected=Set(api.user?.interests ?? [])
            song=api.user?.song
            avatar=api.user?.avatar
        }
        .onChange(of:photo){
            _,item in Task{
                busy=true
                defer{
                    busy=false
                }
                do{
                    if let data=try await item?.loadTransferable(type:Data.self),let jpeg=UIImage(data:data)?.jpegData(compressionQuality:0.85){
                        avatar=try await api.upload(jpeg,type:"image/jpeg")
                    }
                }
                catch{
                    self.error=error.localizedDescription
                }
            }
        }
        .sheet(isPresented:$picker){
            SongPickerView{
                song=$0
                picker=false
            }
        }
    }
}
struct CollectionsView:View {
    @EnvironmentObject var api:API
    @Environment(\.dismiss) var dismiss
    var savePost:String?
    @State private var collections:[Collection]=[]
    @State private var name=""
    @State private var rename:Collection?
    @State private var renameText=""
    @State private var remove:Collection?
    @State private var error:String?
    var body:some View{
        NavigationStack{
            List{
                Section{
                    Text(api.t("Visible only to you.","خاصة بك وحدك.")).font(.caption).foregroundStyle(.secondary)
                    ForEach(collections){
                        c in HStack{
                            if let post=savePost{
                                Button(c.name){
                                    Task{
                                        do{
                                            let _:OK=try await api.request("collections/\(c.id)/\(post)",method:"POST")
                                            dismiss()
                                        }
                                        catch{
                                            self.error=error.localizedDescription
                                        }
                                    }
                                }
                            }
                            else{
                                NavigationLink(c.name){
                                    FeedView(path:"collections/"+c.id)
                                }
                            }
                            Spacer()
                            Menu{
                                Button(api.t("Rename","إعادة تسمية")){
                                    rename=c
                                    renameText=c.name
                                }
                                Button(api.t("Delete","حذف"),role:.destructive){
                                    remove=c
                                }
                            } label:{
                                Image(systemName:"ellipsis")
                            }
                        }
                    }
                }
                Section{
                    TextField(api.t("New collection name","اسم مجموعة جديدة"),text:$name)
                    Button(api.t("Create collection","إنشاء مجموعة")){
                        Task{
                            do{
                                let r:IDResponse=try await api.request("collections",method:"POST",body:["name":name])
                                if let post=savePost{
                                    let _:OK=try await api.request("collections/\(r.id)/\(post)",method:"POST")
                                    dismiss()
                                }
                                name=""
                                await load()
                            }
                            catch{
                                self.error=error.localizedDescription
                            }
                        }
                    }
                    .disabled(name.isEmpty)
                }
                if let error{
                    ErrorNotice(message:error)
                }
            }
            .task{
                await load()
            }
            .navigationTitle(api.t("Private collections","المجموعات الخاصة")).toolbar{
                ToolbarItem(placement:.cancellationAction){
                    Button(api.t("Close","إغلاق")){
                        dismiss()
                    }
                }
            }
            .alert(api.t("Rename collection","تسمية المجموعة"),isPresented:Binding(get:{
                rename != nil
            }
            ,set:{
                if !$0{
                    rename=nil
                }
            }
            )){
                TextField(api.t("Name","الاسم"),text:$renameText)
                Button(api.t("Save","حفظ")){
                    guard let c=rename else{
                        return
                    }
                    Task{
                        do{
                            let _:OK=try await api.request("collections/"+c.id,method:"PATCH",body:["name":renameText])
                            await load()
                        }
                        catch{
                            self.error=error.localizedDescription
                        }
                    }
                }
                Button(api.t("Cancel","إلغاء"),role:.cancel){
                }
            }
            .confirmationDialog(api.t("Delete collection?","حذف المجموعة؟"),isPresented:Binding(get:{
                remove != nil
            }
            ,set:{
                if !$0{
                    remove=nil
                }
            }
            )){
                Button(api.t("Delete","حذف"),role:.destructive){
                    guard let c=remove else{
                        return
                    }
                    Task{
                        do{
                            let _:OK=try await api.request("collections/"+c.id,method:"DELETE")
                            await load()
                        }
                        catch{
                            self.error=error.localizedDescription
                        }
                    }
                }
            }
        }
    }
    func load()async{
        do{
            let r:Page<Collection>=try await api.request("collections")
            collections=r.items
        }
        catch{
            self.error=error.localizedDescription
        }
    }
}
struct CircleLabel:View {
    @EnvironmentObject var api:API
    let circle:Circle
    var body:some View{
        HStack{
            Image(systemName:"person.2.circle").font(.title).foregroundStyle(Ink.blue)
            VStack(alignment:.leading,spacing:4){
                Text(circle.name).font(.headline)
                Text(circle.description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            if circle.private==1{
                Image(systemName:"lock")
            }
        }
    }
}
struct CirclesView:View {
    @EnvironmentObject var api:API
    @State private var circles:[Circle]=[]
    @State private var create=false
    @State private var error:String?
    var body:some View{
        List{
            Button{
                create=true
            } label:{
                Label(api.t("Create Circle","إنشاء دائرة"),systemImage:"plus")
            }
            ForEach(circles){
                circle in NavigationLink{
                    CircleView(circle:circle)
                } label:{
                    CircleLabel(circle:circle)
                }
            }
            if circles.isEmpty{
                QuietEmpty(icon:"person.2",title:api.t("Give an interest a home.","امنح اهتمامًا مساحة."),detail:api.t("Start a Circle for what brings you together.","ابدأ دائرة للاهتمام الذي يجمعكم."))
            }
            if let error{
                ErrorNotice(message:error)
            }
        }
        .task{
            await load()
        }
        .refreshable{
            await load()
        }
        .sheet(isPresented:$create,onDismiss:{
            Task{
                await load()
            }
        }
        ){
            CreateCircleView()
        }
    }
    func load()async{
        do{
            let r:Page<Circle>=try await api.request("circles")
            circles=r.items
            error=nil
        }
        catch{
            self.error=error.localizedDescription
        }
    }
}
struct CreateCircleView:View {
    @EnvironmentObject var api:API
    @Environment(\.dismiss) var dismiss
    @State private var name=""
    @State private var description=""
    @State private var rules=""
    @State private var interest="music"
    @State private var privacy=false
    @State private var busy=false
    @State private var error:String?
    var body:some View{
        NavigationStack{
            Form{
                TextField(api.t("Circle name","اسم الدائرة"),text:$name)
                TextField(api.t("Description","الوصف"),text:$description,axis:.vertical)
                TextField(api.t("Rules","القواعد"),text:$rules,axis:.vertical)
                Picker(api.t("Interest","الاهتمام"),selection:$interest){
                    ForEach(interestKeys,id:\.self){
                        Text(interestName($0,api)).tag($0)
                    }
                }
                Toggle(api.t("Private Circle","دائرة خاصة"),isOn:$privacy)
                if let error{
                    ErrorNotice(message:error)
                }
                BusyButton(title:api.t("Create Circle","إنشاء دائرة"),busy:busy){
                    Task{
                        busy=true
                        defer{
                            busy=false
                        }
                        do{
                            let _:IDResponse=try await api.request("circles",method:"POST",body:["name":name,"description":description,"rules":rules,"interest":interest,"private":privacy ? 1:0])
                            dismiss()
                        }
                        catch{
                            self.error=error.localizedDescription
                        }
                    }
                }
            }
            .navigationTitle(api.t("Create Circle","إنشاء دائرة")).toolbar{
                ToolbarItem(placement:.cancellationAction){
                    Button(api.t("Cancel","إلغاء")){
                        dismiss()
                    }
                }
            }
            .dismissKeyboardToolbar(api.t("Done","تم"))
        }
    }
}
struct CircleView:View {
    @EnvironmentObject var api:API
    @Environment(\.dismiss) var dismiss
    let circle:Circle
    @State private var current:Circle?
    @State private var kind="post"
    @State private var compose=false
    @State private var members=false
    @State private var leaving=false
    @State private var error:String?
    var c:Circle{
        current ?? circle
    }
    var body:some View{
        VStack(alignment:.leading){
            VStack(alignment:.leading,spacing:12){
                Text(c.description).font(.subheadline)
                DisclosureGroup(api.t("Circle rules","قواعد الدائرة")){
                    Text(c.rules).font(.caption)
                }
                if c.status=="accepted"{
                    HStack{
                        Button(api.t("Share with your Circle","شارك مع دائرتك")){
                            compose=true
                        }
                        .buttonStyle(.borderedProminent)
                        Button{
                            members=true
                        } label:{
                            Image(systemName:"person.2")
                        }
                        Button{
                            leaving=true
                        } label:{
                            Image(systemName:c.owner==api.user?.id ? "trash":"rectangle.portrait.and.arrow.right")
                        }
                    }
                }
                else{
                    Button(c.status=="pending" ? api.t("Requested","تم الطلب"):api.t("Join Circle","انضمام للدائرة")){
                        Task{
                            do{
                                let _:LooseResponse=try await api.request("circles/\(c.id)/join",method:"POST")
                                await load()
                            }
                            catch{
                                self.error=error.localizedDescription
                            }
                        }
                    }
                    .disabled(c.status=="pending")
                }
                if let error{
                    ErrorNotice(message:error)
                }
            }
            .padding()
            Picker(api.t("Circle section","قسم الدائرة"),selection:$kind){
                Text(api.t("Posts","منشورات")).tag("post")
                Text(api.t("Conversation","نقاش")).tag("conversation")
                Text(api.t("Questions","أسئلة")).tag("question")
            }
            .pickerStyle(.segmented).padding(.horizontal)
            if c.private==0||c.status=="accepted"{
                FeedView(path:"feed?circle=\(c.id)&kind=\(kind)")
            }
        }
        .navigationTitle(c.name).task{
            await load()
        }
        .sheet(isPresented:$compose){
            ComposerView(kind:kind,circleId:c.id)
        }
        .sheet(isPresented:$members){
            CircleMembersView(circle:c)
        }
        .confirmationDialog(c.owner==api.user?.id ? api.t("Delete Circle and its posts?","حذف الدائرة ومنشوراتها؟"):api.t("Leave Circle?","مغادرة الدائرة؟"),isPresented:$leaving){
            Button(api.t("Confirm","تأكيد"),role:.destructive){
                Task{
                    do{
                        let owner=c.owner==api.user?.id
                        let _:OK=try await api.request("circles/"+c.id+(owner ? "":"/leave"),method:owner ? "DELETE":"POST")
                        dismiss()
                    }
                    catch{
                        self.error=error.localizedDescription
                    }
                }
            }
        }
    }
    func load()async{
        do{
            let r:CircleResponse=try await api.request("circles/"+circle.id)
            current=r.circle
            error=nil
        }
        catch{
            if circle.private==0||circle.status=="accepted"{
                self.error=error.localizedDescription
            }
        }
    }
}
struct CircleMembersView:View {
    @EnvironmentObject var api:API
    @Environment(\.dismiss) var dismiss
    let circle:Circle
    @State private var members:[CircleMember]=[]
    @State private var reports:[ReportItem]=[]
    @State private var error:String?
    var mod:Bool{
        ["owner","moderator"].contains(circle.role ?? "")
    }
    var body:some View{
        NavigationStack{
            List{
                ForEach(members){
                    member in VStack(alignment:.leading,spacing:8){
                        Text(member.name).font(.headline)
                        Text(member.status=="pending" ? api.t("Membership request","طلب عضوية"):member.role).font(.caption)
                        if mod&&member.userId != circle.owner{
                            HStack{
                                if member.status=="pending"{
                                    Button(api.t("Accept","قبول")){
                                        operate(member.userId,"accept")
                                    }
                                }
                                Button(api.t("Remove","إزالة")){
                                    operate(member.userId,"remove")
                                }
                                if circle.owner==api.user?.id{
                                    Button(member.role=="moderator" ? api.t("Remove moderator","إلغاء الإشراف"):api.t("Make moderator","تعيين مشرف")){
                                        operate(member.userId,member.role=="moderator" ? "member":"moderator")
                                    }
                                }
                            }
                        }
                    }
                }
                if mod{
                    Section(api.t("Reports","البلاغات")){
                        ForEach(reports){
                            report in VStack(alignment:.leading){
                                Text(report.reason)
                                HStack{
                                    Button(api.t("Remove content","إزالة المحتوى")){
                                        review(report.id,true)
                                    }
                                    Button(api.t("Dismiss report","إغلاق البلاغ")){
                                        review(report.id,false)
                                    }
                                }
                            }
                        }
                    }
                }
                if let error{
                    ErrorNotice(message:error)
                }
            }
            .navigationTitle(api.t("Members & moderation","الأعضاء والإشراف")).task{
                await load()
            }
            .toolbar{
                ToolbarItem(placement:.cancellationAction){
                    Button(api.t("Close","إغلاق")){
                        dismiss()
                    }
                }
            }
        }
    }
    func load()async{
        do{
            let r:Page<CircleMember>=try await api.request("circles/\(circle.id)/members")
            members=r.items
            if mod{
                let r:Page<ReportItem>=try await api.request("reports?circle="+circle.id)
                reports=r.items
            }
        }
        catch{
            self.error=error.localizedDescription
        }
    }
    func operate(_ user:String,_ operation:String){
        Task{
            do{
                let _:OK=try await api.request("circles/\(circle.id)/members",method:"PATCH",body:["userId":user,"operation":operation])
                await load()
            }
            catch{
                self.error=error.localizedDescription
            }
        }
    }
    func review(_ id:String,_ remove:Bool){
        Task{
            do{
                let _:OK=try await api.request("reports/\(id)?circle=\(circle.id)",method:"PATCH",body:["remove":remove])
                await load()
            }
            catch{
                self.error=error.localizedDescription
            }
        }
    }
}
struct NotificationsView:View {
    @EnvironmentObject var api:API
    @State private var notices:[Notice]=[]
    @State private var requests:[Person]=[]
    @State private var error:String?
    var body:some View{
        List{
            ForEach(requests){
                person in HStack{
                    PersonLabel(person:person)
                    Button(api.t("Accept","قبول")){
                        respond(person.id,true)
                    }
                    Button(api.t("Decline","رفض")){
                        respond(person.id,false)
                    }
                }
            }
            ForEach(notices){
                notice in Button{
                    Task{
                        do{
                            let _:OK=try await api.request("notifications/"+notice.id,method:"POST")
                            api.route = ["message","message_request"].contains(notice.type) ? .conversation(notice.target):["like","comment"].contains(notice.type) ? .post(notice.target):.profile(notice.actor)
                            await load()
                        }
                        catch{
                            self.error=error.localizedDescription
                        }
                    }
                } label:{
                    HStack{
                        VStack(alignment:.leading){
                            Text(notice.name).font(.headline)
                            Text(label(notice.type)).font(.subheadline)
                        }
                        Spacer()
                        if notice.read==nil{
                            Text(api.t("New","جديد")).font(.caption).foregroundStyle(Ink.blue)
                        }
                    }
                }
            }
            if notices.isEmpty{
                QuietEmpty(icon:"bell",title:api.t("All quiet for now.","كل شيء هادئ الآن."),detail:api.t("New replies and connections will appear here.","ستظهر هنا الردود والتواصل الجديد."))
            }
            if let error{
                ErrorNotice(message:error)
            }
        }
        .navigationTitle(api.t("Notifications","الإشعارات")).task{
            await load()
        }
        .refreshable{
            await load()
        }
    }
    func label(_ key:String)->String{
        switch key{
            case "like":return api.t("Liked your post","أعجب بمنشورك")
            case "comment":return api.t("Replied to your post","رد على منشورك")
            case "follow_request":return api.t("Requested to follow you","طلب متابعتك")
            case "follow":return api.t("Connected with you","تواصل معك")
            case "message_request":return api.t("Sent a message request","أرسل طلب محادثة")
            default:return api.t("Sent a message","أرسل رسالة")
        }
    }
    func load()async{
        do{
            let r:Page<Notice>=try await api.request("notifications")
            notices=r.items
            let f:Page<Person>=try await api.request("requests")
            requests=f.items
            error=nil
        }
        catch{
            self.error=error.localizedDescription
        }
    }
    func respond(_ id:String,_ accept:Bool){
        Task{
            do{
                let _:OK=try await api.request("requests/"+id,method:"POST",body:["accept":accept])
                await load()
            }
            catch{
                self.error=error.localizedDescription
            }
        }
    }
}
struct SettingsView:View {
    @EnvironmentObject var api:API
    @Environment(\.dismiss) var dismiss
    @State private var error:String?
    @State private var deleting=false
    var body:some View{
        NavigationStack{
            Form{
                Section(api.t("Preferences","التفضيلات")){
                    Picker(api.t("Language","اللغة"),selection:Binding(get:{
                        api.user?.language ?? "en"
                    }
                    ,set:{
                        update(["language":$0])
                    }
                    )){
                        Text("English").tag("en")
                        Text("العربية").tag("ar")
                    }
                    Picker(api.t("Appearance","المظهر"),selection:Binding(get:{
                        api.user?.theme ?? "system"
                    }
                    ,set:{
                        update(["theme":$0])
                    }
                    )){
                        Text(api.t("System","النظام")).tag("system")
                        Text(api.t("Light","فاتح")).tag("light")
                        Text(api.t("Dark","داكن")).tag("dark")
                    }
                }
                Section(api.t("Privacy","الخصوصية")){
                    Toggle(api.t("Private account","حساب خاص"),isOn:Binding(get:{
                        api.user?.private==1
                    }
                    ,set:{
                        update(["private":$0 ? 1:0])
                    }
                    ))
                    Toggle(api.t("Read receipts","إيصالات القراءة"),isOn:Binding(get:{
                        api.user?.receipts==1
                    }
                    ,set:{
                        update(["receipts":$0 ? 1:0])
                    }
                    ))
                    Toggle(api.t("Typing indicator","مؤشر الكتابة"),isOn:Binding(get:{
                        api.user?.activity==1
                    }
                    ,set:{
                        update(["activity":$0 ? 1:0])
                    }
                    ))
                    Picker(api.t("Messages from","الرسائل من"),selection:Binding(get:{
                        api.user?.messages ?? "requests"
                    }
                    ,set:{
                        update(["messages":$0])
                    }
                    )){
                        Text(api.t("Everyone","الجميع")).tag("everyone")
                        Text(api.t("Message requests","طلبات الرسائل")).tag("requests")
                        Text(api.t("People I follow","من أتابعهم")).tag("following")
                        Text(api.t("Nobody","لا أحد")).tag("nobody")
                    }
                    NavigationLink(api.t("Blocked accounts","الحسابات المحظورة")){
                        BlockedView()
                    }
                }
                Section(api.t("Notifications","الإشعارات")){
                    ForEach(["like","comment","follow","follow_request","message_request","message"],id:\.self){
                        key in Toggle(notificationLabel(key),isOn:Binding(get:{
                            api.user?.notifications?.contains(key) ?? false
                        }
                        ,set:{
                            value in var n=api.user?.notifications ?? []
                            n.removeAll{
                                $0==key
                            }
                            if value{
                                n.append(key)
                            }
                            update(["notifications":n])
                        }
                        ))
                    }
                    Button(api.t("Enable push notifications","تفعيل الإشعارات")){
                        Task{
                            do{
                                let allowed=try await UNUserNotificationCenter.current().requestAuthorization(options:[.alert,.badge,.sound])
                                if allowed{
                                    UIApplication.shared.registerForRemoteNotifications()
                                }
                                else{
                                    error=api.t("Notifications are disabled. You can change this in Settings.","الإشعارات معطلة. يمكنك تعديل ذلك من الإعدادات.")
                                }
                            }
                            catch{
                                self.error=error.localizedDescription
                            }
                        }
                    }
                    .disabled(!api.pushConfigured)
                    if !api.pushConfigured { Text(api.t("Push is not configured on this server yet. In-app notifications are available.", "الإشعارات الفورية غير مفعلة على الخادم بعد. إشعارات التطبيق متاحة.")).font(.caption).foregroundStyle(.secondary) }
                }
                if let error{
                    ErrorNotice(message:error)
                }
                Button(api.t("Sign out","تسجيل الخروج")){
                    Task{
                        do{
                            try await api.logout()
                            dismiss()
                        }
                        catch{
                            self.error=error.localizedDescription
                        }
                    }
                }
                Button(api.t("Delete account","حذف الحساب"),role:.destructive){
                    deleting=true
                }
            }
            .navigationTitle(api.t("Settings","الإعدادات")).toolbar{
                ToolbarItem(placement:.cancellationAction){
                    Button(api.t("Close","إغلاق")){
                        dismiss()
                    }
                }
            }
            .confirmationDialog(api.t("Permanently delete your account and content?","حذف حسابك ومحتواه نهائيًا؟"),isPresented:$deleting){
                Button(api.t("Delete permanently","حذف نهائيًا"),role:.destructive){
                    Task{
                        do{
                            let _:OK=try await api.request("me",method:"DELETE")
                            api.endSession()
                            dismiss()
                        }
                        catch{
                            self.error=error.localizedDescription
                        }
                    }
                }
            }
        }
    }
    func update(_ values:[String:Any]){
        Task{
            do{
                try await api.update(values)
            }
            catch{
                self.error=error.localizedDescription
            }
        }
    }
    func notificationLabel(_ key:String)->String{
        switch key{
            case "like":return api.t("Reactions","التفاعلات")
            case "comment":return api.t("Replies","الردود")
            case "follow":return api.t("Follows","المتابعات")
            case "follow_request":return api.t("Follow requests","طلبات المتابعة")
            case "message_request":return api.t("Message requests","طلبات الرسائل")
            default:return api.t("Messages","الرسائل")
        }
    }
}
struct BlockedView:View {
    @EnvironmentObject var api:API
    @State private var people:[Person]=[]
    @State private var error:String?
    var body:some View{
        List{
            ForEach(people){
                person in HStack{
                    Text(person.name)
                    Spacer()
                    Button(api.t("Unblock","إلغاء الحظر")){
                        Task{
                            do{
                                let _:OK=try await api.request("blocks/"+person.id,method:"DELETE")
                                await load()
                            }
                            catch{
                                self.error=error.localizedDescription
                            }
                        }
                    }
                }
            }
            if let error{
                ErrorNotice(message:error)
            }
        }
        .task{
            await load()
        }
        .navigationTitle(api.t("Blocked accounts","الحسابات المحظورة"))
    }
    func load()async{
        do{
            let r:Page<Person>=try await api.request("blocks")
            people=r.items
        }
        catch{
            self.error=error.localizedDescription
        }
    }
}
