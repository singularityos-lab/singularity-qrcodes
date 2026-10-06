namespace Singularity.Apps.QrCodes {

    public class ContactInfo : Object {
        public string name { get; set; default = ""; }
        public string org { get; set; default = ""; }
        public string phone { get; set; default = ""; }
        public string email { get; set; default = ""; }
        public string url { get; set; default = ""; }
        public string address { get; set; default = ""; }
        public string note { get; set; default = ""; }

        public bool is_empty () {
            return (name + org + phone + email + url + address + note).strip () == "";
        }
    }

    namespace Payload {
        public string wifi_escape (string value) {
            var sb = new StringBuilder ();
            int i = 0;
            unichar ch;
            while (value.get_next_char (ref i, out ch)) {
                if (ch == '\\' || ch == ';' || ch == ',' || ch == ':' || ch == '"') sb.append_c ('\\');
                sb.append_unichar (ch);
            }
            return sb.str;
        }

        public string wifi (WifiInfo info) {
            var sb = new StringBuilder ("WIFI:");
            string security = WifiInfo.normalize_security (info.security);
            sb.append ("T:%s;".printf (security));
            sb.append ("S:%s;".printf (wifi_escape (info.ssid)));
            if (security != "nopass") sb.append ("P:%s;".printf (wifi_escape (info.password)));
            if (info.hidden) sb.append ("H:true;");
            sb.append (";");
            return sb.str;
        }

        public string vcard_escape (string value) {
            return value.replace ("\\", "\\\\").replace (",", "\\,").replace (";", "\\;").replace ("\r\n", "\n").replace ("\n", "\\n");
        }

        public string contact (ContactInfo c) {
            var sb = new StringBuilder ("BEGIN:VCARD\nVERSION:3.0\n");
            string name = c.name.strip ();
            string family = "", given = name;
            int space = name.last_index_of_char (' ');
            if (space > 0) {
                given = name.substring (0, space).strip ();
                family = name.substring (space + 1).strip ();
            }
            sb.append ("N:%s;%s;;;\n".printf (vcard_escape (family), vcard_escape (given)));
            sb.append ("FN:%s\n".printf (vcard_escape (name)));
            if (c.org.strip () != "") sb.append ("ORG:%s\n".printf (vcard_escape (c.org.strip ())));
            if (c.phone.strip () != "") sb.append ("TEL:%s\n".printf (vcard_escape (c.phone.strip ())));
            if (c.email.strip () != "") sb.append ("EMAIL:%s\n".printf (vcard_escape (c.email.strip ())));
            if (c.url.strip () != "") sb.append ("URL:%s\n".printf (vcard_escape (c.url.strip ())));
            if (c.address.strip () != "") sb.append ("ADR:;;%s;;;;\n".printf (vcard_escape (c.address.strip ())));
            if (c.note.strip () != "") sb.append ("NOTE:%s\n".printf (vcard_escape (c.note.strip ())));
            sb.append ("END:VCARD");
            return sb.str;
        }

        public string mailto (string to, string subject, string body) {
            string[] q = {};
            if (subject != "") q += "subject=" + Uri.escape_string (subject, null, true);
            if (body != "") q += "body=" + Uri.escape_string (body, null, true);
            string result = "mailto:" + Uri.escape_string (to, "@+", true);
            if (q.length > 0) result += "?" + string.joinv ("&", q);
            return result;
        }

        public string sms (string number, string body) {
            string result = "sms:" + Uri.escape_string (number, "+", true);
            if (body != "") result += "?body=" + Uri.escape_string (body, null, true);
            return result;
        }

        public const string[] SEARCH_ENGINES = { "duckduckgo", "google", "bing", "openfoodfacts" };

        public string product_search (string code, string engine) {
            string q = Uri.escape_string (code.strip (), null, true);
            switch (engine) {
                case "google": return "https://www.google.com/search?q=" + q;
                case "bing": return "https://www.bing.com/search?q=" + q;
                case "openfoodfacts": return "https://world.openfoodfacts.org/product/" + q;
                default: return "https://duckduckgo.com/?q=" + q;
            }
        }

        public string book_lookup (string isbn) {
            return "https://openlibrary.org/isbn/" + Uri.escape_string (isbn.strip (), null, true);
        }
    }
}
