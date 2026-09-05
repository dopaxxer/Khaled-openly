import SwiftUI
import PhotosUI
struct HomeView:View {
    @EnvironmentObject var api:API
    @State private var mode="for-you"
    @State private var moment=false
    @State private var moments:[Post]=[]
    var body:some View{
        VStack(spacing:0){
            Picker(api.t("Feed","المنشورات"),selection:$mode){
                Text(api.t("For You","لك")).tag("for-you")
                Text(api.t("Following","المتابَعون")).tag("following")
            }
            .pickerStyle(.segmented).padding()
            ScrollView(.horizontal){
                HStack(spacing:18){
                    Button{
                        moment=true
                    } label:{
                        VStack{
                            Image(systemName:"plus.circle.dashed").font(.largeTitle)
                            Text(api.t("Your moment","لحظتك")).font(.caption)
                        }
                    }
                    ForEach(moments.filter{
                        ($0.expires ?? 0)>Date().timeIntervalSince1970*1000
                    }
                    ){
                        p in NavigationLink{
                            MomentView(post:p)
                        } label:{
                            VStack{
                                AvatarView(person:p.name,media:p.avatar,size:50)
                                Text(p.name).font(.caption)
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom,12)
            FeedView(path:"feed?mode=\(mode)" + (mode == "following" ? "&sort=chronological" : "")).id(mode)
        }
        .task{
            let r:Page<Post>?=try? await api.request("feed?kind=moment")
            moments=r?.items ?? []
        }
        .sheet(isPresented:$moment){
            ComposerView(kind:"moment")
        }
    }
}
struct FeedView:View {
    @EnvironmentObject var api:API
    let path:String
    @State private var posts:[Post]=[]
    @State private var next:Cursor?
    @State private var error:String?
    @State private var loading=true
    var body:some View{
        ScrollView{
            LazyVStack(spacing:0){
                if loading{
                    ProgressView().padding(40)
                }
                else if let error{
                    ErrorNotice(message:error,retry:{
                        Task{
                            await load()
                        }
                    }
                    )
                }
                else if posts.isEmpty{
                    QuietEmpty(icon:"square.and.pencil",title:api.t("A space waiting for a thought.","مساحة تنتظر فكرة."),detail:api.t("Share something or discover people with shared interests.","شارك شيئًا أو اكتشف أشخاصًا يجمعك بهم اهتمام."))
                }
                ForEach(posts){
                    p in PostRow(post:p,onChange:{
                        Task{
                            await load()
                        }
                    }
                    )
                    Divider()
                }
                if next != nil{
                    Button(api.t("Load more","عرض المزيد")){
                        Task{
                            await load(more:true)
                        }
                    }
                    .padding()
                }
            }
        }
        .refreshable{
            await load()
        }
        .task(id:path){
            await load()
        }
        .scrollDismissesKeyboard(.interactively)
    }
    func load(more:Bool=false) async{
        do{
            var target=path
            if more,let next{
                target += (path.contains("?") ? "&":"?")+"before=\(Int(next.before))&cursor=\(next.cursor)&score=\(next.score ?? 0)"
            }
            let r:Page<Post>=try await api.request(target)
            posts=more ? posts+r.items:r.items
            next=r.next
            error=nil
        }
        catch{
            self.error=error.localizedDescription
        }
        loading=false
    }
}
struct PostRow:View {
    @EnvironmentObject var api:API
    let post:Post
    var onChange:()->Void={
    }
    @State private var save=false
    @State private var report=false
    @State private var edit=false
    @State private var delete=false
    @State private var image=false
    @State private var error:String?
    var body:some View{
        VStack(alignment:.leading,spacing:14){
            HStack{
                NavigationLink{
                    ProfileView(id:post.author)
                } label:{
                    HStack{
                        AvatarView(person:post.name,media:post.avatar)
                        VStack(alignment:.leading){
                            Text(post.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                            Text("@"+post.username).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
                if post.pinned==1{
                    Image(systemName:"pin.fill").font(.caption).foregroundStyle(Ink.blue)
                }
                Menu{
                    if post.author==api.user?.id{
                        Button(api.t("Edit","تعديل")){
                            edit=true
                        }
                        Button(post.pinned==1 ? api.t("Unpin","إلغاء التثبيت"):api.t("Pin to My Space","تثبيت في مساحتي")){
                            action("posts/"+post.id,"PATCH",["pinned":post.pinned==1 ? 0:1])
                        }
                        Button(api.t("Delete","حذف"),role:.destructive){
                            delete=true
                        }
                    }
                    else{
                        Button(api.t("Show less like this","إخفاء وتقليل هذا المحتوى")){
                            action("posts/\(post.id)/hide","POST")
                        }
                        Button(api.t("Report","إبلاغ")){
                            report=true
                        }
                    }
                } label:{
                    Image(systemName:"ellipsis").frame(width:40,height:40)
                }
            }
            if !post.body.isEmpty{
                Text(post.body).font(.body).textSelection(.enabled)
            }
            if let id=post.image{
                Button{
                    image=true
                } label:{
                    SecureImage(id:id).frame(maxWidth:.infinity).frame(height:260).clipped().clipShape(RoundedRectangle(cornerRadius:8))
                }
            }
            if let song=post.song{
                SongView(song:song)
            }
            HStack(spacing:24){
                Button{
                    action("posts/\(post.id)/like",post.liked==1 ? "DELETE":"POST")
                } label:{
                    Label("\(post.likes ?? 0)",systemImage:post.liked==1 ? "heart.fill":"heart")
                }
                NavigationLink{
                    PostDetailView(id:post.id)
                } label:{
                    Label("\(post.comments ?? 0)",systemImage:"bubble.left")
                }
                ShareLink(item:api.origin.appending(queryItems:[URLQueryItem(name:"post",value:post.id)])){
                    Image(systemName:"square.and.arrow.up")
                }
                Spacer()
                Button{
                    save=true
                } label:{
                    Image(systemName:post.saved==1 ? "bookmark.fill":"bookmark")
                }
                .accessibilityLabel(api.t("Save","حفظ"))
            }
            .font(.subheadline).foregroundStyle(.secondary)
            Text(Date(timeIntervalSince1970:post.created/1000),style:.date).font(.caption2).foregroundStyle(.secondary)
            if let error{
                ErrorNotice(message:error)
            }
        }
        .padding(20).sheet(isPresented:$save){
            CollectionsView(savePost:post.id)
        }
        .sheet(isPresented:$report){
            ReportView(kind:"post",target:post.id)
        }
        .sheet(isPresented:$edit){
            ComposerView(edit:post)
        }
        .sheet(isPresented:$image){
            NavigationStack{
                if let id=post.image{
                    SecureImage(id:id).scaledToFit().padding()
                }
            }
        }
        .confirmationDialog(api.t("Delete this post?","حذف هذا المنشور؟"),isPresented:$delete,titleVisibility:.visible){
            Button(api.t("Delete","حذف"),role:.destructive){
                action("posts/"+post.id,"DELETE")
            }
        }
    }
    func action(_ path:String,_ method:String,_ body:[String:Any]?=nil){
        Task{
            do{
                let _:LooseResponse=try await api.request(path,method:method,body:body)
                onChange()
            }
            catch{
                self.error=error.localizedDescription
            }
        }
    }
}
struct LooseResponse:Decodable{
}
struct ComposerView:View {
    @EnvironmentObject var api:API
    @Environment(\.dismiss) var dismiss
    var kind="post"
    var circleId:String?
    var edit:Post?
    @State private var text=""
    @State private var audience="public"
    @State private var mood=""
    @State private var photo:PhotosPickerItem?
    @State private var image:String?
    @State private var song:Song?
    @State private var songPicker=false
    @State private var camera=false
    @State private var busy=false
    @State private var error:String?
    @State private var id=UUID().uuidString.lowercased()
    @State private var loaded=false
    var draftKey:String{
        "openly.\(api.user?.id ?? "").draft.\(kind).\(circleId ?? "main")"
    }
    var bodyView:some View{
        Form{
            Section{
                TextField(api.t("What’s on your mind?","بماذا تفكر؟"),text:$text,axis:.vertical).lineLimit(5...12)
                Text("\(text.count)/1500").font(.caption).foregroundStyle(.secondary)
            }
            if let image{
                SecureImage(id:image).frame(height:200).clipped()
                if edit==nil{
                    Button(api.t("Remove image","إزالة الصورة")){
                        self.image=nil
                    }
                }
            }
            if let song{
                SongView(song:song)
                if edit==nil{
                    Button(api.t("Remove song","إزالة الأغنية")){
                        self.song=nil
                    }
                }
            }
            if edit==nil{
                Section{
                    PhotosPicker(selection:$photo,matching:.images){
                        Label(api.t("Choose photo","اختيار صورة"),systemImage:"photo")
                    }
                    Button{
                        camera=true
                    } label:{
                        Label(api.t("Take photo","التقاط صورة"),systemImage:"camera")
                    }
                    Button{
                        songPicker=true
                    } label:{
                        Label(api.t("Add song","إضافة أغنية"),systemImage:"music.note")
                    }
                }
            }
            if kind=="moment"{
                TextField(api.t("Mood (optional)","المزاج (اختياري)"),text:$mood)
                Text(api.t("Expires 24 hours after publishing.","تنتهي بعد 24 ساعة من النشر.")).font(.caption)
            }
            Picker(api.t("Audience","الجمهور"),selection:$audience){
                Text(api.t("Everyone","الجميع")).tag("public")
                Text(api.t("Followers","المتابعون")).tag("followers")
                Text(api.t("Only me","أنا فقط")).tag("only_me")
            }
            if let error{
                ErrorNotice(message:error)
            }
            BusyButton(title:api.t("Share","مشاركة"),busy:busy){
                publish()
            }
            .disabled((text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && image==nil && song==nil)||text.count>1500)
        }
        .scrollDismissesKeyboard(.interactively)
    }
    var body:some View{
        NavigationStack{
            bodyView.navigationTitle(edit==nil ? api.t("A thought to share","فكرة تستحق المشاركة"):api.t("Edit post","تعديل المنشور")).navigationBarTitleDisplayMode(.inline).toolbar{
                ToolbarItem(placement:.cancellationAction){
                    Button(api.t("Close","إغلاق")){
                        saveDraft()
                        dismiss()
                    }
                }
            }
            .dismissKeyboardToolbar(api.t("Done","تم"))
        }
        .task{
            if let edit{
                text=edit.body
                image=edit.image
                song=edit.song
                audience=edit.audience
            }
            else if let data=UserDefaults.standard.data(forKey:draftKey),let d=try? JSONDecoder().decode(PostDraft.self,from:data){
                text=d.body
                image=d.image
                song=d.song
                audience=d.audience
                id=d.id
                mood=d.mood
            }
            loaded=true
        }
        .onChange(of:text){
            _,_ in saveDraft()
        }
        .onChange(of:audience){
            _,_ in saveDraft()
        }
        .onChange(of:song){
            _,_ in saveDraft()
        }
        .onChange(of:image){
            _,_ in saveDraft()
        }
        .onChange(of:photo){
            _,new in Task{
                busy=true
                defer{
                    busy=false
                }
                do{
                    if let data=try await new?.loadTransferable(type:Data.self),let picture=UIImage(data:data),let jpeg=picture.preparingThumbnail(of:CGSize(width:1800,height:1800))?.jpegData(compressionQuality:0.85) ?? picture.jpegData(compressionQuality:0.85){
                        image=try await api.upload(jpeg,type:"image/jpeg")
                    }
                }
                catch{
                    self.error=error.localizedDescription
                }
            }
        }
        .sheet(isPresented:$songPicker){
            SongPickerView{
                song=$0
                songPicker=false
            }
        }
        .sheet(isPresented:$camera){
            CameraView{
                picture in camera=false
                Task{
                    busy=true
                    defer{
                        busy=false
                    }
                    do{
                        if let data=picture.jpegData(compressionQuality:0.8){
                            image=try await api.upload(data,type:"image/jpeg")
                        }
                    }
                    catch{
                        self.error=error.localizedDescription
                    }
                }
            }
        }
        .onDisappear{
            saveDraft()
        }
    }
    func saveDraft(){
        guard loaded,edit==nil else{
            return
        }
        let draft=PostDraft(id:id,body:text,image:image,song:song,audience:audience,mood:mood)
        if let data=try? JSONEncoder().encode(draft){
            UserDefaults.standard.set(data,forKey:draftKey)
        }
    }
    func publish(){
        Task{
            guard !busy else{
                return
            }
            busy=true
            defer{
                busy=false
            }
            do{
                if let edit{
                    let _:LooseResponse=try await api.request("posts/"+edit.id,method:"PATCH",body:["body":text,"audience":audience])
                }
                else{
                    var values:[String:Any]=["id":id,"body":text,"audience":audience,"kind":kind,"mood":mood]
                    if let image{
                        values["image"]=image
                    }
                    if let circleId{
                        values["circleId"]=circleId
                    }
                    if let song{
                        values["song"]=try JSONSerialization.jsonObject(with:JSONEncoder().encode(song))
                    }
                    let _:PostResponse=try await api.request("posts",method:"POST",body:values)
                }
                loaded=false
                UserDefaults.standard.removeObject(forKey:draftKey)
                dismiss()
            }
            catch{
                self.error=error.localizedDescription
            }
        }
    }
}
struct PostDraft:Codable {
    let id:String
    let body:String
    let image:String?
    let song:Song?
    let audience:String
    let mood:String
}
struct CameraView:UIViewControllerRepresentable {
    let onPhoto:(UIImage)->Void
    @Environment(\.dismiss) var dismiss
    func makeCoordinator()->Coordinator{
        Coordinator(self)
    }
    func makeUIViewController(context:Context)->UIImagePickerController{
        let picker=UIImagePickerController()
        picker.sourceType=UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera:.photoLibrary
        picker.delegate=context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController:UIImagePickerController,context:Context){
    }
    class Coordinator:NSObject,UINavigationControllerDelegate,UIImagePickerControllerDelegate{
        let parent:CameraView
        init(_ p:CameraView){
            parent=p
        }
        func imagePickerController(_ picker:UIImagePickerController,didFinishPickingMediaWithInfo info:[UIImagePickerController.InfoKey:Any]){
            if let image=info[.originalImage] as? UIImage{
                parent.onPhoto(image)
            }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker:UIImagePickerController){
            parent.dismiss()
        }
    }
}
struct SongPickerView:View {
    @EnvironmentObject var api:API
    @Environment(\.dismiss) var dismiss
    let onPick:(Song)->Void
    @State private var query=""
    @State private var songs:[Song]=[]
    @State private var error:String?
    var body:some View{
        NavigationStack{
            List{
                if let error{
                    ErrorNotice(message:error)
                }
                ForEach(songs){
                    song in Button{
                        onPick(song)
                    } label:{
                        HStack{
                            Text(song.title)
                            Spacer()
                            Text(song.artist).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .searchable(text:$query,prompt:api.t("Song or artist","أغنية أو فنان")).task(id:query){
                guard query.count>1 else{
                    songs=[]
                    return
                }
                do{
                    try await Task.sleep(for:.milliseconds(350))
                    let r:Page<Song>=try await api.request("music?q="+(query.addingPercentEncoding(withAllowedCharacters:.urlQueryAllowed) ?? ""))
                    songs=r.items
                    error=nil
                }
                catch{
                    if !Task.isCancelled{
                        self.error=error.localizedDescription
                    }
                }
            }
            .navigationTitle(api.t("Find a song","ابحث عن أغنية")).toolbar{
                ToolbarItem(placement:.cancellationAction){
                    Button(api.t("Close","إغلاق")){
                        dismiss()
                    }
                }
            }
        }
    }
}
struct PostDetailView:View {
    @EnvironmentObject var api:API
    let id:String
    @State private var post:Post?
    @State private var comments:[Comment]=[]
    @State private var text=""
    @State private var parent:Comment?
    @State private var error:String?
    @State private var busy=false
    @State private var commentId=UUID().uuidString.lowercased()
    var body:some View{
        ScrollView{
            LazyVStack(alignment:.leading){
                if let post{
                    PostRow(post:post)
                }
                if let error{
                    ErrorNotice(message:error,retry:{
                        Task{
                            await load()
                        }
                    }
                    )
                }
                ForEach(comments){
                    cm in VStack(alignment:.leading,spacing:8){
                        Text(cm.name).font(.subheadline.bold())
                        Text(cm.body)
                        Button(api.t("Reply","رد")){
                            parent=cm
                        }
                        .font(.caption)
                    }
                    .padding().padding(.leading,cm.parent==nil ? 0:18)
                }
            }
        }
        .safeAreaInset(edge:.bottom){
            VStack{
                if let parent{
                    HStack{
                        Text(api.t("Replying to ","ردًا على ")+parent.name)
                        Spacer()
                        Button{
                            self.parent=nil
                        } label:{
                            Image(systemName:"xmark")
                        }
                    }
                }
                HStack{
                    TextField(api.t("Add a reply…","أضف ردًا…"),text:$text,axis:.vertical).textFieldStyle(.roundedBorder)
                    Button{
                        Task{
                            busy=true
                            defer{
                                busy=false
                            }
                            do{
                                var values:[String:Any]=["id":commentId,"body":text]
                                if let parent{
                                    values["parent"]=parent.id
                                }
                                let _:OK=try await api.request("posts/\(id)/comments",method:"POST",body:values)
                                text=""
                                self.parent=nil
                                commentId=UUID().uuidString.lowercased()
                                await load()
                            }
                            catch{
                                self.error=error.localizedDescription
                            }
                        }
                    } label:{
                        Image(systemName:"paperplane.fill")
                    }
                    .disabled(text.isEmpty||busy)
                }
            }
            .padding().background(.bar)
        }
        .task{
            await load()
        }
        .navigationTitle(api.t("Conversation","نقاش")).dismissKeyboardToolbar(api.t("Done","تم"))
    }
    func load()async{
        do{
            let p:PostResponse=try await api.request("posts/"+id)
            post=p.post
            let c:Page<Comment>=try await api.request("posts/\(id)/comments")
            comments=c.items
            error=nil
        }
        catch{
            self.error=error.localizedDescription
        }
    }
}
struct MomentView:View {
    @EnvironmentObject var api:API
    @Environment(\.dismiss) var dismiss
    let post:Post
    @State private var error:String?
    var body:some View{
        TimelineView(.periodic(from:.now,by:30)){
            context in VStack(spacing:20){
                if (post.expires ?? 0)<=context.date.timeIntervalSince1970*1000{
                    Text(api.t("This Moment has expired.","انتهت صلاحية هذه اللحظة."))
                }
                else{
                    Text(post.name).font(.headline)
                    if let mood=post.mood{
                        Text(mood).foregroundStyle(.secondary)
                    }
                    Text(post.body)
                    if let image=post.image{
                        SecureImage(id:image).frame(height:300).clipped()
                    }
                    if let song=post.song{
                        SongView(song:song)
                    }
                    Button(post.author==api.user?.id ? api.t("Delete Moment","حذف اللحظة"):api.t("Reply privately","رد برسالة خاصة")){
                        Task{
                            do{
                                if post.author==api.user?.id{
                                    let _:OK=try await api.request("posts/"+post.id,method:"DELETE")
                                    dismiss()
                                }
                                else{
                                    let c:ConversationResponse=try await api.request("conversations",method:"POST",body:["userId":post.author])
                                    api.route = .conversation(c.conversation.id)
                                }
                            }
                            catch{
                                self.error=error.localizedDescription
                            }
                        }
                    }
                }
                if let error{
                    ErrorNotice(message:error)
                }
            }
            .padding()
        }
    }
}
