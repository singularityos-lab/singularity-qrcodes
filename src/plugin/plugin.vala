using Gtk;

[ModuleInit]
public void peas_register_types (TypeModule module) {
    var objmodule = module as Peas.ObjectModule;
    objmodule.register_extension_type (typeof (Singularity.Plugin), typeof (Singularity.Apps.QrCodes.WifiSharePlugin));
}

namespace Singularity.Apps.QrCodes {

    public class WifiSharePlugin : Object, Singularity.Plugin {
        public const string APP_ID = "dev.sinty.qrcodes";
        private Singularity.PluginContext context;
        private Singularity.QuickTile tile;
        private Singularity.SettingsPageAction wifi_action;
        private string? pending_ssid = null;

        public void activate (Singularity.PluginContext context) {
            this.context = context;
            tile = new Singularity.QuickTile ("dev.sinty.qrcodes.share-wifi", _("Share Wi-Fi"), "qrcodes-code-symbolic");
            tile.subtitle = _("As a QR code");
            tile.toggleable = false;
            tile.detail_title = _("Share Wi-Fi");
            tile.clicked.connect (open_in_app);
            tile.set_detail_page (() => {
                var page = new WifiSharePage (pending_ssid);
                pending_ssid = null;
                return page;
            });
            context.add_quick_tile (tile);
            wifi_action = new Singularity.SettingsPageAction ("dev.sinty.qrcodes.share-network", Singularity.SettingsPageAction.WIFI_NETWORK, _("Share Network"), "qrcodes-code-symbolic");
            wifi_action.activated_for.connect ((ssid) => {
                pending_ssid = ssid;
                tile.open_detail_page ();
            });
            context.add_settings_page_action (wifi_action);
        }

        public void deactivate () {
            context.remove_settings_page_action (wifi_action);
            context.remove_quick_tile (tile);
        }

        public Gtk.Widget? get_settings_widget () {
            return null;
        }

        private void open_in_app () {
            var info = new DesktopAppInfo (APP_ID + ".desktop");
            if (info == null) return;
            try {
                info.launch_action ("share-wifi", Gdk.Display.get_default ().get_app_launch_context ());
            } catch (Error e) {
                warning ("qrcodes plugin: %s", e.message);
            }
        }
    }

    public class WifiSharePage : Box {
        private const int VISIBLE_SECONDS = 30;
        private Stack stack;
        private Picture picture;
        private Label network;
        private Label countdown;
        private Label problem;
        private Button show_button;
        private uint timer;
        private int remaining;
        private uint serial;
        private string? ssid;

        public WifiSharePage (string? ssid = null) {
            Object (orientation: Orientation.VERTICAL, spacing: 12);
            margin_start = 12;
            margin_end = 12;
            margin_bottom = 12;
            this.ssid = ssid;

            stack = new Stack ();
            stack.transition_type = StackTransitionType.CROSSFADE;
            stack.vhomogeneous = false;
            append (stack);

            var intro = new Box (Orientation.VERTICAL, 12);
            var hint = new Label (ssid != null
                ? _("Show a code that a phone camera can scan to join %s. The code contains the network password.").printf (ssid)
                : _("Show a code that a phone camera can scan to join the Wi-Fi network this computer is using. The code contains the network password."));
            hint.wrap = true;
            hint.wrap_mode = Pango.WrapMode.WORD_CHAR;
            hint.justify = Justification.CENTER;
            hint.add_css_class ("dim-label");
            intro.append (hint);
            problem = new Label ("");
            problem.wrap = true;
            problem.justify = Justification.CENTER;
            problem.visible = false;
            intro.append (problem);
            show_button = new Button.with_label (_("Show Code"));
            show_button.add_css_class ("suggested-action");
            show_button.halign = Align.CENTER;
            show_button.clicked.connect (reveal);
            intro.append (show_button);
            stack.add_named (intro, "intro");

            var busy = new Box (Orientation.VERTICAL, 12);
            var spinner = new Spinner ();
            spinner.spinning = true;
            spinner.halign = Align.CENTER;
            busy.append (spinner);
            var busy_label = new Label (_("Reading the Wi-Fi network…"));
            busy_label.add_css_class ("dim-label");
            busy.append (busy_label);
            stack.add_named (busy, "busy");

            var shown = new Box (Orientation.VERTICAL, 8);
            network = new Label ("");
            network.add_css_class ("title-4");
            network.ellipsize = Pango.EllipsizeMode.END;
            shown.append (network);
            picture = new Picture ();
            picture.can_shrink = true;
            picture.content_fit = ContentFit.CONTAIN;
            picture.set_size_request (220, 220);
            picture.halign = Align.CENTER;
            shown.append (picture);
            countdown = new Label ("");
            countdown.add_css_class ("caption");
            countdown.add_css_class ("dim-label");
            shown.append (countdown);
            var hide = new Button.with_label (_("Hide Code"));
            hide.halign = Align.CENTER;
            hide.clicked.connect (conceal);
            shown.append (hide);
            stack.add_named (shown, "shown");

            destroy.connect (() => {
                serial++;
                conceal ();
            });
            unmap.connect (() => {
                serial++;
                conceal ();
            });
        }

        private void reveal () {
            uint mine = ++serial;
            problem.visible = false;
            stack.visible_child_name = "busy";
            read_network.begin ((o, res) => {
                if (mine != serial) return;
                string? secret_problem;
                WifiInfo info;
                try {
                    info = read_network.end (res, out secret_problem);
                } catch (NetworkError e) {
                    fail (e.message);
                    return;
                }
                if (secret_problem != null && info.security != "nopass" && info.password == "") {
                    fail (secret_problem);
                    return;
                }
                try {
                    var code = QrCode.encode_text (Payload.wifi (info), QrEcLevel.MEDIUM);
                    var bytes = new Bytes.take (Render.png_bytes (code, int.max (4, Render.module_for_size (code, 440))));
                    picture.paintable = Gdk.Texture.from_bytes (bytes);
                } catch (Error e) {
                    fail (e.message);
                    return;
                }
                network.label = info.ssid;
                stack.visible_child_name = "shown";
                remaining = VISIBLE_SECONDS;
                update_countdown ();
                if (timer != 0) Source.remove (timer);
                timer = Timeout.add_seconds (1, () => {
                    remaining--;
                    if (remaining <= 0) {
                        timer = 0;
                        conceal ();
                        return Source.REMOVE;
                    }
                    update_countdown ();
                    return Source.CONTINUE;
                });
            });
        }

        private async WifiInfo read_network (out string? secret_problem) throws NetworkError {
            if (ssid != null) return yield Network.saved_wifi (ssid, out secret_problem);
            return yield Network.current_wifi (out secret_problem);
        }

        private void update_countdown () {
            countdown.label = ngettext ("Hidden in %d second", "Hidden in %d seconds", remaining).printf (remaining);
        }

        private void fail (string message) {
            problem.label = message;
            problem.visible = true;
            stack.visible_child_name = "intro";
        }

        private void conceal () {
            if (timer != 0) Source.remove (timer);
            timer = 0;
            picture.paintable = null;
            network.label = "";
            stack.visible_child_name = "intro";
        }
    }
}
