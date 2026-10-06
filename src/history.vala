namespace Singularity.Apps.QrCodes {

    public enum Origin {
        SCANNED,
        GENERATED;

        public string id () {
            return this == GENERATED ? "generated" : "scanned";
        }

        public static Origin from_id (string? id) {
            return id == "generated" ? GENERATED : SCANNED;
        }
    }

    public class HistoryEntry : Object {
        public string id { get; set; }
        public Origin origin { get; set; }
        public string text { get; set; }
        public string source { get; set; default = ""; }
        public string format { get; set; default = "qr"; }
        public int64 time { get; set; }

        public HistoryEntry (Origin origin, string text, string source, int64 time, string format = "qr") {
            Object (id: Uuid.string_random (), origin: origin, text: text, source: source, time: time, format: format);
        }
    }

    public class History : Object {
        public const int LIMIT = 100;
        public Gee.ArrayList<HistoryEntry> items = new Gee.ArrayList<HistoryEntry> ();
        public string path { get; private set; }
        public string? load_error { get; private set; }
        private int batch_depth;
        private bool batch_dirty;
        public signal void changed ();

        public void begin_batch () {
            batch_depth++;
        }

        public void end_batch () {
            if (batch_depth == 0) return;
            batch_depth--;
            if (batch_depth == 0 && batch_dirty) {
                batch_dirty = false;
                save ();
                changed ();
            }
        }

        private void commit () {
            if (batch_depth > 0) {
                batch_dirty = true;
                return;
            }
            save ();
            changed ();
        }

        public History (string? file = null) {
            if (file == null) {
                string data = Environment.get_user_data_dir ();
                path = Path.build_filename (data, "singularity", "qrcodes", "history.json");
                migrate (Path.build_filename (data, "singularity", "decoder", "history.json"), path);
            } else {
                path = file;
            }
            load ();
        }

        public static bool migrate (string old_path, string new_path) {
            if (FileUtils.test (new_path, FileTest.EXISTS) || !FileUtils.test (old_path, FileTest.EXISTS)) return false;
            DirUtils.create_with_parents (Path.get_dirname (new_path), 0700);
            if (FileUtils.rename (old_path, new_path) != 0) {
                warning ("qrcodes: the old history could not be moved to %s", new_path);
                return false;
            }
            DirUtils.remove (Path.get_dirname (old_path));
            return true;
        }

        public void load () {
            items.clear ();
            load_error = null;
            if (!FileUtils.test (path, FileTest.EXISTS)) return;
            try {
                var parser = new Json.Parser ();
                parser.load_from_file (path);
                var root = parser.get_root ();
                if (root == null || root.get_node_type () != Json.NodeType.ARRAY) {
                    load_error = _("The history file is damaged.");
                    return;
                }
                foreach (var node in root.get_array ().get_elements ()) {
                    if (node.get_node_type () != Json.NodeType.OBJECT) continue;
                    var o = node.get_object ();
                    if (!o.has_member ("text")) continue;
                    string text = o.get_string_member_with_default ("text", "");
                    if (text == "") continue;
                    var e = new HistoryEntry (Origin.from_id (o.get_string_member_with_default ("origin", "scanned")), text,
                        o.get_string_member_with_default ("source", ""), o.get_int_member_with_default ("time", 0),
                        o.get_string_member_with_default ("format", "qr"));
                    string id = o.get_string_member_with_default ("id", "");
                    if (id != "") e.id = id;
                    if (items.size < LIMIT) items.add (e);
                }
            } catch (Error e) {
                load_error = e.message;
            }
        }

        public bool save () {
            var b = new Json.Builder ();
            b.begin_array ();
            foreach (var e in items) {
                b.begin_object ();
                b.set_member_name ("id");
                b.add_string_value (e.id);
                b.set_member_name ("origin");
                b.add_string_value (e.origin.id ());
                b.set_member_name ("text");
                b.add_string_value (e.text);
                b.set_member_name ("source");
                b.add_string_value (e.source);
                b.set_member_name ("format");
                b.add_string_value (e.format);
                b.set_member_name ("time");
                b.add_int_value (e.time);
                b.end_object ();
            }
            b.end_array ();
            var gen = new Json.Generator ();
            gen.pretty = true;
            gen.set_root (b.get_root ());
            try {
                DirUtils.create_with_parents (Path.get_dirname (path), 0700);
                FileUtils.set_contents_full (path, gen.to_data (null), -1, FileSetContentsFlags.CONSISTENT, 0600);
            } catch (Error e) {
                warning ("qrcodes: %s", e.message);
                return false;
            }
            return true;
        }

        public HistoryEntry add (Origin origin, string text, string source, int64 time = -1, string format = "qr") {
            for (int i = 0; i < items.size; i++) {
                if (items[i].origin == origin && items[i].text == text && items[i].format == format) {
                    items.remove_at (i);
                    break;
                }
            }
            var e = new HistoryEntry (origin, text, source, time >= 0 ? time : new DateTime.now_utc ().to_unix (), format);
            items.insert (0, e);
            while (items.size > LIMIT) items.remove_at (items.size - 1);
            commit ();
            return e;
        }

        public void remove (string id) {
            for (int i = 0; i < items.size; i++) {
                if (items[i].id == id) {
                    items.remove_at (i);
                    save ();
                    changed ();
                    return;
                }
            }
        }

        public void clear () {
            items.clear ();
            save ();
            changed ();
        }
    }
}
