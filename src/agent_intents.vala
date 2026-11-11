namespace Singularity.Apps.QrCodes {

    internal class QrCodesIntents : Object {

        private static string text(Json.Object args, string key) {
            return args.has_member(key) && args.get_member(key).get_value_type() == typeof(string) ? args.get_string_member(key).strip() : "";
        }

        private static string payload(Json.Object args, out string kind) throws Error {
            if (args.has_member("wifi")) {
                var w = args.get_object_member("wifi");
                var info = new WifiInfo();
                info.ssid = text(w, "ssid");
                if (info.ssid == "") throw new IOError.INVALID_ARGUMENT("give the network name in wifi.ssid");
                info.password = w.has_member("password") ? w.get_string_member("password") : "";
                string sec = text(w, "security").up();
                info.security = sec == "" ? (info.password == "" ? "nopass" : "WPA") : WifiInfo.normalize_security(sec);
                info.hidden = w.has_member("hidden") && w.get_boolean_member("hidden");
                kind = "wifi";
                return Payload.wifi(info);
            }
            if (args.has_member("contact")) {
                var c = args.get_object_member("contact");
                var info = new ContactInfo();
                info.name = text(c, "name");
                info.org = text(c, "org");
                info.phone = text(c, "phone");
                info.email = text(c, "email");
                info.url = text(c, "url");
                info.address = text(c, "address");
                info.note = text(c, "note");
                if (info.is_empty()) throw new IOError.INVALID_ARGUMENT("the contact has no fields");
                kind = "contact";
                return Payload.contact(info);
            }
            string t = args.has_member("text") ? args.get_string_member("text") : "";
            if (t.strip() == "") throw new IOError.INVALID_ARGUMENT("give text, wifi or contact");
            kind = Content.parse(t).kind.id();
            return t;
        }

        private static string target(Json.Object args, string kind, string ext) throws Error {
            string p = text(args, "path");
            if (p != "") {
                if (p.has_prefix("~/")) p = Path.build_filename(Environment.get_home_dir(), p.substring(2));
                if (!Path.is_absolute(p)) throw new IOError.INVALID_ARGUMENT("path must be absolute");
                if (FileUtils.test(p, FileTest.EXISTS)) throw new IOError.EXISTS("%s already exists", p);
                return p;
            }
            string dir = Environment.get_user_special_dir(UserDirectory.PICTURES) ?? Environment.get_home_dir();
            DirUtils.create_with_parents(dir, 0755);
            string name = "QR " + kind;
            string candidate = Path.build_filename(dir, name + ext);
            for (int i = 2; FileUtils.test(candidate, FileTest.EXISTS); i++) candidate = Path.build_filename(dir, "%s %d%s".printf(name, i, ext));
            return candidate;
        }

        private static void describe(Json.Builder b, Content c, bool reveal) {
            b.set_member_name("kind").add_string_value(c.kind.id());
            if (c.title != "") b.set_member_name("title").add_string_value(c.title);
            b.set_member_name("fields").begin_object();
            foreach (var f in c.fields) {
                if (f.secret && !reveal) continue;
                b.set_member_name(f.key).add_string_value(f.value);
            }
            b.end_object();
            bool hidden = !reveal && (c.kind == ContentKind.WIFI || c.kind == ContentKind.OTP);
            if (!hidden) b.set_member_name("text").add_string_value(c.raw);
            else b.set_member_name("note").add_string_value("the password or secret it carries is not shown");
        }

        internal static void install(QrCodesApp app) {
            var agent = app.agent;
            agent.add_intent("qrcodes_create",
                "Make a QR code (or a barcode with format ean13, ean8, upca, code128) from text, a link, a Wi-Fi network or a contact, saved as a PNG or SVG image in Pictures unless path is given.",
                "{\"type\":\"object\",\"properties\":{\"text\":{\"type\":\"string\"},\"wifi\":{\"type\":\"object\",\"properties\":{\"ssid\":{\"type\":\"string\"},\"password\":{\"type\":\"string\"},\"security\":{\"type\":\"string\",\"enum\":[\"WPA\",\"SAE\",\"WEP\",\"nopass\"]},\"hidden\":{\"type\":\"boolean\"}}},\"contact\":{\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\"},\"org\":{\"type\":\"string\"},\"phone\":{\"type\":\"string\"},\"email\":{\"type\":\"string\"},\"url\":{\"type\":\"string\"},\"address\":{\"type\":\"string\"},\"note\":{\"type\":\"string\"}}},\"format\":{\"type\":\"string\",\"enum\":[\"qr\",\"ean13\",\"ean8\",\"upca\",\"code128\"]},\"image\":{\"type\":\"string\",\"enum\":[\"png\",\"svg\"]},\"path\":{\"type\":\"string\"}}}",
                Singularity.AppIntentRisk.UNDOABLE, (args) => {
                    string kind;
                    string data = payload(args, out kind);
                    var format = CodeFormat.from_id(text(args, "format"));
                    bool svg = text(args, "image") == "svg" || text(args, "path").has_suffix(".svg");
                    if (format.is_linear()) {
                        if (kind != "text" && kind != "url" && kind != "product") throw new IOError.INVALID_ARGUMENT("a %s barcode holds digits or plain text, not a %s", format.label(), kind);
                        kind = format.id();
                    }
                    string path = target(args, kind, svg ? ".svg" : ".png");
                    if (format.is_linear()) {
                        var bar = Barcode.encode(format, data);
                        if (svg) FileUtils.set_contents(path, Render.barcode_svg(bar));
                        else Render.save_barcode_png(bar, 3, path);
                        data = bar.text;
                    } else {
                        var qr = QrCode.encode_text(data, QrEcLevel.MEDIUM);
                        if (svg) FileUtils.set_contents(path, Render.svg(qr));
                        else Render.save_png(qr, 10, path);
                    }
                    bool verified = false;
                    if (!svg && Scan.AVAILABLE) {
                        Decoded[] check = {};
                        bool readable = true;
                        try {
                            check = Scan.decode_file(path);
                        } catch (Error e) {
                            readable = false;
                        }
                        foreach (var d in check) if (d.text == data) verified = true;
                        if (readable && !verified) {
                            FileUtils.remove(path);
                            throw new IOError.FAILED("the saved image does not read back as the same code");
                        }
                    }
                    var e = app.history.add(Origin.GENERATED, data, Path.get_basename(path), -1, format.id());
                    var b = new Json.Builder();
                    b.begin_object();
                    b.set_member_name("path").add_string_value(path);
                    b.set_member_name("format").add_string_value(format.id());
                    b.set_member_name("kind").add_string_value(kind);
                    b.set_member_name("verified_by_reading_back").add_boolean_value(verified);
                    b.set_member_name("history_id").add_string_value(e.id);
                    b.set_member_name("undo").add_string_value("delete " + path + " and qrcodes_forget with id " + e.id);
                    b.end_object();
                    return b.get_root();
                });
            agent.add_intent("qrcodes_read", "Read the QR codes and barcodes in an image file and say what they hold. Wi-Fi passwords and two-factor secrets are left out unless reveal is true.",
                "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"},\"reveal\":{\"type\":\"boolean\"}},\"required\":[\"path\"]}",
                Singularity.AppIntentRisk.READ, (args) => {
                    if (!Scan.AVAILABLE) throw new IOError.NOT_SUPPORTED("this build of QR Codes cannot read images");
                    string p = text(args, "path");
                    if (p.has_prefix("~/")) p = Path.build_filename(Environment.get_home_dir(), p.substring(2));
                    if (p == "" || !FileUtils.test(p, FileTest.IS_REGULAR)) throw new IOError.NOT_FOUND("no image at %s", p);
                    bool reveal = args.has_member("reveal") && args.get_boolean_member("reveal");
                    var found = Scan.decode_file(p);
                    var b = new Json.Builder();
                    b.begin_object();
                    b.set_member_name("codes").begin_array();
                    foreach (var d in found) {
                        b.begin_object();
                        b.set_member_name("format").add_string_value(d.format.id());
                        describe(b, Content.parse_code(d.text, d.format), reveal);
                        b.end_object();
                    }
                    b.end_array();
                    if (found.length == 0) b.set_member_name("note").add_string_value("no code found in the image");
                    b.end_object();
                    return b.get_root();
                });
            agent.add_intent("qrcodes_history", "Codes recently scanned or made in QR Codes, newest first. Wi-Fi passwords and two-factor secrets are left out.",
                "{\"type\":\"object\",\"properties\":{\"query\":{\"type\":\"string\"},\"limit\":{\"type\":\"integer\"}}}",
                Singularity.AppIntentRisk.READ, (args) => {
                    app.history.load();
                    string q = text(args, "query").casefold();
                    int limit = args.has_member("limit") ? (int) args.get_int_member("limit").clamp(1, 100) : 20;
                    var b = new Json.Builder();
                    b.begin_array();
                    int n = 0;
                    foreach (var e in app.history.items) {
                        var c = Content.parse_code(e.text, CodeFormat.from_id(e.format));
                        if (q != "" && !c.title.casefold().contains(q) && !(c.kind != ContentKind.WIFI && c.kind != ContentKind.OTP && e.text.casefold().contains(q))) continue;
                        if (n++ == limit) break;
                        b.begin_object();
                        b.set_member_name("id").add_string_value(e.id);
                        b.set_member_name("origin").add_string_value(e.origin.id());
                        b.set_member_name("format").add_string_value(e.format);
                        b.set_member_name("time").add_string_value(new DateTime.from_unix_local(e.time).format_iso8601());
                        describe(b, c, false);
                        b.end_object();
                    }
                    b.end_array();
                    return b.get_root();
                });
            agent.add_intent("qrcodes_forget", "Remove one entry from the QR Codes history.",
                "{\"type\":\"object\",\"properties\":{\"id\":{\"type\":\"string\"}},\"required\":[\"id\"]}",
                Singularity.AppIntentRisk.UNDOABLE, (args) => {
                    string id = text(args, "id");
                    HistoryEntry? e = null;
                    foreach (var x in app.history.items) if (x.id == id) e = x;
                    if (e == null) throw new IOError.NOT_FOUND("no history entry %s", id);
                    app.history.remove(id);
                    var fresh = new History(app.history.path);
                    foreach (var x in fresh.items) if (x.id == id) throw new IOError.FAILED("the entry is still in the history");
                    var b = new Json.Builder();
                    b.begin_object();
                    b.set_member_name("forgotten").add_string_value(id);
                    b.end_object();
                    return b.get_root();
                });
        }
    }
}
