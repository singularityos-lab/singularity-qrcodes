namespace Singularity.Apps.QrCodes {

    public class ContactCard : Object {
        public string uid { get; set; default = ""; }
        public string name { get; set; default = ""; }
        public string org { get; set; default = ""; }
        public string note { get; set; default = ""; }
        public string source { get; set; default = ""; }
        public Gee.ArrayList<string> phones = new Gee.ArrayList<string> ();
        public Gee.ArrayList<string> emails = new Gee.ArrayList<string> ();
        public Gee.ArrayList<string> urls = new Gee.ArrayList<string> ();
        public Gee.ArrayList<string> addresses = new Gee.ArrayList<string> ();

        public string display_name () {
            if (name != "") return name;
            if (org != "") return org;
            if (emails.size > 0) return emails[0];
            if (phones.size > 0) return phones[0];
            return "";
        }

        public string detail () {
            string[] parts = {};
            if (emails.size > 0) parts += emails[0];
            if (phones.size > 0) parts += phones[0];
            if (parts.length == 0 && org != "" && name != "") parts += org;
            return string.joinv (", ", parts);
        }

        public bool matches (string query) {
            string q = query.strip ().casefold ();
            if (q == "") return true;
            if (name.casefold ().contains (q) || org.casefold ().contains (q)) return true;
            foreach (string s in emails) if (s.casefold ().contains (q)) return true;
            foreach (string s in phones) if (s.replace (" ", "").contains (q.replace (" ", ""))) return true;
            return false;
        }

        public ContactInfo to_info () {
            var info = new ContactInfo ();
            info.name = name;
            info.org = org;
            info.phone = phones.size > 0 ? phones[0] : "";
            info.email = emails.size > 0 ? emails[0] : "";
            info.url = urls.size > 0 ? urls[0] : "";
            info.address = addresses.size > 0 ? addresses[0] : "";
            info.note = note;
            return info;
        }
    }

    namespace ContactBook {
        public string local_dir () {
            return Path.build_filename (Environment.get_user_data_dir (), "singularity", "contacts");
        }

        public string synced_dir () {
            return Path.build_filename (Environment.get_user_cache_dir (), "singularity-contacts");
        }

        private string[] unfold (string text) {
            string[] lines = {};
            var cur = new StringBuilder ();
            bool have = false;
            foreach (string raw in text.replace ("\r\n", "\n").replace ("\r", "\n").split ("\n")) {
                if (have && (raw.has_prefix (" ") || raw.has_prefix ("\t"))) {
                    cur.append (raw.substring (1));
                    continue;
                }
                if (have) lines += cur.str;
                cur.truncate ();
                cur.append (raw);
                have = true;
            }
            if (have) lines += cur.str;
            return lines;
        }

        private string join_parts (string value, string sep) {
            string[] out_parts = {};
            foreach (string p in Content.split_escaped (value, ';')) {
                string s = Content.vcard_unescape (p).strip ();
                if (s != "") out_parts += s;
            }
            return string.joinv (sep, out_parts);
        }

        private void add_unique (Gee.ArrayList<string> list, string value) {
            string v = value.strip ();
            if (v != "" && !list.contains (v)) list.add (v);
        }

        public Gee.ArrayList<ContactCard> parse (string text, string source) {
            var cards = new Gee.ArrayList<ContactCard> ();
            ContactCard? card = null;
            string family = "", given = "";
            foreach (string line in unfold (text)) {
                int colon = line.index_of_char (':');
                if (colon <= 0) continue;
                string head = line.substring (0, colon);
                string value = line.substring (colon + 1);
                string prop = head.split (";")[0].up ();
                int dot = prop.last_index_of_char ('.');
                if (dot >= 0) prop = prop.substring (dot + 1);
                if (prop == "BEGIN" && value.strip ().up () == "VCARD") {
                    card = new ContactCard ();
                    card.source = source;
                    family = given = "";
                    continue;
                }
                if (card == null) continue;
                if (prop == "END") {
                    if (card.name == "") card.name = "%s %s".printf (given, family).strip ();
                    if (card.display_name () != "") cards.add (card);
                    card = null;
                    continue;
                }
                switch (prop) {
                    case "UID": card.uid = Content.vcard_unescape (value).strip (); break;
                    case "FN": card.name = Content.vcard_unescape (value).strip (); break;
                    case "N":
                        string[] parts = Content.split_escaped (value, ';');
                        family = parts.length > 0 ? Content.vcard_unescape (parts[0]).strip () : "";
                        given = parts.length > 1 ? Content.vcard_unescape (parts[1]).strip () : "";
                        break;
                    case "ORG": card.org = join_parts (value, " "); break;
                    case "NOTE": card.note = Content.vcard_unescape (value).strip (); break;
                    case "TEL":
                        string tel = Content.vcard_unescape (value);
                        if (tel.has_prefix ("tel:")) tel = tel.substring (4);
                        add_unique (card.phones, tel);
                        break;
                    case "EMAIL":
                        string mail = Content.vcard_unescape (value);
                        if (mail.down ().has_prefix ("mailto:")) mail = mail.substring (7);
                        add_unique (card.emails, mail);
                        break;
                    case "URL": add_unique (card.urls, Content.vcard_unescape (value)); break;
                    case "ADR": add_unique (card.addresses, join_parts (value, ", ")); break;
                    default: break;
                }
            }
            return cards;
        }

        public Gee.ArrayList<ContactCard> read_dir (string dir, string source) {
            var cards = new Gee.ArrayList<ContactCard> ();
            Dir d;
            try {
                d = Dir.open (dir);
            } catch (FileError e) {
                return cards;
            }
            string[] names = {};
            string? n;
            while ((n = d.read_name ()) != null) {
                if (n.down ().has_suffix (".vcf")) names += n;
            }
            foreach (string name in names) {
                string text;
                try {
                    FileUtils.get_contents (Path.build_filename (dir, name), out text);
                } catch (FileError e) {
                    continue;
                }
                cards.add_all (parse (text, source));
            }
            return cards;
        }

        public Gee.ArrayList<ContactCard> read_all (string? local = null, string? synced = null) {
            var cards = read_dir (local ?? local_dir (), _("On This Computer"));
            var seen = new Gee.HashSet<string> ();
            foreach (var c in cards) if (c.uid != "") seen.add (c.uid);
            foreach (var c in read_dir (synced ?? synced_dir (), _("Online Account"))) {
                if (c.uid != "" && !seen.add (c.uid)) continue;
                cards.add (c);
            }
            cards.sort ((a, b) => {
                int r = a.display_name ().casefold ().collate (b.display_name ().casefold ());
                return r != 0 ? r : strcmp (a.source, b.source);
            });
            return cards;
        }
    }
}
