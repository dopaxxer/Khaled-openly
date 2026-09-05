import SwiftUI
import PhotosUI
import AVFoundation
import AVKit
struct ConversationsView:View {
    @EnvironmentObject var api:API
    @State private var items:[Conversation]=[]
    @State private var requests=false
    @State private var error:String?
    var body:some View{
        List{
            Toggle(api.t("Message requests only","طلبات الرسائل فقط"),isOn:$requests)
            ForEach(items.filter{
                !requests||$0.status=="pending"
            }
            ){
                c in NavigationLink{
                    ChatView(cid:c.id,name:c.name ?? api.t("Conversation","محادثة"),conversation:c)
                } label:{
                    HStack{
                        AvatarView(person:c.name ?? "O",media:c.avatar)
                        VStack(alignment:.leading){
                            Text(c.name ?? "Openly").font(.headline)
                            Text(c.lastBody ?? api.t("Start a conversation","ابدأ محادثة")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        if c.status=="pending"{
                            Text(api.t("Request","طلب")).font(.caption)
                        }
                        if (c.unread ?? 0)>0{
                            Text("\(c.unread!)").font(.caption).foregroundStyle(Ink.blue)
                        }
                    }
                }
            }
            if items.isEmpty{
                QuietEmpty(icon:"bubble.left.and.bubble.right",title:api.t("Good conversations start small.","المحادثات الجميلة تبدأ ببساطة."),detail:api.t("Discover someone and say hello.","اكتشف شخصًا وقل مرحبًا."))
            }
            if let error{
                ErrorNotice(message:error)
            }
        }
        .refreshable{
            await load()
        }
        .task{
            while !Task.isCancelled{
                await load()
                try? await Task.sleep(for:.seconds(10))
            }
        }
    }
    func load()async{
        do{
            let r:Page<Conversation>=try await api.request("conversations")
            items=r.items
            error=nil
        }
        catch{
            self.error=error.localizedDescription
        }
    }
}
@MainActor final class VoiceRecorder:ObservableObject {
    @Published var recording=false
    private var recorder:AVAudioRecorder?
    private var file:URL?
    func start()async throws{
        let allowed=await withCheckedContinuation{
            continuation in AVAudioApplication.requestRecordPermission{
                continuation.resume(returning:$0)
            }
        }
        guard allowed else{
            throw OpenlyError(code:"Microphone access was denied. Enable it in Settings.")
        }
        try AVAudioSession.sharedInstance().setCategory(.playAndRecord,mode:.default,options:[.defaultToSpeaker,.allowBluetoothHFP])
        try AVAudioSession.sharedInstance().setActive(true)
        let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".m4a")
        file=url
        recorder=try AVAudioRecorder(url:url,settings:[AVFormatIDKey:kAudioFormatMPEG4AAC,AVSampleRateKey:44100,AVNumberOfChannelsKey:1,AVEncoderAudioQualityKey:AVAudioQuality.high.rawValue])
        recorder?.record(forDuration:120)
        recording=true
    }
    func stop()throws->Data?{
        recorder?.stop()
        recording=false
        try? AVAudioSession.sharedInstance().setActive(false)
        guard let file else{
            return nil
        }
        defer{
            try? FileManager.default.removeItem(at:file)
        }
        return try Data(contentsOf:file)
    }
    func cancel(){
        recorder?.stop()
        recording=false
        if let file{
            try? FileManager.default.removeItem(at:file)
        }
        try? AVAudioSession.sharedInstance().setActive(false)
    }
}
struct ChatView:View {
    @EnvironmentObject var api:API
    @Environment(\.scenePhase) var scenePhase
    let cid:String
    let name:String
    var conversation:Conversation?
    @State private var messages:[Message]=[]
    @State private var pending:[PendingMessage]=[]
    @State private var draft=""
    @State private var reply:Message?
    @State private var photo:PhotosPickerItem?
    @State private var media:String?
    @State private var busy=false
    @State private var loading=true
    @State private var error:String?
    @State private var status="accepted"
    @State private var typing=false
    @State private var bottom=true
    @State private var newMessages=false
    @State private var scrollTarget:String?
    @State private var next:Cursor?
    @State private var report:Message?
    @State private var muted=false
    @State private var current:Conversation?
    @State private var id=UUID().uuidString.lowercased()
    @StateObject private var voice=VoiceRecorder()
    var localKey:String{
        "openly.\(api.user?.id ?? "").chat.\(cid)"
    }
    var content:some View{
        VStack(spacing:0){
            if status=="pending"{
                VStack{
                    Text(api.t("Message request. One text introduction is allowed until accepted.","طلب محادثة. يُسمح برسالة تعريفية واحدة حتى القبول.")).font(.caption)
                    if let c=current,c.initiator != api.user?.id{
                        HStack{
                            Button(api.t("Accept","قبول")){
                                setRequest(true)
                            }
                            Button(api.t("Decline","رفض")){
                                setRequest(false)
                            }
                        }
                    }
                }
                .padding().background(Ink.blue.opacity(0.06))
            }
            if typing{
                Text(api.t("Typing…","يكتب الآن…")).font(.caption).foregroundStyle(.secondary)
            }
            transcript
            if let error{
                ErrorNotice(message:error,retry:{
                    Task{
                        await load()
                    }
                }
                )
            }
            composer
        }
    }
    var body:some View {
        content
        .navigationTitle(name).navigationBarTitleDisplayMode(.inline).toolbar{
            ToolbarItem(placement:.topBarTrailing){
                Button{
                    Task{
                        do{
                            let _:OK=try await api.request("conversations/\(cid)/state",method:"PATCH",body:["muted":muted ? 0:1])
                            muted.toggle()
                        }
                        catch{
                            self.error=error.localizedDescription
                        }
                    }
                } label:{
                    Image(systemName:muted ? "bell.slash.fill":"bell.slash")
                }
            }
        }
        .dismissKeyboardToolbar(api.t("Done","تم")).task{
            current=conversation
            if current==nil{
                let list:Page<Conversation>?=try? await api.request("conversations")
                current=list?.items.first{
                    $0.id==cid
                }
            }
            status=current?.status ?? "accepted"
            let state:StateResponse?=try? await api.request("conversations/\(cid)/state")
            draft=UserDefaults.standard.string(forKey:localKey) ?? state?.state?.draft ?? ""
            muted=state?.state?.muted==1
            await load()
            for await _ in api.updates(cid){
                if Task.isCancelled{
                    break
                }
                await load()
            }
        }
        .task(id:draft){
            UserDefaults.standard.set(draft,forKey:localKey)
            do{
                try await Task.sleep(for:.milliseconds(700))
                let _:OK=try await api.request("conversations/\(cid)/state",method:"PATCH",body:["draft":draft,"typing":!draft.isEmpty])
            }
            catch{
            }
        }
        .onDisappear{
            voice.cancel()
            UserDefaults.standard.set(draft,forKey:localKey)
        }
        .onChange(of:photo){
            _,item in Task{
                busy=true
                defer{
                    busy=false
                }
                do{
                    if let data=try await item?.loadTransferable(type:Data.self),let jpeg=UIImage(data:data)?.jpegData(compressionQuality:0.8){
                        media=try await api.upload(jpeg,type:"image/jpeg")
                    }
                }
                catch{
                    self.error=error.localizedDescription
                }
            }
        }
        .sheet(item:$report){
            m in ReportView(kind:"message",target:m.id)
        }
    }
    var transcript: some View {
            ScrollViewReader{
                proxy in ScrollView{
                    LazyVStack(spacing:14){
                        if let next{
                            Button(api.t("Earlier messages","رسائل أقدم")){
                                Task{
                                    let anchor=messages.first?.id
                                    do{
                                        let p:MessagePage=try await api.request("conversations/\(cid)/messages?before=\(Int(next.before))&cursor=\(next.cursor)")
                                        messages=p.items.filter{
                                            m in !messages.contains{
                                                $0.id==m.id
                                            }
                                        } + messages
                                        self.next=p.next
                                        if let anchor{
                                            proxy.scrollTo(anchor,anchor:.top)
                                        }
                                    }
                                    catch{
                                        self.error=error.localizedDescription
                                    }
                                }
                            }
                        }
                        if loading{
                            ProgressView()
                        }
                        ForEach(messages){
                            m in messageRow(m).id(m.id)
                        }
                        ForEach(pending){
                            p in HStack{
                                Spacer()
                                VStack(alignment:.trailing){
                                    Text(p.body)
                                    Text(p.failed ? api.t("Failed","تعذّر الإرسال"):api.t("Pending","قيد الإرسال")).font(.caption)
                                    if p.failed{
                                        Button(api.t("Retry","إعادة المحاولة")){
                                            send(p)
                                        }
                                    }
                                }
                                .padding(12).background(Ink.blue.opacity(0.08),in:RoundedRectangle(cornerRadius:10))
                            }
                            .id(p.id)
                        }
                        Color.clear.frame(height:1).id("bottom").onAppear{
                            bottom=true
                            newMessages=false
                            Task{
                                await acknowledge(read:true)
                            }
                        }
                        .onDisappear{
                            bottom=false
                        }
                    }
                    .padding().scrollTargetLayout()
                }
                .scrollDismissesKeyboard(.interactively).onChange(of:messages.count){
                    _,_ in if bottom{
                        proxy.scrollTo("bottom",anchor:.bottom)
                    }
                    else{
                        newMessages=true
                    }
                }
                .overlay(alignment:.bottom){
                    if newMessages{
                        Button{
                            proxy.scrollTo("bottom",anchor:.bottom)
                            newMessages=false
                        } label:{
                            Label(api.t("New messages","رسائل جديدة"),systemImage:"arrow.down")
                        }
                        .buttonStyle(.borderedProminent).padding()
                    }
                }
            }
    }
    @ViewBuilder var composer:some View{
        VStack(spacing:8){
            if let reply{
                HStack{
                    Text(api.t("Reply to: ","رد على: ")+String(reply.body.prefix(60))).font(.caption)
                    Spacer()
                    Button{
                        self.reply=nil
                    } label:{
                        Image(systemName:"xmark")
                    }
                }
            }
            if media != nil{
                HStack{
                    Text(api.t("Attachment ready","المرفق جاهز")).font(.caption)
                    Spacer()
                    Button{
                        media=nil
                    } label:{
                        Image(systemName:"xmark")
                    }
                }
            }
            if voice.recording{
                Text(api.t("Recording — tap stop. Maximum 2 minutes.","جارٍ التسجيل — اضغط إيقاف. الحد الأقصى دقيقتان.")).font(.caption).foregroundStyle(.red)
            }
            HStack{
                PhotosPicker(selection:$photo,matching:.images){
                    Image(systemName:"photo")
                }
                .disabled(busy||status != "accepted")
                TextField(api.t("Write a message…","اكتب رسالة…"),text:$draft,axis:.vertical).lineLimit(1...5).textFieldStyle(.roundedBorder)
                Button{
                    Task{
                        do{
                            if voice.recording{
                                if let data=try voice.stop(){
                                    busy=true
                                    defer{
                                        busy=false
                                    }
                                    media=try await api.upload(data,type:"audio/mp4")
                                }
                            }
                            else{
                                try await voice.start()
                            }
                        }
                        catch{
                            self.error=api.t("Microphone access or recording failed. Check Settings or send text.","تعذّر الوصول للميكروفون أو التسجيل. تحقق من الإعدادات أو أرسل نصًا.")
                        }
                    }
                } label:{
                    Image(systemName:voice.recording ? "stop.circle.fill":"mic")
                }
                .disabled(busy||status != "accepted")
                Button{
                    send()
                } label:{
                    Image(systemName:"paperplane.fill")
                }
                .disabled(busy||voice.recording||(draft.isEmpty&&media==nil)||status=="declined")
            }
        }
        .padding(12).background(.bar)
    }
    @ViewBuilder func messageRow(_ m:Message)->some View{
        HStack{
            if m.sender==api.user?.id{
                Spacer(minLength:42)
            }
            VStack(alignment:.leading,spacing:7){
                if let replyId=m.replyTo{
                    Text(api.t("Reply: ","رد: ")+(messages.first{
                        $0.id==replyId
                    }?.body ?? api.t("Earlier message","رسالة سابقة"))).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                if let media=m.media{
                    MessageAttachment(id:media)
                }
                if !m.body.isEmpty{
                    Text(m.body).textSelection(.enabled)
                }
                HStack{
                    Text(Date(timeIntervalSince1970:m.created/1000),style:.time)
                    if m.sender==api.user?.id{
                        Text(m.read != nil ? api.t("Read","مقروءة"):m.delivered != nil ? api.t("Delivered","تم التسليم"):api.t("Sent","تم الإرسال"))
                    }
                }
                .font(.caption2).foregroundStyle(.secondary)
                if let reactions=m.reactions,!reactions.isEmpty{
                    Text(reactions.map(\.emoji).joined(separator:" ")).font(.caption)
                }
            }
            .padding(12).background(m.sender==api.user?.id ? Ink.blue.opacity(0.09):Color.secondary.opacity(0.08),in:RoundedRectangle(cornerRadius:12)).contextMenu{
                Button(api.t("Reply","رد")){
                    reply=m
                }
                ForEach(["♥","👍","✨","😂"],id:\.self){
                    emoji in Button(emoji){
                        Task{
                            do{
                                let _:OK=try await api.request("messages/\(m.id)/reaction",method:"POST",body:["emoji":emoji])
                                await load()
                            }
                            catch{
                                self.error=error.localizedDescription
                            }
                        }
                    }
                }
                Button(api.t("Remove my reaction","إزالة تفاعلي")){
                    Task{
                        let _:OK?=try? await api.request("messages/\(m.id)/reaction",method:"POST",body:["emoji":""])
                        await load()
                    }
                }
                if m.sender != api.user?.id{
                    Button(api.t("Report","إبلاغ")){
                        report=m
                    }
                }
            }
            if m.sender != api.user?.id{
                Spacer(minLength:42)
            }
        }
    }
    func load()async{
        do{
            let r:MessagePage=try await api.request("conversations/\(cid)/messages")
            var map=Dictionary(uniqueKeysWithValues:messages.map{
                ($0.id,$0)
            }
            )
            for m in r.items{
                map[m.id]=m
            }
            messages=map.values.sorted{
                $0.created==$1.created ? $0.id<$1.id:$0.created<$1.created
            }
            pending.removeAll{
                p in messages.contains{
                    $0.id==p.id
                }
            }
            if loading{
                next=r.next
            }
            typing=r.typing
            status=r.status
            error=nil
            await acknowledge(read:bottom)
        }
        catch{
            self.error=error.localizedDescription
        }
        loading=false
    }
    func acknowledge(read:Bool)async{
        guard scenePhase == .active else{
            return
        }
        let ids=messages.filter{
            $0.sender != api.user?.id && ($0.delivered==nil || (read&&$0.read==nil))
        }
        .suffix(100).map(\.id)
        guard !ids.isEmpty else{
            return
        }
        let _:OK?=try? await api.request("conversations/\(cid)/ack",method:"POST",body:["ids":ids,"read":read])
    }
    func setRequest(_ accept:Bool){
        Task{
            do{
                let _:OK=try await api.request("conversations/\(cid)/"+(accept ? "accept":"decline"),method:"POST")
                status=accept ? "accepted":"declined"
            }
            catch{
                self.error=error.localizedDescription
            }
        }
    }
    func send(_ retry:PendingMessage?=nil){
        guard !busy else{
            return
        }
        let p=retry ?? PendingMessage(id:id,body:draft,media:media,reply:reply?.id,failed:false)
        pending.removeAll{
            $0.id==p.id
        }
        pending.append(PendingMessage(id:p.id,body:p.body,media:p.media,reply:p.reply,failed:false))
        busy=true
        Task{
            defer{
                busy=false
            }
            do{
                var values:[String:Any]=["id":p.id,"body":p.body]
                if let media=p.media{
                    values["media"]=media
                }
                if let reply=p.reply{
                    values["replyTo"]=reply
                }
                let _:MessageResponse=try await api.request("conversations/\(cid)/messages",method:"POST",body:values)
                if retry==nil{
                    draft=""
                    media=nil
                    reply=nil
                    id=UUID().uuidString.lowercased()
                    UserDefaults.standard.removeObject(forKey:localKey)
                }
                bottom=true
                await load()
            }
            catch{
                if let i=pending.firstIndex(where:{
                    $0.id==p.id
                }
                ){
                    pending[i].failed=true
                }
                self.error=error.localizedDescription
            }
        }
    }
}
struct PendingMessage:Identifiable{
    let id:String
    let body:String
    let media:String?
    let reply:String?
    var failed:Bool
}
struct MessageAttachment:View {
    @EnvironmentObject var api:API
    let id:String
    @State private var image:UIImage?
    @State private var file:URL?
    @State private var player:AVPlayer?
    @State private var playing=false
    @State private var error:String?
    var body:some View{
        Group{
            if let image{
                Image(uiImage:image).resizable().scaledToFit().frame(maxHeight:250)
            }
            else if let file{
                Button{
                    if playing{
                        player?.pause()
                    }
                    else{
                        if player==nil{
                            player=AVPlayer(url:file)
                        }
                        player?.play()
                    }
                    playing.toggle()
                } label:{
                    Label(api.t("Voice message","رسالة صوتية"),systemImage:playing ? "pause.circle":"play.circle")
                }
            }
            else if let error{
                Text(error).font(.caption)
            }
            else{
                ProgressView()
            }
        }
        .task(id:id){
            do{
                let(data,type)=try await api.media(id)
                if type.hasPrefix("image/"){
                    image=UIImage(data:data)
                }
                else{
                    let url=FileManager.default.temporaryDirectory.appendingPathComponent(id+".m4a")
                    try data.write(to:url,options:.completeFileProtection)
                    file=url
                }
            }
            catch{
                self.error=error.localizedDescription
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { notification in
            guard let item=notification.object as? AVPlayerItem, item === player?.currentItem else { return }
            playing=false
            player?.seek(to:.zero)
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemFailedToPlayToEndTime)) { notification in
            guard let item=notification.object as? AVPlayerItem, item === player?.currentItem else { return }
            playing=false
            error=api.t("Audio could not be played. Try opening this conversation again.", "تعذّر تشغيل الصوت. حاول فتح المحادثة مجددًا.")
            file=nil
        }
        .onDisappear{
            player?.pause()
            playing=false
            player=nil
            if let file{
                try? FileManager.default.removeItem(at:file)
                self.file=nil
            }
        }
    }
}
