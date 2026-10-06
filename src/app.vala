using Gtk;

namespace Singularity.Apps.QrCodes {

    public class QrCodesApp : Singularity.Application {
        public History history;
        private string? pending_action;
        private const string[] LAUNCH_ACTIONS = { "scan-screen", "share-wifi", "new-code" };

        public QrCodesApp () {
            Object (application_id: "dev.sinty.qrcodes", flags: ApplicationFlags.DEFAULT_FLAGS);
            add_main_option ("scan-screen", 0, OptionFlags.NONE, OptionArg.NONE, _("Scan a code in an area of the screen"), null);
            add_main_option ("share-wifi", 0, OptionFlags.NONE, OptionArg.NONE, _("Share the current Wi-Fi network as a code"), null);
            add_main_option ("new-code", 0, OptionFlags.NONE, OptionArg.NONE, _("Create a new code"), null);
            new CodeSearchProvider (this).export (this);
        }

        protected override int handle_local_options (VariantDict options) {
            string? requested = null;
            foreach (unowned string name in LAUNCH_ACTIONS) {
                if (options.contains (name)) requested = name;
            }
            if (requested == null) return -1;
            try {
                register (null);
            } catch (Error e) {
                return 1;
            }
            if (get_is_remote ()) {
                activate_action (requested, null);
                return 0;
            }
            pending_action = requested;
            return -1;
        }

        private QrCodesWindow present_window () {
            activate ();
            return (QrCodesWindow) get_active_window ();
        }

        private void add_launch_actions () {
            var scan_screen = new SimpleAction ("scan-screen", null);
            scan_screen.activate.connect (() => present_window ().scan_screenshot ());
            add_action (scan_screen);
            var share = new SimpleAction ("share-wifi", null);
            share.activate.connect (() => present_window ().activate_window_action ("share-wifi"));
            add_action (share);
            var new_code = new SimpleAction ("new-code", null);
            new_code.activate.connect (() => present_window ().activate_window_action ("new-text"));
            add_action (new_code);
            var scan_image = new SimpleAction ("scan-image", new VariantType ("as"));
            scan_image.activate.connect ((param) => {
                File[] files = {};
                foreach (unowned string uri in param.get_strv ()) files += File.new_for_uri (uri);
                present_window ().scan_files (files);
            });
            add_action (scan_image);
            var show_file = new SimpleAction ("show-file", VariantType.STRING);
            show_file.activate.connect ((param) => {
                try {
                    AppInfo.launch_default_for_uri (File.new_for_path (param.get_string ()).get_uri (), null);
                } catch (Error e) {
                    warning ("qrcodes: %s", e.message);
                }
            });
            add_action (show_file);
        }

        protected override void startup () {
            base.startup ();
            history = new History ();
            var provider = new CssProvider ();
            provider.load_from_string (CSS);
            StyleContext.add_provider_for_display (Gdk.Display.get_default (), provider, STYLE_PROVIDER_PRIORITY_USER + 1);

            var menu = new GLib.Menu ();
            var file = new GLib.Menu ();
            if (Scan.AVAILABLE) {
                var f1 = new GLib.Menu ();
                f1.append (_("Scan with Camera"), "win.scan-camera");
                f1.append (_("Scan an Image…"), "win.scan-image");
                f1.append (_("Scan Several Images…"), "win.scan-batch");
                f1.append (_("Scan a Screenshot…"), "win.scan-screenshot");
                f1.append (_("Scan the Clipboard"), "win.scan-clipboard");
                f1.append (_("Scan Again"), "win.scan-again");
                file.append_section (null, f1);
            }
            var f2 = new GLib.Menu ();
            f2.append (_("New Code"), "win.new-text");
            f2.append (_("New Barcode"), "win.new-barcode");
            f2.append (_("Code from a Contact…"), "win.choose-contact");
            f2.append (_("Share Current Wi-Fi"), "win.share-wifi");
            file.append_section (null, f2);
            var f3 = new GLib.Menu ();
            f3.append (_("Save as PNG…"), "win.save-png");
            f3.append (_("Save as SVG…"), "win.save-svg");
            f3.append (_("Export Results as CSV…"), "win.export-csv");
            file.append_section (null, f3);
            var f4 = new GLib.Menu ();
            f4.append (_("Close Window"), "win.close");
            f4.append (_("Quit"), "app.quit");
            file.append_section (null, f4);
            menu.append_submenu (_("File"), file);

            var edit = new GLib.Menu ();
            var e1 = new GLib.Menu ();
            e1.append (_("Copy"), "win.copy");
            edit.append_section (null, e1);
            var e2 = new GLib.Menu ();
            e2.append (_("Clear History…"), "win.clear-history");
            edit.append_section (null, e2);
            var e3 = new GLib.Menu ();
            e3.append (_("Settings"), "app.settings");
            edit.append_section (null, e3);
            menu.append_submenu (_("Edit"), edit);

            var view = new GLib.Menu ();
            view.append (_("Scan"), "win.show-scan");
            view.append (_("Create"), "win.show-create");
            view.append (_("History"), "win.show-history");
            menu.append_submenu (_("View"), view);
            set_menubar (menu);

            var quit = new SimpleAction ("quit", null);
            quit.activate.connect (() => {
                foreach (var w in get_windows ()) w.close ();
            });
            add_action (quit);
            var settings_action = new SimpleAction ("settings", null);
            settings_action.activate.connect (() => {
                try {
                    Singularity.Shell.ShellService shell = Bus.get_proxy_sync (BusType.SESSION, "dev.sinty.desktop", "/dev/sinty/Shell");
                    shell.open_app_settings ("dev.sinty.qrcodes");
                } catch (Error e) {
                    warning ("qrcodes: could not open the settings: %s", e.message);
                }
            });
            add_action (settings_action);
            add_launch_actions ();
            set_accels_for_action ("app.quit", { "<Control>q" });
            set_accels_for_action ("app.settings", { "<Control>comma" });
            set_accels_for_action ("win.close", { "<Control>w" });
            set_accels_for_action ("win.scan-camera", { "<Control>r" });
            set_accels_for_action ("win.scan-image", { "<Control>o" });
            set_accels_for_action ("win.scan-batch", { "<Control><Shift>o" });
            set_accels_for_action ("win.scan-screenshot", { "<Control><Shift>r" });
            set_accels_for_action ("win.scan-clipboard", { "<Control><Shift>v" });
            set_accels_for_action ("win.new-text", { "<Control>n" });
            set_accels_for_action ("win.new-barcode", { "<Control>b" });
            set_accels_for_action ("win.choose-contact", { "<Control><Shift>k" });
            set_accels_for_action ("win.share-wifi", { "<Control><Shift>w" });
            set_accels_for_action ("win.save-png", { "<Control>s" });
            set_accels_for_action ("win.save-svg", { "<Control><Shift>s" });
            set_accels_for_action ("win.export-csv", { "<Control>e" });
            set_accels_for_action ("win.copy", { "<Control><Shift>c" });
            set_accels_for_action ("win.show-scan", { "<Control>1" });
            set_accels_for_action ("win.show-create", { "<Control>2" });
            set_accels_for_action ("win.show-history", { "<Control>h" });
        }

        public override void activate () {
            var w = get_active_window ();
            if (w == null) w = new QrCodesWindow (this);
            w.present ();
            if (pending_action != null) {
                string name = pending_action;
                pending_action = null;
                activate_action (name, null);
            }
        }

        private const string CSS = """
.qrcodes-stage {
    background-color: #0b0c0f;
}

.qrcodes-hint {
    padding: 8px 18px;
    border-radius: 99px;
    background-color: alpha(black, 0.55);
    color: white;
    font-weight: 700;
}

.qrcodes-code {
    border-radius: 14px;
    background-color: white;
    box-shadow: 0 1px 3px alpha(black, 0.18);
}

.qrcodes-mono {
    font-family: monospace;
}

.qrcodes-text {
    background: transparent;
}
""";
    }

    public static int main (string[] args) {
        Intl.setlocale (LocaleCategory.ALL, "");
        Gst.init (ref args);
        string locale_dir = "/usr/share/locale";
        try {
            string exe = FileUtils.read_link ("/proc/self/exe");
            locale_dir = Path.build_filename (Path.get_dirname (Path.get_dirname (exe)), "share", "locale");
        } catch (Error e) {
        }
        Intl.bindtextdomain ("singularity-qrcodes", locale_dir);
        Intl.bind_textdomain_codeset ("singularity-qrcodes", "UTF-8");
        Intl.textdomain ("singularity-qrcodes");
        return new QrCodesApp ().run (args);
    }
}
