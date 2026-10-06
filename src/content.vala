namespace Singularity.Apps.QrCodes {

    public enum ContentKind {
        TEXT,
        URL,
        WIFI,
        CONTACT,
        GEO,
        EMAIL,
        PHONE,
        SMS,
        OTP,
        PRODUCT;

        public string id () {
            switch (this) {
                case URL: return "url";
                case WIFI: return "wifi";
                case CONTACT: return "contact";
                case GEO: return "geo";
                case EMAIL: return "email";
                case PHONE: return "phone";
                case SMS: return "sms";
                case OTP: return "otp";
                case PRODUCT: return "product";
                default: return "text";
            }
        }

        public string label () {
            switch (this) {
                case URL: return _("Web Link");
                case WIFI: return _("Wi-Fi Network");
                case CONTACT: return _("Contact");
                case GEO: return _("Location");
                case EMAIL: return _("Email");
                case PHONE: return _("Phone Number");
                case SMS: return _("Text Message");
                case OTP: return _("Two-Factor Setup Code");
                case PRODUCT: return _("Product Code");
                default: return _("Text");
            }
        }

        public string icon_name () {
            switch (this) {
                case URL: return "web-browser-symbolic";
                case WIFI: return "network-wireless-symbolic";
                case CONTACT: return "avatar-default-symbolic";
                case GEO: return "mark-location-symbolic";
                case EMAIL: return "mail-unread-symbolic";
                case PHONE: return "call-start-symbolic";
                case SMS: return "mail-send-symbolic";
                case OTP: return "dialog-password-symbolic";
                case PRODUCT: return "package-x-generic-symbolic";
                default: return "text-x-generic-symbolic";
            }
        }
    }

    public class Field : Object {
        public string key { get; construct; }
        public string label { get; construct; }
        public string value { get; construct; }
        public bool secret { get; construct; }

        public Field (string key, string label, string value, bool secret = false) {
            Object (key: key, label: label, value: value, secret: secret);
        }
    }

    public class WifiInfo : Object {
        public string ssid { get; set; default = ""; }
        public string security { get; set; default = "nopass"; }
        public string password { get; set; default = ""; }
        public bool hidden { get; set; }

        public bool has_password () {
            return security != "nopass" && password != "";
        }

        public string security_label () {
            switch (security) {
                case "WPA": return _("WPA/WPA2");
                case "SAE": return _("WPA3");
                case "WEP": return _("WEP");
                default: return _("None");
            }
        }

        public static string normalize_security (string? t) {
            string v = (t ?? "").strip ().up ();
            if (v == "" || v == "NOPASS" || v == "NONE" || v == "OPEN") return "nopass";
            if (v == "WEP") return "WEP";
            if (v == "SAE" || v == "WPA3") return "SAE";
            return "WPA";
        }
    }

    public class Content : Object {
        public ContentKind kind { get; private set; }
        public CodeFormat format { get; private set; default = CodeFormat.QR; }
        public string raw { get; private set; }
        public string title { get; private set; default = ""; }
        public string? url { get; private set; }
        public WifiInfo? wifi { get; private set; }
        public Gee.ArrayList<Field> fields = new Gee.ArrayList<Field> ();

        private Content (ContentKind kind, string raw) {
            this.kind = kind;
            this.raw = raw;
        }

        public string? field (string key) {
            foreach (var f in fields) if (f.key == key) return f.value;
            return null;
        }

        public Gee.ArrayList<string> values (string key) {
            var list = new Gee.ArrayList<string> ();
            foreach (var f in fields) if (f.key == key) list.add (f.value);
            return list;
        }

        private void add (string key, string label, string? value, bool secret = false) {
            if (value == null || value.strip () == "") return;
            fields.add (new Field (key, label, value.strip (), secret));
        }

        private static bool starts (string text, string prefix) {
            return text.length >= prefix.length && text.substring (0, prefix.length).ascii_down () == prefix.ascii_down ();
        }

        public static bool is_vcard (string text) {
            return starts (text.strip (), "BEGIN:VCARD");
        }

        public string summary () {
            if (format == CodeFormat.QR) return kind.label ();
            return _("%s, %s").printf (kind.label (), format.label ());
        }

        public static Content parse_code (string input, CodeFormat format) {
            string code = input.strip ();
            if (format.is_product () && Gtin.all_digits (code)) {
                var c = new Content (ContentKind.PRODUCT, input);
                c.format = format;
                c.title = code;
                c.add ("code", _("Code"), code);
                c.fields.add (new Field ("format", _("Format"), format.label ()));
                if (format == CodeFormat.EAN13 && Gtin.is_isbn (code)) c.fields.add (new Field ("isbn", _("Book Number (ISBN)"), code));
                if (!Gtin.valid (code)) c.fields.add (new Field ("check", _("Check Digit"), _("Does not match, the code may be misread")));
                return c;
            }
            var c = parse (input);
            c.format = format;
            return c;
        }

        public static Content parse (string input) {
            string text = input.strip ();
            Content? c = null;
            if (starts (text, "WIFI:")) c = parse_wifi (text);
            else if (starts (text, "MECARD:")) c = parse_mecard (text);
            else if (starts (text, "BEGIN:VCARD")) c = parse_vcard (text);
            else if (starts (text, "geo:")) c = parse_geo (text);
            else if (starts (text, "mailto:")) c = parse_mailto (text);
            else if (starts (text, "MATMSG:")) c = parse_matmsg (text);
            else if (starts (text, "tel:")) c = parse_tel (text);
            else if (starts (text, "smsto:") || starts (text, "sms:") || starts (text, "mmsto:")) c = parse_sms (text);
            else if (starts (text, "otpauth://")) c = parse_otp (text);
            else c = parse_url (text);
            if (c == null) {
                c = new Content (ContentKind.TEXT, input);
                c.title = first_line (text);
            }
            c.raw = input;
            return c;
        }

        private static string first_line (string text) {
            int nl = text.index_of_char ('\n');
            string line = (nl >= 0 ? text.substring (0, nl) : text).strip ();
            if (line.char_count () > 80) line = line.substring (0, line.index_of_nth_char (80)) + "…";
            return line;
        }

        public static string[] split_escaped (string text, unichar sep) {
            string[] parts = {};
            var cur = new StringBuilder ();
            bool esc = false;
            int i = 0;
            unichar ch;
            while (text.get_next_char (ref i, out ch)) {
                if (esc) {
                    cur.append_unichar ('\\');
                    cur.append_unichar (ch);
                    esc = false;
                } else if (ch == '\\') {
                    esc = true;
                } else if (ch == sep) {
                    parts += cur.str;
                    cur.truncate ();
                } else {
                    cur.append_unichar (ch);
                }
            }
            if (esc) cur.append_unichar ('\\');
            parts += cur.str;
            return parts;
        }

        public static string unescape (string text) {
            var out_text = new StringBuilder ();
            bool esc = false;
            int i = 0;
            unichar ch;
            while (text.get_next_char (ref i, out ch)) {
                if (esc) {
                    out_text.append_unichar (ch);
                    esc = false;
                } else if (ch == '\\') {
                    esc = true;
                } else {
                    out_text.append_unichar (ch);
                }
            }
            if (esc) out_text.append_unichar ('\\');
            return out_text.str;
        }

        private static int unescaped_index (string text, unichar ch) {
            bool esc = false;
            int i = 0;
            unichar c;
            while (true) {
                int start = i;
                if (!text.get_next_char (ref i, out c)) break;
                if (esc) esc = false;
                else if (c == '\\') esc = true;
                else if (c == ch) return start;
            }
            return -1;
        }

        private class Pair {
            public string key;
            public string value;

            public Pair (string key, string value) {
                this.key = key;
                this.value = value;
            }
        }

        private static Gee.ArrayList<Pair> key_values (string body) {
            var list = new Gee.ArrayList<Pair> ();
            foreach (string part in split_escaped (body, ';')) {
                if (part == "") continue;
                int colon = unescaped_index (part, ':');
                if (colon <= 0) continue;
                list.add (new Pair (part.substring (0, colon).strip ().up (), part.substring (colon + 1)));
            }
            return list;
        }

        private static Content? parse_wifi (string text) {
            var info = new WifiInfo ();
            string? type = null;
            bool seen_ssid = false;
            foreach (var kv in key_values (text.substring (5))) {
                switch (kv.key) {
                    case "S": info.ssid = unescape (kv.value); seen_ssid = true; break;
                    case "T": type = unescape (kv.value); break;
                    case "P": info.password = unescape (kv.value); break;
                    case "H": info.hidden = unescape (kv.value).strip ().down () == "true"; break;
                    default: break;
                }
            }
            if (!seen_ssid) return null;
            info.security = WifiInfo.normalize_security (type);
            if (type == null && info.password != "") info.security = "WPA";
            var c = new Content (ContentKind.WIFI, text);
            c.wifi = info;
            c.title = info.ssid;
            c.add ("ssid", _("Network Name"), info.ssid);
            c.fields.add (new Field ("security", _("Security"), info.security_label ()));
            if (info.security != "nopass") c.add ("password", _("Password"), info.password, true);
            if (info.hidden) c.fields.add (new Field ("hidden", _("Hidden Network"), _("Yes")));
            return c;
        }

        private static Content? parse_mecard (string text) {
            var c = new Content (ContentKind.CONTACT, text);
            foreach (var kv in key_values (text.substring (7))) {
                string v = unescape (kv.value);
                switch (kv.key) {
                    case "N":
                        string[] parts = split_escaped (kv.value, ',');
                        string name = parts.length >= 2 ? "%s %s".printf (unescape (parts[1]).strip (), unescape (parts[0]).strip ()) : v;
                        c.add ("name", _("Name"), name.strip ());
                        break;
                    case "SOUND": break;
                    case "TEL": case "TEL-AV": c.add ("phone", _("Phone"), v); break;
                    case "EMAIL": c.add ("email", _("Email"), v); break;
                    case "URL": c.add ("url", _("Website"), v); break;
                    case "ADR": c.add ("address", _("Address"), v); break;
                    case "ORG": c.add ("org", _("Organization"), v); break;
                    case "NOTE": c.add ("note", _("Note"), v); break;
                    case "BDAY": c.add ("birthday", _("Birthday"), format_date (v)); break;
                    case "NICKNAME": c.add ("nickname", _("Nickname"), v); break;
                    default: break;
                }
            }
            c.title = c.field ("name") ?? c.field ("org") ?? c.field ("email") ?? c.field ("phone") ?? _("Contact");
            return c;
        }

        private static string format_date (string v) {
            string s = v.strip ();
            if (s.length == 8 && Regex.match_simple ("^[0-9]{8}$", s)) return "%s-%s-%s".printf (s.substring (0, 4), s.substring (4, 2), s.substring (6, 2));
            return s;
        }

        public static string vcard_unescape (string v) {
            var sb = new StringBuilder ();
            bool esc = false;
            int i = 0;
            unichar ch;
            while (v.get_next_char (ref i, out ch)) {
                if (esc) {
                    if (ch == 'n' || ch == 'N') sb.append_c ('\n');
                    else sb.append_unichar (ch);
                    esc = false;
                } else if (ch == '\\') {
                    esc = true;
                } else {
                    sb.append_unichar (ch);
                }
            }
            return sb.str;
        }

        private static Content? parse_vcard (string text) {
            string unfolded = text.replace ("\r\n", "\n").replace ("\r", "\n");
            try {
                unfolded = new Regex ("\n[ \t]").replace (unfolded, -1, 0, "");
            } catch (RegexError e) {
            }
            var c = new Content (ContentKind.CONTACT, text);
            string? fn = null, n = null;
            foreach (string line in unfolded.split ("\n")) {
                int colon = line.index_of_char (':');
                if (colon <= 0) continue;
                string head = line.substring (0, colon);
                string val = line.substring (colon + 1);
                string[] params = head.split (";");
                string name = params[0].up ();
                int dot = name.index_of_char ('.');
                if (dot >= 0) name = name.substring (dot + 1);
                switch (name) {
                    case "FN": fn = vcard_unescape (val); break;
                    case "N": n = val; break;
                    case "ORG": c.add ("org", _("Organization"), join_components (val, " ")); break;
                    case "TITLE": c.add ("title", _("Job Title"), vcard_unescape (val)); break;
                    case "TEL": c.add ("phone", _("Phone"), vcard_unescape (val).replace ("tel:", "")); break;
                    case "EMAIL": c.add ("email", _("Email"), vcard_unescape (val)); break;
                    case "URL": c.add ("url", _("Website"), vcard_unescape (val)); break;
                    case "ADR": c.add ("address", _("Address"), join_components (val, ", ")); break;
                    case "NOTE": c.add ("note", _("Note"), vcard_unescape (val)); break;
                    case "BDAY": c.add ("birthday", _("Birthday"), format_date (vcard_unescape (val))); break;
                    case "NICKNAME": c.add ("nickname", _("Nickname"), vcard_unescape (val)); break;
                    default: break;
                }
            }
            string? display = fn;
            if ((display == null || display.strip () == "") && n != null) {
                string[] parts = split_escaped (n, ';');
                string family = parts.length > 0 ? vcard_unescape (parts[0]).strip () : "";
                string given = parts.length > 1 ? vcard_unescape (parts[1]).strip () : "";
                display = "%s %s".printf (given, family).strip ();
            }
            if (display != null && display.strip () != "") c.fields.insert (0, new Field ("name", _("Name"), display.strip ()));
            c.title = c.field ("name") ?? c.field ("org") ?? c.field ("email") ?? c.field ("phone") ?? _("Contact");
            return c;
        }

        private static string join_components (string val, string sep) {
            string[] out_parts = {};
            foreach (string p in split_escaped (val, ';')) {
                string s = vcard_unescape (p).strip ();
                if (s != "") out_parts += s;
            }
            return string.joinv (sep, out_parts);
        }

        private static Content? parse_geo (string text) {
            string body = text.substring (4);
            string? query = null;
            int q = body.index_of_char ('?');
            if (q >= 0) {
                query = body.substring (q + 1);
                body = body.substring (0, q);
            }
            int semi = body.index_of_char (';');
            if (semi >= 0) body = body.substring (0, semi);
            string[] coords = body.split (",");
            if (coords.length < 2) return null;
            double lat = 0, lon = 0;
            if (!double.try_parse (coords[0].strip (), out lat) || !double.try_parse (coords[1].strip (), out lon)) return null;
            if (lat < -90 || lat > 90 || lon < -180 || lon > 180) return null;
            var c = new Content (ContentKind.GEO, text);
            c.add ("latitude", _("Latitude"), format_coord (lat));
            c.add ("longitude", _("Longitude"), format_coord (lon));
            if (coords.length > 2) c.add ("altitude", _("Altitude"), _("%s m").printf (coords[2].strip ()));
            if (query != null) {
                var qp = query_params (query);
                if (qp.has_key ("q")) c.add ("label", _("Place"), qp["q"]);
            }
            c.title = c.field ("label") ?? "%s, %s".printf (format_coord (lat), format_coord (lon));
            c.url = "https://www.openstreetmap.org/?mlat=%s&mlon=%s#map=16/%s/%s".printf (format_coord (lat), format_coord (lon), format_coord (lat), format_coord (lon));
            return c;
        }

        private static string format_coord (double v) {
            char[] buf = new char[double.DTOSTR_BUF_SIZE];
            string s = v.format (buf, "%.6f");
            while (s.contains (".") && (s.has_suffix ("0") || s.has_suffix ("."))) {
                bool dot = s.has_suffix (".");
                s = s.substring (0, s.length - 1);
                if (dot) break;
            }
            return s;
        }

        public static Gee.HashMap<string, string> query_params (string query) {
            var map = new Gee.HashMap<string, string> ();
            foreach (string pair in query.split ("&")) {
                if (pair == "") continue;
                int eq = pair.index_of_char ('=');
                string k = eq >= 0 ? pair.substring (0, eq) : pair;
                string v = eq >= 0 ? pair.substring (eq + 1) : "";
                k = (Uri.unescape_string (k.replace ("+", " ")) ?? k).down ();
                v = Uri.unescape_string (v.replace ("+", " ")) ?? v;
                if (!map.has_key (k)) map[k] = v;
            }
            return map;
        }

        private static Content? parse_mailto (string text) {
            string body = text.substring (7);
            string? query = null;
            int q = body.index_of_char ('?');
            if (q >= 0) {
                query = body.substring (q + 1);
                body = body.substring (0, q);
            }
            var c = new Content (ContentKind.EMAIL, text);
            string to = Uri.unescape_string (body) ?? body;
            c.add ("to", _("To"), to);
            if (query != null) {
                var qp = query_params (query);
                if (qp.has_key ("cc")) c.add ("cc", _("Cc"), qp["cc"]);
                if (qp.has_key ("subject")) c.add ("subject", _("Subject"), qp["subject"]);
                if (qp.has_key ("body")) c.add ("body", _("Message"), qp["body"]);
            }
            c.title = to != "" ? to : (c.field ("subject") ?? _("Email"));
            c.url = text;
            return c;
        }

        private static Content? parse_matmsg (string text) {
            var c = new Content (ContentKind.EMAIL, text);
            string to = "", sub = "", body = "";
            foreach (var kv in key_values (text.substring (7))) {
                switch (kv.key) {
                    case "TO": to = unescape (kv.value); break;
                    case "SUB": sub = unescape (kv.value); break;
                    case "BODY": body = unescape (kv.value); break;
                    default: break;
                }
            }
            if (to == "" && sub == "" && body == "") return null;
            c.add ("to", _("To"), to);
            c.add ("subject", _("Subject"), sub);
            c.add ("body", _("Message"), body);
            c.title = to != "" ? to : _("Email");
            c.url = Payload.mailto (to, sub, body);
            return c;
        }

        private static Content? parse_tel (string text) {
            string number = Uri.unescape_string (text.substring (4)) ?? text.substring (4);
            if (number.strip () == "") return null;
            var c = new Content (ContentKind.PHONE, text);
            c.add ("phone", _("Number"), number);
            c.title = number.strip ();
            c.url = text;
            return c;
        }

        private static Content? parse_sms (string text) {
            string number = "", body = "";
            int colon = text.index_of_char (':');
            string scheme = text.substring (0, colon).down ();
            string rest = text.substring (colon + 1);
            if (scheme == "sms") {
                int q = rest.index_of_char ('?');
                if (q >= 0) {
                    var qp = query_params (rest.substring (q + 1));
                    if (qp.has_key ("body")) body = qp["body"];
                    rest = rest.substring (0, q);
                }
                number = Uri.unescape_string (rest) ?? rest;
            } else {
                int second = rest.index_of_char (':');
                if (second >= 0) {
                    number = rest.substring (0, second);
                    body = rest.substring (second + 1);
                } else {
                    number = rest;
                }
            }
            if (number.strip () == "" && body.strip () == "") return null;
            var c = new Content (ContentKind.SMS, text);
            c.add ("phone", _("To"), number);
            c.add ("body", _("Message"), body);
            c.title = number.strip () != "" ? number.strip () : _("Text Message");
            c.url = Payload.sms (number.strip (), body);
            return c;
        }

        private static Content? parse_otp (string text) {
            Uri uri;
            try {
                uri = Uri.parse (text, UriFlags.NONE);
            } catch (Error e) {
                return null;
            }
            string type = (uri.get_host () ?? "").down ();
            if (type != "totp" && type != "hotp") return null;
            string label = uri.get_path () ?? "";
            if (label.has_prefix ("/")) label = label.substring (1);
            string issuer = "", account = label;
            int colon = label.index_of_char (':');
            if (colon >= 0) {
                issuer = label.substring (0, colon).strip ();
                account = label.substring (colon + 1).strip ();
            }
            var qp = query_params (uri.get_query () ?? "");
            if (qp.has_key ("issuer") && qp["issuer"].strip () != "") issuer = qp["issuer"].strip ();
            if (!qp.has_key ("secret") || qp["secret"].strip () == "") return null;
            var c = new Content (ContentKind.OTP, text);
            c.add ("issuer", _("Service"), issuer);
            c.add ("account", _("Account"), account);
            c.fields.add (new Field ("type", _("Type"), type == "totp" ? _("Time-based (TOTP)") : _("Counter-based (HOTP)")));
            c.add ("secret", _("Secret Key"), qp["secret"], true);
            if (qp.has_key ("digits")) c.add ("digits", _("Digits"), qp["digits"]);
            if (qp.has_key ("algorithm")) c.add ("algorithm", _("Algorithm"), qp["algorithm"].up ());
            if (type == "totp" && qp.has_key ("period")) c.add ("period", _("Period"), _("%s seconds").printf (qp["period"]));
            if (type == "hotp" && qp.has_key ("counter")) c.add ("counter", _("Counter"), qp["counter"]);
            if (issuer != "" && account != "") c.title = "%s (%s)".printf (issuer, account);
            else if (issuer != "") c.title = issuer;
            else if (account != "") c.title = account;
            else c.title = _("Two-Factor Account");
            return c;
        }

        private static Content? parse_url (string text) {
            if (text.contains (" ") || text.contains ("\n") || text.contains ("\t")) return null;
            string candidate = text;
            string lower = text.ascii_down ();
            if (lower.has_prefix ("www.")) candidate = "https://" + text;
            else if (!lower.has_prefix ("http://") && !lower.has_prefix ("https://") && !lower.has_prefix ("ftp://")) return null;
            Uri uri;
            try {
                uri = Uri.parse (candidate, UriFlags.NONE);
            } catch (Error e) {
                return null;
            }
            string? host = uri.get_host ();
            if (host == null || host == "" || !host.contains (".") && host != "localhost") return null;
            var c = new Content (ContentKind.URL, text);
            c.url = candidate;
            c.add ("url", _("Address"), candidate);
            c.add ("host", _("Website"), host);
            c.title = host;
            return c;
        }
    }
}
