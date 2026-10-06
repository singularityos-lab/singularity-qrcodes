namespace Singularity.Apps.QrCodes {

    public class ScanGroup : Object {
        public string source { get; set; default = ""; }
        public string? error { get; set; }
        public Gee.ArrayList<Decoded> codes = new Gee.ArrayList<Decoded> ();

        public ScanGroup (string source) {
            Object (source: source);
        }
    }

    namespace Csv {
        public string field (string raw) {
            string value = raw;
            if (value != "" && "=+-@\t\r".index_of_char (value[0]) >= 0) value = "'" + value;
            bool quote = value.contains (",") || value.contains ("\"") || value.contains ("\n") || value.contains ("\r")
                || value != value.strip ();
            if (!quote) return value;
            return "\"" + value.replace ("\"", "\"\"") + "\"";
        }

        public string row (string[] values) {
            string[] fields = {};
            foreach (string v in values) fields += field (v);
            return string.joinv (",", fields) + "\r\n";
        }

        public string document (Gee.List<ScanGroup> groups) {
            var sb = new StringBuilder ();
            sb.append (row ({ _("File"), _("Format"), _("Type"), _("Content") }));
            foreach (var g in groups) {
                if (g.codes.size == 0) {
                    sb.append (row ({ g.source, "", g.error ?? _("No code found"), "" }));
                    continue;
                }
                foreach (var d in g.codes) {
                    var c = Content.parse_code (d.text, d.format);
                    sb.append (row ({ g.source, d.format.label (), c.kind.label (), d.text }));
                }
            }
            return sb.str;
        }

        public int count (Gee.List<ScanGroup> groups) {
            int n = 0;
            foreach (var g in groups) n += g.codes.size;
            return n;
        }
    }
}
