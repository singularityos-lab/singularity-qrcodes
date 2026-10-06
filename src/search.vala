namespace Singularity.Apps.QrCodes {

    public class CodeSearchProvider : Singularity.SearchProviderService {
        private QrCodesApp app;

        public CodeSearchProvider (QrCodesApp app) {
            this.app = app;
        }

        public static string? text_of (string[] terms) {
            if (terms.length < 2 || terms[0].down () != "qr") return null;
            string text = string.joinv (" ", terms[1:terms.length]).strip ();
            return text != "" ? text : null;
        }

        public override async string[] get_initial_results (string[] terms, Cancellable? cancellable) throws Error {
            string? text = text_of (terms);
            if (text == null) return {};
            return { text };
        }

        public override async Singularity.SearchResultMeta[] get_result_metas (string[] ids, Cancellable? cancellable) throws Error {
            Singularity.SearchResultMeta[] metas = {};
            foreach (var id in ids) {
                QrCode code;
                try {
                    code = QrCode.encode_text (id, QrEcLevel.MEDIUM);
                } catch (QrEncodeError e) {
                    continue;
                }
                var meta = new Singularity.SearchResultMeta (id, id);
                meta.description = _("QR code, %d × %d modules").printf (code.size, code.size);
                meta.icon = new ThemedIcon ("dev.sinty.qrcodes");
                meta.preview_icon = new BytesIcon (new Bytes.take (Render.png_bytes (code, int.max (4, Render.module_for_size (code, 160)))));
                meta.preview_large = true;
                meta.add_action ("save", _("Save Image"), "document-save-symbolic");
                metas += meta;
            }
            return metas;
        }

        public override async Singularity.SearchActivationReply? activate_result (string id, string[] terms, uint32 timestamp) throws Error {
            app.activate ();
            var w = app.get_active_window () as QrCodesWindow;
            if (w != null) w.create_from_text (id);
            return null;
        }

        public override async Singularity.SearchActivationReply? activate_action (string id, string action_id, string[] terms, uint32 timestamp) throws Error {
            if (action_id != "save") return null;
            var code = QrCode.encode_text (id, QrEcLevel.MEDIUM);
            string dir = Environment.get_user_special_dir (UserDirectory.PICTURES) ?? Environment.get_home_dir ();
            DirUtils.create_with_parents (dir, 0755);
            string path = Path.build_filename (dir, _("QR Code.png"));
            for (int n = 2; FileUtils.test (path, FileTest.EXISTS); n++) {
                path = Path.build_filename (dir, _("QR Code %d.png").printf (n));
            }
            Render.save_png (code, int.max (8, Render.module_for_size (code, 768)), path);
            var note = new Notification (_("QR Code Saved"));
            note.set_body (Path.get_basename (path));
            note.set_icon (new ThemedIcon ("dev.sinty.qrcodes"));
            note.set_default_action_and_target_value ("app.show-file", new Variant.string (path));
            app.send_notification ("search-save", note);
            return null;
        }

        public override void launch_search (string[] terms, uint32 timestamp) {
            string? text = text_of (terms);
            app.activate ();
            var w = app.get_active_window () as QrCodesWindow;
            if (w != null && text != null) w.create_from_text (text);
        }
    }
}
