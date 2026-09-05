import SwiftUI
import AVKit
struct Ink {
    static let blue=Color(UIColor {
        $0.userInterfaceStyle == .dark ? UIColor(red:0.61,green:0.71,blue:1,alpha:1) : UIColor(red:0.14,green:0.29,blue:0.70,alpha:1)
    }
    )
    static func accent(_ name:String?) -> Color {
        guard name != nil && name != "blue" else { return blue }
        return Color(UIColor { trait in
            if name == "indigo" { return trait.userInterfaceStyle == .dark ? UIColor(red:0.72,green:0.67,blue:1,alpha:1) : UIColor(red:0.31,green:0.27,blue:0.65,alpha:1) }
            return trait.userInterfaceStyle == .dark ? UIColor(red:0.61,green:0.75,blue:0.78,alpha:1) : UIColor(red:0.24,green:0.37,blue:0.42,alpha:1)
        })
    }
    static let paper=Color(uiColor:.systemGroupedBackground)
}
struct AvatarView:View {
    let person:String
    var media:String?
    var size:CGFloat=40
    var body:some View{
        Group{
            if let media{
                SecureImage(id:media)
            }
            else{
                Text(String(person.prefix(1))).font(.headline).foregroundStyle(Ink.blue).frame(maxWidth:.infinity,maxHeight:.infinity).background(Ink.blue.opacity(0.09))
            }
        }
        .frame(width:size,height:size).clipShape(SwiftUI.Circle()).accessibilityHidden(true)
    }
}
struct SecureImage:View {
    @EnvironmentObject var api:API
    let id:String
    var fit=false
    @State private var image:UIImage?
    @State private var failed=false
    var body:some View{
        Group{
            if let image{
                Image(uiImage:image).resizable().aspectRatio(contentMode:fit ? .fit : .fill)
            }
            else if failed{
                Image(systemName:"photo.badge.exclamationmark").foregroundStyle(.secondary)
            }
            else{
                ProgressView()
            }
        }
        .task(id:id){
            do{
                let (data,_)=try await api.media(id)
                image=UIImage(data:data)
            }
            catch{
                failed=true
            }
        }
    }
}
struct QuietEmpty:View {
    let icon:String
    let title:String
    let detail:String
    var body:some View{
        ContentUnavailableView{
            Label(title,systemImage:icon)
        } description:{
            Text(detail)
        }
        .padding(.vertical,24)
    }
}
struct ErrorNotice:View {
    @EnvironmentObject var api:API
    let message:String
    var retry:(()->Void)?
    var body:some View{
        VStack(spacing:10){
            Text(message).font(.subheadline).foregroundStyle(.red)
            if let retry{
                Button(action:retry){
                    Image(systemName:"arrow.clockwise")
                }.accessibilityLabel(api.t("Try again","حاول مجددًا"))
            }
        }
        .padding().accessibilityElement(children:.combine)
    }
}
struct SongView:View {
    @EnvironmentObject var api:API
    let song:Song
    @State private var player:AVPlayer?
    @State private var playing=false
    var body:some View{
        HStack(spacing:12){
            AsyncImage(url:URL(string:song.artwork)){
                image in image.resizable().scaledToFill()
            } placeholder:{
                Color.secondary.opacity(0.1)
            }
            .frame(width:48,height:48).clipShape(RoundedRectangle(cornerRadius:6))
            VStack(alignment:.leading,spacing:3){
                Text(song.title).font(.subheadline.weight(.semibold))
                Text(song.artist).font(.caption).foregroundStyle(.secondary)
                if song.preview==nil{
                    Text(api.t("Preview unavailable","المقتطف غير متاح")).font(.caption2)
                }
            }
            Spacer()
            if let preview=song.preview{
                Button{
                    if playing{
                        player?.pause()
                    }
                    else{
                        if player==nil{
                            player=AVPlayer(url:URL(string:preview)!)
                        }
                        player?.play()
                    }
                    playing.toggle()
                } label:{
                    Image(systemName:playing ? "pause.fill":"play.fill")
                }
                .accessibilityLabel(api.t("Play or pause preview","تشغيل المقتطف أو إيقافه"))
            }
            if let url=URL(string:song.url){
                Link(destination:url){
                    Image(systemName:"arrow.up.right")
                }
                .accessibilityLabel(api.t("Open in Apple Music","فتح في Apple Music"))
            }
        }
        .padding(12).background(Ink.paper,in:RoundedRectangle(cornerRadius:8)).onDisappear{
            player?.pause()
            playing=false
        }
    }
}
struct BusyButton:View {
    let title:String
    var busy:Bool=false
    let action:()->Void
    var body:some View{
        Button(action:action){
            HStack{
                if busy{
                    ProgressView()
                }
                Text(title).frame(maxWidth:.infinity)
            }
        }
        .buttonStyle(.borderedProminent).controlSize(.large).disabled(busy)
    }
}
struct ReportView:View {
    @EnvironmentObject var api:API
    @Environment(\.dismiss) var dismiss
    let kind:String
    let target:String
    @State private var reason=""
    @State private var error:String?
    var body:some View{
        NavigationStack{
            Form{
                TextField(api.t("What happened?","ماذا حدث؟"),text:$reason,axis:.vertical).lineLimit(4...8)
                if let error{
                    ErrorNotice(message:error)
                }
                Button(api.t("Send report","إرسال البلاغ")){
                    Task{
                        do{
                            let _:OK=try await api.request("reports",method:"POST",body:["kind":kind,"target":target,"reason":reason])
                            dismiss()
                        }
                        catch{
                            self.error=error.localizedDescription
                        }
                    }
                }
                .disabled(reason.count<3)
            }
            .navigationTitle(api.t("Report","إبلاغ")).toolbar{
                ToolbarItem(placement:.cancellationAction){
                    Button(api.t("Cancel","إلغاء")){
                        dismiss()
                    }
                }
            }
        }
    }
}
extension View {
    func dismissKeyboardToolbar(_ title:String)->some View{
        self.toolbar{
            ToolbarItemGroup(placement:.keyboard){
                Spacer()
                Button(title){
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),to:nil,from:nil,for:nil)
                }
            }
        }
    }
}

struct ImageViewer: View {
    @EnvironmentObject var api: API
    @Environment(\.dismiss) var dismiss
    let id: String
    @State private var zoom: CGFloat=1
    @GestureState private var gestureZoom: CGFloat=1
    var body: some View {
        NavigationStack {
            ScrollView([.horizontal,.vertical]) {
                SecureImage(id:id,fit:true).containerRelativeFrame([.horizontal,.vertical])
                    .scaleEffect(zoom*gestureZoom)
                    .gesture(MagnifyGesture().updating($gestureZoom) { value,state,_ in state=value.magnification }.onEnded { value in zoom=min(5,max(1,zoom*value.magnification)) })
            }
            .navigationTitle(api.t("Photo", "صورة"))
            .toolbar {
                ToolbarItem(placement:.cancellationAction) { Button(api.t("Close", "إغلاق")) { dismiss() } }
                ToolbarItemGroup(placement:.topBarTrailing) {
                    Button { zoom=max(1,zoom-0.5) } label: { Image(systemName:"minus.magnifyingglass") }.accessibilityLabel(api.t("Zoom out", "تصغير"))
                    Button { zoom=min(5,zoom+0.5) } label: { Image(systemName:"plus.magnifyingglass") }.accessibilityLabel(api.t("Zoom in", "تكبير"))
                }
            }
        }
    }
}
