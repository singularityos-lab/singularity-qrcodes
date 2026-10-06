using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.QrCodes {

    public class QrCodesWindow : Singularity.Widgets.Window {
        private const string AUTHENTICATOR_ID = "dev.sinty.authenticator.desktop";

        private QrCodesApp app;
        private History history;
        private CameraScanner camera;

        private Stack stack;
        private Overlay overlay;
        private AppSidebar sidebar;
        private Gee.HashMap<string, SidebarRow> rows = new Gee.HashMap<string, SidebarRow> ();
        private Button copy_bubble;
        private Button again_bubble;
        private Button png_bubble;
        private Button svg_bubble;
        private Button clear_bubble;
        private Button csv_bubble;
        private Singularity.Widgets.Toast? last_toast = null;

        private Stack camera_stack;
        private Picture camera_picture;
        private StatusPage camera_error;

        private StatusPage busy_page;
        private Button busy_cancel;
        private Cancellable? batch_cancel;
        private StatusPage nocode_page;

        private Label result_title;
        private Image result_icon;
        private Label result_kind;
        private CodeView result_code;
        private Box result_actions;
        private Button result_back;
        private PreferencesGroup result_details;
        private Label result_raw;
        private Content? current;
        private bool current_from_history;
        private string last_source = "";

        private Label codes_title;
        private Label codes_subtitle;
        private Box codes_groups;
        private Gee.ArrayList<ScanGroup> groups = new Gee.ArrayList<ScanGroup> ();

        private CodeView share_code;
        private Label share_name;
        private Label share_detail;
        private ActionRow share_password;
        private QrCode? shared;
        private WifiInfo? shared_info;

        private BubbleSwitcher kind_switcher;
        private Stack create_forms;
        private TextView create_text;
        private EntryRow wifi_ssid;
        private SelectionRow wifi_security;
        private PasswordRow wifi_password;
        private SwitchRow wifi_hidden;
        private EntryRow contact_name;
        private EntryRow contact_org;
        private EntryRow contact_phone;
        private EntryRow contact_email;
        private EntryRow contact_url;
        private EntryRow contact_address;
        private EntryRow contact_note;
        private SelectionRow bar_format;
        private EntryRow bar_text;
        private PreferencesGroup bar_group;
        private PreferencesGroup options_group;
        private SelectionRow ec_row;
        private QrEcLevel ec_level = QrEcLevel.MEDIUM;
        private CodeView create_code;
        private Label create_info;
        private Stack create_preview_stack;
        private QrCode? created;
        private Barcode? created_bar;
        private string created_text = "";
        private uint create_save_id;

        private PreferencesGroup history_group;
        private Stack history_stack;
        private Label history_error;
        private Gee.ArrayList<Widget> history_rows = new Gee.ArrayList<Widget> ();

        private string[] security_ids = { "WPA", "SAE", "WEP", "nopass" };
        private string[] security_labels;
        private GLib.Settings? settings;

        public QrCodesWindow (QrCodesApp app) {
            Object (application: app);
            this.app = app;
            history = app.history;
            camera = new CameraScanner ();
            set_default_size (1000, 720);
            set_title (_("QR Codes"));
            security_labels = { _("WPA/WPA2"), _("WPA3"), _("WEP"), _("None") };
            var schema = SettingsSchemaSource.get_default ()?.lookup ("dev.sinty.qrcodes", true);
            if (schema != null) settings = new GLib.Settings ("dev.sinty.qrcodes");

            sidebar = new AppSidebar (200);
            add_row ("scan", "camera-photo-symbolic", _("Scan"));
            add_row ("create-home", "document-new-symbolic", _("Create"));
            add_row ("history", "document-open-recent-symbolic", _("History"));
            set_sidebar (sidebar);

            stack = new Stack ();
            stack.transition_type = StackTransitionType.CROSSFADE;
            stack.hhomogeneous = false;
            stack.add_named (build_welcome (), "welcome");
            stack.add_named (Scan.AVAILABLE ? build_scan () : build_no_scan (), "scan");
            stack.add_named (build_camera (), "camera");
            stack.add_named (build_busy (), "busy");
            stack.add_named (build_nocode (), "nocode");
            stack.add_named (build_result (), "result");
            stack.add_named (build_codes (), "codes");
            stack.add_named (build_create_home (), "create-home");
            stack.add_named (build_create (), "create");
            stack.add_named (build_share (), "share");
            stack.add_named (build_history (), "history");
            overlay = new Overlay ();
            overlay.child = stack;
            set_content (overlay);

            add_bubble_widget (kind_switcher);
            copy_bubble = add_bubble_icon ("edit-copy-symbolic", _("Copy (Ctrl+Shift+C)"), () => copy_current ());
            again_bubble = add_bubble_icon ("view-refresh-symbolic", _("Scan Again"), () => scan_again ());
            png_bubble = add_bubble_icon ("document-save-symbolic", _("Save as PNG (Ctrl+S)"), () => save_png ());
            svg_bubble = add_bubble_icon ("document-save-as-symbolic", _("Save as SVG (Ctrl+Shift+S)"), () => save_svg ());
            clear_bubble = add_bubble_icon ("user-trash-symbolic", _("Clear History"), () => confirm_clear ());
            csv_bubble = add_bubble_icon ("x-office-spreadsheet-symbolic", _("Export as CSV (Ctrl+E)"), () => export_csv ());

            add_actions ();
            install_drop ();

            camera.frame.connect ((tex) => {
                camera_picture.paintable = tex;
                if (camera_stack.visible_child_name != "live") camera_stack.visible_child_name = "live";
            });
            camera.decoded.connect ((codes) => {
                camera.stop ();
                show_decoded (codes.to_array (), "camera", _("Camera"));
            });
            camera.failed.connect ((msg) => camera_failed (msg));
            history.changed.connect (fill_history);
            close_request.connect (() => {
                camera.stop ();
                return false;
            });

            fill_history ();
            if (history.load_error != null) show_toast (_("The history could not be read."));
            show_page ("welcome");
        }

        private void add_row (string id, string icon, string title) {
            var row = new SidebarRow (icon, title);
            row.clicked.connect (() => show_page (id));
            if (id == "scan" && !Scan.AVAILABLE) row.tooltip_text = _("Scanning is not available");
            rows[id] = row;
            sidebar.box.append (row);
        }

        private delegate void Callback ();

        private void action (string name, owned Callback cb, bool enabled = true) {
            var a = new SimpleAction (name, null);
            a.activate.connect (() => cb ());
            a.set_enabled (enabled);
            add_action (a);
        }

        private void set_action_enabled (string name, bool enabled) {
            var a = lookup_action (name) as SimpleAction;
            if (a != null) a.set_enabled (enabled);
        }

        private void add_actions () {
            action ("scan-camera", () => start_camera (), Scan.AVAILABLE);
            action ("scan-image", () => open_image (), Scan.AVAILABLE);
            action ("scan-screenshot", () => scan_screenshot (), Scan.AVAILABLE);
            action ("scan-clipboard", () => scan_clipboard (), Scan.AVAILABLE);
            action ("save-png", () => save_png (), false);
            action ("save-svg", () => save_svg (), false);
            action ("copy", () => copy_current (), false);
            action ("clear-history", () => confirm_clear (), history.items.size > 0);
            action ("show-scan", () => show_page ("scan"));
            action ("show-create", () => show_page ("create-home"));
            action ("new-text", () => open_form ("text"));
            action ("new-barcode", () => open_form ("barcode"));
            action ("share-wifi", () => share_wifi ());
            action ("choose-contact", () => choose_contact ());
            action ("scan-batch", () => open_batch (), Scan.AVAILABLE);
            action ("export-csv", () => export_csv (), false);
            action ("show-history", () => show_page ("history"));
            action ("scan-again", () => scan_again (), false);
            action ("close", () => close ());
        }

        private void install_drop () {
            var drop = new DropTarget (Type.INVALID, Gdk.DragAction.COPY);
            drop.set_gtypes ({ typeof (Gdk.FileList), typeof (Gdk.Texture) });
            drop.drop.connect ((value, x, y) => {
                if (!Scan.AVAILABLE) {
                    show_toast (_("Scanning is not available in this copy of QR Codes"));
                    return false;
                }
                if (value.holds (typeof (Gdk.Texture))) {
                    scan_texture ((Gdk.Texture) value.get_object (), "image");
                    return true;
                }
                if (value.holds (typeof (Gdk.FileList))) {
                    var files = file_list (((Gdk.FileList) value.get_boxed ()).get_files ());
                    if (files.size > 1) {
                        scan_batch (files);
                        return true;
                    }
                    if (files.size == 1) {
                        scan_file (files[0], "image");
                        return true;
                    }
                }
                return false;
            });
            ((Widget) this).add_controller (drop);
        }

        private Widget build_welcome () {
            var wp = new WelcomePage ();
            wp.app_icon_name = "dev.sinty.qrcodes";
            wp.title = _("QR Codes");
            if (Scan.AVAILABLE) {
                wp.subtitle = _("Scan QR codes and barcodes with your camera or from pictures, and create your own.");
                wp.add_action ("camera-web", _("Scan with Camera"), _("Point your camera at a QR code or a barcode"), () => start_camera ());
                wp.add_action ("image-x-generic", _("Scan an Image"), _("Read the codes in a picture or a screenshot"), () => open_image ());
            } else {
                wp.subtitle = _("Create QR codes for links, Wi-Fi networks and contacts, and barcodes for products.");
            }
            wp.add_action ("text-x-generic", _("Create a Code"), _("Turn text, a link, a Wi-Fi network or a contact into a QR code, or make a barcode"), () => show_page ("create-home"));
            if (history.items.size > 0) {
                wp.add_action ("document-open-recent", _("History"), _("Codes you scanned or created before"), () => show_page ("history"));
            }
            if (!Scan.AVAILABLE) {
                var note = new Label (_("Scanning is not available because this copy of QR Codes was built without the ZBar library."));
                note.wrap = true;
                note.max_width_chars = 50;
                note.justify = Justification.CENTER;
                note.add_css_class ("dim-label");
                wp.set_extra_widget (note);
            }
            return wp;
        }

        private Box column (int max_width) {
            var box = new Box (Orientation.VERTICAL, 18);
            box.margin_start = 24;
            box.margin_end = 24;
            box.margin_top = 12;
            box.margin_bottom = 32;
            box.width_request = 320;
            box.hexpand = true;
            box.halign = Align.CENTER;
            box.set_size_request (int.min (max_width, 640), -1);
            return box;
        }

        private ScrolledWindow scroller (Widget child) {
            var scroll = new ScrolledWindow ();
            scroll.hscrollbar_policy = PolicyType.NEVER;
            scroll.child = child;
            apply_view_edge (scroll);
            return scroll;
        }

        private ActionRow nav_row (string icon, string title, string subtitle, owned Callback cb) {
            var row = new ActionRow (title, subtitle, icon);
            row.activatable = true;
            var arrow = new Image.from_icon_name ("go-next-symbolic");
            arrow.add_css_class ("dim-label");
            row.add_suffix (arrow);
            row.activated.connect (() => cb ());
            return row;
        }

        private Widget build_scan () {
            var wp = new WelcomePage ();
            wp.app_icon_name = "dev.sinty.qrcodes";
            wp.title = _("Scan a Code");
            wp.subtitle = _("Choose where the code is, or drop pictures anywhere in this window.");
            wp.is_section = true;
            var ctrl = Gdk.ModifierType.CONTROL_MASK;
            var ctrl_shift = ctrl | Gdk.ModifierType.SHIFT_MASK;
            wp.add_action_with_caption ("camera-web", _("Camera"), _("Point your camera at the code"), accelerator_get_label (Gdk.Key.r, ctrl), () => start_camera ());
            wp.add_action_with_caption ("image-x-generic", _("Image File"), _("Pick a picture that shows a code"), accelerator_get_label (Gdk.Key.o, ctrl), () => open_image ());
            wp.add_action_with_caption ("applets-screenshooter", _("Screenshot"), _("Select the part of the screen with the code"), accelerator_get_label (Gdk.Key.r, ctrl_shift), () => scan_screenshot ());
            wp.add_action_with_caption ("edit-paste", _("Clipboard"), _("Read a picture you copied"), accelerator_get_label (Gdk.Key.v, ctrl_shift), () => scan_clipboard ());
            wp.add_action_with_caption ("folder-pictures", _("Several Images"), _("Read every code in many pictures at once and export the list"), accelerator_get_label (Gdk.Key.o, ctrl_shift), () => open_batch ());
            return wp;
        }

        private Widget build_create_home () {
            var wp = new WelcomePage ();
            wp.app_icon_name = "dev.sinty.qrcodes";
            wp.title = _("Create a Code");
            wp.subtitle = _("Choose what the code holds. You can save it as a picture or copy it.");
            wp.is_section = true;
            var ctrl = Gdk.ModifierType.CONTROL_MASK;
            var ctrl_shift = ctrl | Gdk.ModifierType.SHIFT_MASK;
            wp.add_action_with_caption ("network-wireless", _("Share Current Wi-Fi"), _("Show a code that lets guests join the network you use now"), accelerator_get_label (Gdk.Key.w, ctrl_shift), () => share_wifi ());
            wp.add_action_with_caption ("text-x-generic", _("Text or Link"), _("Any text or a web address"), accelerator_get_label (Gdk.Key.n, ctrl), () => open_form ("text"));
            wp.add_action ("network-wireless", _("Wi-Fi Network"), _("Type the name and password of a network"), () => open_form ("wifi"));
            wp.add_action ("x-office-addressbook", _("Contact Card"), _("Type a card or choose someone from Contacts"), () => open_form ("contact"));
            wp.add_action_with_caption ("barcode", _("Barcode"), _("EAN-13, EAN-8, UPC-A or Code 128"), accelerator_get_label (Gdk.Key.b, ctrl), () => open_form ("barcode"));
            return wp;
        }

        private Widget build_share () {
            var box = new Box (Orientation.VERTICAL, 16);
            box.valign = Align.CENTER;
            box.halign = Align.CENTER;
            box.margin_top = 24;
            box.margin_bottom = 32;
            box.margin_start = 24;
            box.margin_end = 24;
            share_code = new CodeView (360);
            share_code.add_css_class ("qrcodes-code");
            share_code.halign = Align.CENTER;
            box.append (share_code);
            share_name = new Label ("");
            share_name.add_css_class ("title-1");
            share_name.wrap = true;
            share_name.wrap_mode = Pango.WrapMode.WORD_CHAR;
            share_name.justify = Justification.CENTER;
            share_name.selectable = true;
            share_name.max_width_chars = 30;
            box.append (share_name);
            share_detail = new Label ("");
            share_detail.add_css_class ("dim-label");
            share_detail.wrap = true;
            share_detail.justify = Justification.CENTER;
            share_detail.max_width_chars = 44;
            box.append (share_detail);
            var group = new PreferencesGroup ();
            group.width_request = 360;
            share_password = new ActionRow (_("Password"), "");
            share_password.activatable = false;
            bool shown = false;
            var reveal = new Button.from_icon_name ("view-reveal-symbolic");
            reveal.add_css_class ("flat");
            reveal.valign = Align.CENTER;
            reveal.tooltip_text = _("Show");
            reveal.clicked.connect (() => {
                if (shared_info == null) return;
                shown = !shown;
                share_password.subtitle = shown ? shared_info.password : mask (shared_info.password);
                reveal.icon_name = shown ? "view-conceal-symbolic" : "view-reveal-symbolic";
                reveal.tooltip_text = shown ? _("Hide") : _("Show");
            });
            share_password.add_suffix (reveal);
            var copy = new Button.from_icon_name ("edit-copy-symbolic");
            copy.add_css_class ("flat");
            copy.valign = Align.CENTER;
            copy.tooltip_text = _("Copy Password");
            copy.clicked.connect (() => {
                if (shared_info != null) copy_text (shared_info.password, _("Password copied"));
            });
            share_password.add_suffix (copy);
            share_password.notify["visible"].connect (() => {
                shown = false;
                reveal.icon_name = "view-reveal-symbolic";
            });
            group.add_row (share_password);
            box.append (group);
            var buttons = new Box (Orientation.HORIZONTAL, 12);
            buttons.halign = Align.CENTER;
            var save = new Button.with_label (_("Save"));
            save.add_css_class ("pill");
            save.add_css_class ("suggested-action");
            save.clicked.connect (() => save_png ());
            buttons.append (save);
            var copy_image = new Button.with_label (_("Copy"));
            copy_image.add_css_class ("pill");
            copy_image.clicked.connect (() => copy_current ());
            buttons.append (copy_image);
            box.append (buttons);
            return scroller (box);
        }

        private Widget build_codes () {
            var box = column (720);
            var head = new Box (Orientation.VERTICAL, 4);
            codes_title = new Label ("");
            codes_title.add_css_class ("title-2");
            codes_title.xalign = 0;
            codes_title.wrap = true;
            head.append (codes_title);
            codes_subtitle = new Label ("");
            codes_subtitle.add_css_class ("dim-label");
            codes_subtitle.xalign = 0;
            codes_subtitle.wrap = true;
            head.append (codes_subtitle);
            box.append (head);
            codes_groups = new Box (Orientation.VERTICAL, 18);
            box.append (codes_groups);
            return scroller (box);
        }

        private Widget build_no_scan () {
            var page = new StatusPage ();
            page.icon_name = "dialog-warning";
            page.title = _("Scanning Is Not Available");
            page.description = _("This copy of QR Codes was built without the ZBar library, which reads QR codes. You can still create codes.");
            var b = new Button.with_label (_("Create a Code"));
            b.add_css_class ("pill");
            b.add_css_class ("suggested-action");
            b.halign = Align.CENTER;
            b.clicked.connect (() => show_page ("create-home"));
            page.child = b;
            return page;
        }

        private Widget build_camera () {
            camera_stack = new Stack ();
            camera_stack.transition_type = StackTransitionType.CROSSFADE;

            var starting = new Box (Orientation.VERTICAL, 12);
            starting.valign = Align.CENTER;
            starting.halign = Align.CENTER;
            var spinner = new Spinner ();
            spinner.spinning = true;
            spinner.set_size_request (32, 32);
            starting.append (spinner);
            var sl = new Label (_("Starting the camera…"));
            sl.add_css_class ("dim-label");
            starting.append (sl);
            camera_stack.add_named (starting, "starting");

            var live = new Overlay ();
            live.add_css_class ("qrcodes-stage");
            camera_picture = new Picture ();
            camera_picture.content_fit = ContentFit.CONTAIN;
            camera_picture.hexpand = true;
            camera_picture.vexpand = true;
            camera_picture.update_property (AccessibleProperty.LABEL, _("Camera preview"), -1);
            live.child = camera_picture;
            var hint = new Label (_("Point the camera at a QR code"));
            hint.add_css_class ("qrcodes-hint");
            hint.halign = Align.CENTER;
            hint.valign = Align.END;
            hint.margin_bottom = 28;
            hint.can_target = false;
            live.add_overlay (hint);
            camera_stack.add_named (live, "live");

            camera_error = new StatusPage ();
            camera_error.icon_name = "camera-web-symbolic";
            camera_error.title = _("Camera Not Available");
            var box = new Box (Orientation.HORIZONTAL, 12);
            box.halign = Align.CENTER;
            var retry = new Button.with_label (_("Try Again"));
            retry.add_css_class ("pill");
            retry.add_css_class ("suggested-action");
            retry.clicked.connect (() => start_camera ());
            box.append (retry);
            var image = new Button.with_label (_("Scan an Image"));
            image.add_css_class ("pill");
            image.clicked.connect (() => open_image ());
            box.append (image);
            camera_error.child = box;
            camera_stack.add_named (camera_error, "error");
            return camera_stack;
        }

        private Widget build_busy () {
            busy_page = new StatusPage ();
            busy_page.icon_name = "image-x-generic-symbolic";
            busy_page.title = _("Looking for a Code…");
            var busy_box = new Box (Orientation.VERTICAL, 18);
            var spinner = new Spinner ();
            spinner.spinning = true;
            spinner.set_size_request (24, 24);
            spinner.halign = Align.CENTER;
            busy_box.append (spinner);
            busy_cancel = new Button.with_label (_("Stop"));
            busy_cancel.add_css_class ("pill");
            busy_cancel.halign = Align.CENTER;
            busy_cancel.visible = false;
            busy_cancel.clicked.connect (() => {
                if (batch_cancel != null) batch_cancel.cancel ();
            });
            busy_box.append (busy_cancel);
            busy_page.child = busy_box;
            return busy_page;
        }

        private Widget build_nocode () {
            nocode_page = new StatusPage ();
            nocode_page.icon_name = "image-missing-symbolic";
            nocode_page.title = _("No Code Found");
            var box = new Box (Orientation.HORIZONTAL, 12);
            box.halign = Align.CENTER;
            var again = new Button.with_label (_("Try Another Image"));
            again.add_css_class ("pill");
            again.add_css_class ("suggested-action");
            again.clicked.connect (() => open_image ());
            box.append (again);
            var cam = new Button.with_label (_("Use the Camera"));
            cam.add_css_class ("pill");
            cam.clicked.connect (() => start_camera ());
            box.append (cam);
            nocode_page.child = box;
            return nocode_page;
        }

        private Widget build_result () {
            var box = column (720);

            result_back = new Button ();
            var back_box = new Box (Orientation.HORIZONTAL, 6);
            back_box.append (new Image.from_icon_name ("go-previous-symbolic"));
            back_box.append (new Label (_("All Codes")));
            result_back.child = back_box;
            result_back.add_css_class ("flat");
            result_back.halign = Align.START;
            result_back.visible = false;
            result_back.clicked.connect (() => show_page ("codes"));
            box.append (result_back);

            var header = new Box (Orientation.HORIZONTAL, 24);
            var text_box = new Box (Orientation.VERTICAL, 8);
            text_box.hexpand = true;
            text_box.valign = Align.CENTER;
            var kind_box = new Box (Orientation.HORIZONTAL, 8);
            result_icon = new Image ();
            result_icon.pixel_size = 16;
            result_icon.add_css_class ("dim-label");
            kind_box.append (result_icon);
            result_kind = new Label ("");
            result_kind.add_css_class ("dim-label");
            result_kind.xalign = 0;
            kind_box.append (result_kind);
            text_box.append (kind_box);
            result_title = new Label ("");
            result_title.add_css_class ("title-2");
            result_title.wrap = true;
            result_title.wrap_mode = Pango.WrapMode.WORD_CHAR;
            result_title.selectable = true;
            result_title.xalign = 0;
            text_box.append (result_title);
            result_actions = new Box (Orientation.HORIZONTAL, 8);
            result_actions.margin_top = 8;
            text_box.append (result_actions);
            header.append (text_box);
            result_code = new CodeView (148);
            result_code.add_css_class ("qrcodes-code");
            result_code.valign = Align.CENTER;
            header.append (result_code);
            box.append (header);

            result_details = new PreferencesGroup ();
            box.append (result_details);

            var raw_group = new PreferencesGroup (_("Content"), _("Exactly what the code holds"));
            result_raw = new Label ("");
            result_raw.wrap = true;
            result_raw.wrap_mode = Pango.WrapMode.WORD_CHAR;
            result_raw.selectable = true;
            result_raw.xalign = 0;
            result_raw.add_css_class ("qrcodes-mono");
            result_raw.margin_top = 12;
            result_raw.margin_bottom = 12;
            result_raw.margin_start = 12;
            result_raw.margin_end = 12;
            var raw_row = new ListBoxRow ();
            raw_row.activatable = false;
            raw_row.child = result_raw;
            raw_group.add_row (raw_row);
            var copy_raw = new Button.from_icon_name ("edit-copy-symbolic");
            copy_raw.add_css_class ("flat");
            copy_raw.tooltip_text = _("Copy");
            copy_raw.clicked.connect (() => copy_current ());
            raw_group.add_header_suffix (copy_raw);
            box.append (raw_group);
            return scroller (box);
        }

        private Widget build_create () {
            var outer = new Box (Orientation.HORIZONTAL, 0);

            var form = new Box (Orientation.VERTICAL, 18);
            form.margin_start = 24;
            form.margin_end = 12;
            form.margin_top = 12;
            form.margin_bottom = 32;
            form.width_request = 360;

            create_forms = new Stack ();
            create_forms.vhomogeneous = false;
            create_forms.transition_type = StackTransitionType.CROSSFADE;
            create_forms.add_titled (build_text_form (), "text", _("Text"));
            create_forms.add_titled (build_wifi_form (), "wifi", _("Wi-Fi"));
            create_forms.add_titled (build_contact_form (), "contact", _("Contact"));
            create_forms.add_titled (build_barcode_form (), "barcode", _("Barcode"));
            create_forms.notify["visible-child-name"].connect (() => {
                if (options_group == null || create_preview_stack == null) return;
                options_group.visible = create_forms.visible_child_name != "barcode";
                update_created ();
            });
            kind_switcher = new BubbleSwitcher (create_forms);
            form.append (create_forms);

            var options = new PreferencesGroup (_("Options"));
            options_group = options;
            string[] ec_labels = {};
            foreach (var l in QrEcLevel.all ()) ec_labels += l.label ();
            ec_row = new SelectionRow (_("Error Correction"), ec_labels, ec_level.label ());
            ec_row.subtitle = _("Higher levels still scan when the code is partly damaged or covered, but make it denser");
            ec_row.selected.connect ((item) => {
                foreach (var l in QrEcLevel.all ()) if (l.label () == item) ec_level = l;
                ec_row.current_value = ec_level.label ();
                update_created ();
            });
            options.add_row (ec_row);
            form.append (options);

            var form_scroll = scroller (form);
            form_scroll.hexpand = false;
            form_scroll.width_request = 400;
            outer.append (form_scroll);

            var preview = new Box (Orientation.VERTICAL, 16);
            preview.hexpand = true;
            preview.vexpand = true;
            preview.valign = Align.CENTER;
            preview.halign = Align.CENTER;
            preview.margin_start = 12;
            preview.margin_end = 24;
            preview.margin_top = 24;
            preview.margin_bottom = 24;
            create_preview_stack = new Stack ();
            create_preview_stack.transition_type = StackTransitionType.CROSSFADE;
            create_code = new CodeView (320);
            create_code.add_css_class ("qrcodes-code");
            create_preview_stack.add_named (create_code, "code");
            var empty = new StatusPage ();
            empty.icon_name = "dev.sinty.qrcodes";
            empty.title = _("Nothing to Show Yet");
            empty.description = _("Fill in the form and the code appears here.");
            create_preview_stack.add_named (empty, "empty");
            preview.append (create_preview_stack);
            create_info = new Label ("");
            create_info.add_css_class ("dim-label");
            create_info.wrap = true;
            create_info.max_width_chars = 40;
            create_info.justify = Justification.CENTER;
            preview.append (create_info);
            outer.append (preview);
            apply_view_edge (preview);
            return outer;
        }

        private Widget build_text_form () {
            var group = new PreferencesGroup (_("Text"), _("Any text or a web address"));
            create_text = new TextView ();
            create_text.wrap_mode = WrapMode.WORD_CHAR;
            create_text.top_margin = 10;
            create_text.bottom_margin = 10;
            create_text.left_margin = 12;
            create_text.right_margin = 12;
            create_text.accepts_tab = false;
            create_text.add_css_class ("qrcodes-text");
            create_text.update_property (AccessibleProperty.LABEL, _("Text or Web Address"), -1);
            create_text.buffer.changed.connect (() => schedule_update ());
            var scroll = new ScrolledWindow ();
            scroll.hscrollbar_policy = PolicyType.NEVER;
            scroll.min_content_height = 140;
            scroll.max_content_height = 320;
            scroll.propagate_natural_height = true;
            scroll.child = create_text;
            var row = new ListBoxRow ();
            row.activatable = false;
            row.child = scroll;
            group.add_row (row);
            return group;
        }

        private EntryRow entry_row (PreferencesGroup group, string title) {
            var row = new EntryRow (title);
            row.entry_changed.connect (() => schedule_update ());
            group.add_row (row);
            return row;
        }

        private Widget build_wifi_form () {
            var group = new PreferencesGroup (_("Wi-Fi Network"), _("Guests scan this code to join your network"));
            wifi_ssid = entry_row (group, _("Network Name"));
            wifi_security = new SelectionRow (_("Security"), security_labels, security_labels[0]);
            wifi_security.selected.connect ((item) => {
                wifi_security.current_value = item;
                wifi_password.visible = item != security_labels[3];
                update_created ();
            });
            group.add_row (wifi_security);
            wifi_password = new PasswordRow (_("Password"));
            wifi_password.entry_changed.connect (() => schedule_update ());
            group.add_row (wifi_password);
            wifi_hidden = new SwitchRow (_("Hidden Network"), _("The network does not broadcast its name"));
            wifi_hidden.notify["active"].connect (() => update_created ());
            group.add_row (wifi_hidden);
            return group;
        }

        private Widget build_contact_form () {
            var group = new PreferencesGroup (_("Contact"), _("Share a contact card"));
            var choose = nav_row ("avatar-default-symbolic", _("Choose from Contacts"), _("Fill the card with someone you know"), () => choose_contact ());
            choose.tooltip_text = _("Ctrl+Shift+K");
            group.add_row (choose);
            contact_name = entry_row (group, _("Name"));
            contact_org = entry_row (group, _("Organization"));
            contact_phone = entry_row (group, _("Phone"));
            contact_email = entry_row (group, _("Email"));
            contact_url = entry_row (group, _("Website"));
            contact_address = entry_row (group, _("Address"));
            contact_note = entry_row (group, _("Note"));
            return group;
        }

        private Widget build_barcode_form () {
            bar_group = new PreferencesGroup (_("Barcode"), "");
            string[] labels = {};
            foreach (var f in CodeFormat.barcodes ()) labels += f.label ();
            bar_format = new SelectionRow (_("Format"), labels, labels[0]);
            bar_format.selected.connect ((item) => {
                bar_format.current_value = item;
                update_bar_hint ();
                update_created ();
            });
            bar_group.add_row (bar_format);
            bar_text = entry_row (bar_group, _("Code"));
            update_bar_hint ();
            return bar_group;
        }

        private CodeFormat bar_format_value () {
            foreach (var f in CodeFormat.barcodes ()) if (f.label () == bar_format.current_value) return f;
            return CodeFormat.EAN13;
        }

        private void update_bar_hint () {
            var f = bar_format_value ();
            if (f == CodeFormat.CODE128) {
                bar_group.description = _("Letters, digits and symbols, up to %d characters, for labels and shipping").printf (Barcode.MAX_CODE128);
            } else {
                bar_group.description = _("%d digits for products; leave out the last one and it is worked out for you").printf (f.digits ());
            }
        }

        private Widget build_history () {
            history_stack = new Stack ();
            var empty = new WelcomePage ();
            empty.is_section = true;
            empty.app_icon_name = "document-open-recent";
            empty.title = _("No History Yet");
            empty.subtitle = _("Codes you scan or create appear here.");
            if (Scan.AVAILABLE) empty.add_action ("camera-web", _("Scan a Code"), _("With the camera, from an image or from the screen"), () => show_page ("scan"));
            empty.add_action ("barcode", _("Create a Code"), _("For a link, a text, a Wi-Fi network or a contact"), () => show_page ("create-home"));
            history_stack.add_named (empty, "empty");
            var box = column (720);
            history_error = new Label ("");
            history_error.add_css_class ("error");
            history_error.wrap = true;
            history_error.xalign = 0;
            history_error.visible = false;
            box.append (history_error);
            history_group = new PreferencesGroup (_("History"), _("The last %d codes you scanned or created").printf (History.LIMIT));
            var clear = new Button.with_label (_("Clear"));
            clear.clicked.connect (() => confirm_clear ());
            history_group.add_header_suffix (clear);
            box.append (history_group);
            history_stack.add_named (scroller (box), "list");
            return history_stack;
        }

        private void show_page (string name) {
            if (name != "camera" && camera.running) camera.stop ();
            stack.visible_child_name = name;
            bool welcome = name == "welcome";
            set_sidebar_visible (!welcome);
            string section = name;
            if (name == "camera" || name == "result" || name == "busy" || name == "nocode" || name == "codes") section = "scan";
            if (name == "create" || name == "share") section = "create-home";
            if (name == "result" && current != null && current_from_history) section = "history";
            foreach (var e in rows.entries) e.value.set_active (e.key == section);
            bool makes = name == "create" || name == "share";
            copy_bubble.visible = name == "result" || name == "codes" || makes;
            copy_bubble.tooltip_text = makes ? _("Copy Image (Ctrl+Shift+C)") : (name == "codes" ? _("Copy All (Ctrl+Shift+C)") : _("Copy Text (Ctrl+Shift+C)"));
            again_bubble.visible = Scan.AVAILABLE && (name == "result" || name == "nocode" || name == "codes") && last_source != "";
            png_bubble.visible = makes;
            svg_bubble.visible = makes;
            clear_bubble.visible = name == "history";
            csv_bubble.visible = name == "codes";
            kind_switcher.visible = name == "create";
            if (name != "result") current_from_history = false;
            sync_actions ();
            if (name == "create") {
                options_group.visible = create_forms.visible_child_name != "barcode";
                update_created ();
                Idle.add (() => {
                    if (create_forms.visible_child_name == "text") create_text.grab_focus ();
                    return Source.REMOVE;
                });
            }
        }

        private void sync_actions () {
            string name = stack.visible_child_name ?? "";
            bool can_save = (name == "create" && (created != null || created_bar != null)) || (name == "share" && shared != null);
            png_bubble.sensitive = can_save;
            svg_bubble.sensitive = can_save;
            set_action_enabled ("save-png", can_save);
            set_action_enabled ("save-svg", can_save);
            bool has_codes = name == "codes" && Csv.count (groups) > 0;
            bool can_copy = (name == "result" && current != null) || can_save || has_codes;
            copy_bubble.sensitive = can_copy;
            set_action_enabled ("copy", can_copy);
            set_action_enabled ("scan-again", again_bubble.visible);
            csv_bubble.sensitive = has_codes || (name == "codes" && groups.size > 0);
            set_action_enabled ("export-csv", name == "codes" && groups.size > 0);
            bool has_history = history.items.size > 0;
            clear_bubble.sensitive = has_history;
            set_action_enabled ("clear-history", has_history);
        }

        public void start_camera () {
            if (!Scan.AVAILABLE) return;
            show_page ("camera");
            camera_stack.visible_child_name = "starting";
            camera_picture.paintable = null;
            camera.start.begin ((o, res) => {
                try {
                    camera.start.end (res);
                } catch (Error e) {
                    if (e is PortalError.CANCELLED) {
                        show_page ("scan");
                        return;
                    }
                    camera_failed (e.message);
                }
            });
        }

        private void camera_failed (string message) {
            if (stack.visible_child_name != "camera") return;
            camera_error.description = message;
            camera_stack.visible_child_name = "error";
        }

        public void open_image () {
            if (!Scan.AVAILABLE) return;
            var dialog = new FileDialog ();
            dialog.title = _("Scan an Image");
            var filters = new GLib.ListStore (typeof (FileFilter));
            var images = new FileFilter ();
            images.name = _("Images");
            images.add_mime_type ("image/*");
            filters.append (images);
            dialog.filters = filters;
            dialog.default_filter = images;
            string? pics = Environment.get_user_special_dir (UserDirectory.PICTURES);
            if (pics != null) dialog.initial_folder = File.new_for_path (pics);
            dialog.open.begin (this, null, (o, res) => {
                try {
                    var file = dialog.open.end (res);
                    if (file != null) scan_file (file, "image");
                } catch (Error e) {
                }
            });
        }

        public void scan_screenshot () {
            if (!Scan.AVAILABLE) return;
            Portal.screenshot.begin ("", (o, res) => {
                try {
                    string uri = Portal.screenshot.end (res);
                    scan_file (File.new_for_uri (uri), "screenshot");
                } catch (PortalError e) {
                    if (e is PortalError.CANCELLED) return;
                    show_error (_("Could Not Take a Screenshot"), (e is PortalError.UNSUPPORTED) ? _("Taking screenshots is not supported by the desktop portal on this system.") : e.message);
                }
            });
        }

        public void scan_clipboard () {
            if (!Scan.AVAILABLE) return;
            var clipboard = get_clipboard ();
            var formats = clipboard.get_formats ();
            if (formats.contain_gtype (typeof (Gdk.Texture))) {
                clipboard.read_texture_async.begin (null, (o, res) => {
                    try {
                        var tex = clipboard.read_texture_async.end (res);
                        if (tex != null) {
                            scan_texture (tex, "clipboard");
                            return;
                        }
                    } catch (Error e) {
                    }
                    show_toast (_("The picture in the clipboard could not be read"));
                });
            } else if (formats.contain_gtype (typeof (Gdk.FileList))) {
                clipboard.read_value_async.begin (typeof (Gdk.FileList), Priority.DEFAULT, null, (o, res) => {
                    try {
                        var v = clipboard.read_value_async.end (res);
                        var files = file_list (((Gdk.FileList) v.get_boxed ()).get_files ());
                        if (files.size > 1) {
                            scan_batch (files);
                            return;
                        }
                        if (files.size == 1) {
                            scan_file (files[0], "clipboard");
                            return;
                        }
                    } catch (Error e) {
                    }
                    show_toast (_("The clipboard does not hold a picture"));
                });
            } else {
                show_toast (_("The clipboard does not hold a picture"));
            }
        }

        private static string file_label (File file) {
            string? name = null;
            try {
                var fi = file.query_info (FileAttribute.STANDARD_DISPLAY_NAME, FileQueryInfoFlags.NONE);
                name = fi.get_display_name ();
            } catch (Error e) {
            }
            return name ?? file.get_basename () ?? file.get_uri ();
        }

        private static string read_error (Error e) {
            if ((e is FileError.NOENT) || (e is IOError.NOT_FOUND)) return _("The file no longer exists.");
            if ((e is FileError.ACCES) || (e is IOError.PERMISSION_DENIED)) return _("QR Codes is not allowed to open this file.");
            return _("The file is not a picture QR Codes can open.");
        }

        private void scan_file (File file, string source) {
            show_page ("busy");
            busy_page.title = _("Looking for Codes…");
            busy_page.description = file.get_basename () ?? "";
            busy_cancel.visible = false;
            string label = file_label (file);
            scan_file_async.begin (file, (o, res) => {
                try {
                    var found = scan_file_async.end (res);
                    show_decoded (found, source, label);
                } catch (Error e) {
                    nocode_page.title = _("Could Not Read the Picture");
                    nocode_page.description = read_error (e);
                    last_source = source;
                    show_page ("nocode");
                }
            });
        }

        private async Decoded[] scan_file_async (File file) throws Error {
            Bytes bytes = yield file.load_bytes_async (null, null);
            Decoded[] found = {};
            Error? failure = null;
            new Thread<void*> ("qrcodes-scan", () => {
                try {
                    var stream = new MemoryInputStream.from_bytes (bytes);
                    var pixbuf = new Gdk.Pixbuf.from_stream (stream);
                    var t = pixbuf.apply_embedded_orientation ();
                    found = Scan.decode_pixbuf (t ?? pixbuf);
                } catch (Error e) {
                    failure = e;
                }
                Idle.add (scan_file_async.callback);
                return null;
            });
            yield;
            if (failure != null) throw failure;
            return found;
        }

        public void open_batch () {
            if (!Scan.AVAILABLE) return;
            var dialog = new FileDialog ();
            dialog.title = _("Scan Several Images");
            var filters = new GLib.ListStore (typeof (FileFilter));
            var images = new FileFilter ();
            images.name = _("Images");
            images.add_mime_type ("image/*");
            filters.append (images);
            dialog.filters = filters;
            dialog.default_filter = images;
            string? pics = Environment.get_user_special_dir (UserDirectory.PICTURES);
            if (pics != null) dialog.initial_folder = File.new_for_path (pics);
            dialog.open_multiple.begin (this, null, (o, res) => {
                try {
                    var model = dialog.open_multiple.end (res);
                    if (model == null) return;
                    var files = new Gee.ArrayList<File> ();
                    for (uint i = 0; i < model.get_n_items (); i++) files.add ((File) model.get_item (i));
                    if (files.size == 1) scan_file (files[0], "image");
                    else if (files.size > 1) scan_batch (files);
                } catch (Error e) {
                }
            });
        }

        private static Gee.ArrayList<File> file_list (SList<weak File> files) {
            var list = new Gee.ArrayList<File> ();
            foreach (var f in files) list.add (f);
            return list;
        }

        public void scan_files (File[] files) {
            if (!Scan.AVAILABLE || files.length == 0) return;
            if (files.length == 1) {
                scan_file (files[0], "image");
                return;
            }
            var list = new Gee.ArrayList<File> ();
            foreach (var f in files) list.add (f);
            scan_batch (list);
        }

        public void activate_window_action (string name) {
            var a = lookup_action (name);
            if (a != null && a.enabled) a.activate (null);
        }

        public void create_from_text (string text) {
            edit_as_new (text);
        }

        private void scan_batch (Gee.ArrayList<File> files) {
            batch_cancel = new Cancellable ();
            busy_cancel.visible = true;
            show_page ("busy");
            run_batch.begin (files, batch_cancel);
        }

        private async void run_batch (Gee.ArrayList<File> files, Cancellable cancel) {
            var result = new Gee.ArrayList<ScanGroup> ();
            int n = 0;
            foreach (var file in files) {
                if (cancel.is_cancelled ()) break;
                n++;
                busy_page.title = _("Scanning Picture %d of %d").printf (n, files.size);
                busy_page.description = file.get_basename () ?? "";
                var g = new ScanGroup (file_label (file));
                try {
                    foreach (var d in yield scan_file_async (file)) g.codes.add (d);
                } catch (Error e) {
                    g.error = read_error (e);
                }
                result.add (g);
            }
            busy_cancel.visible = false;
            if (batch_cancel == cancel) batch_cancel = null;
            if (stack.visible_child_name != "busy") return;
            last_source = "batch";
            remember_groups (result);
            if (result.size == 0) {
                show_page ("scan");
                return;
            }
            show_codes (result, cancel.is_cancelled () ? _("Stopped after %d of %d pictures").printf (result.size, files.size) : null);
        }

        private void remember_groups (Gee.List<ScanGroup> list) {
            history.begin_batch ();
            for (int gi = list.size - 1; gi >= 0; gi--) {
                var g = list[gi];
                for (int i = g.codes.size - 1; i >= 0; i--) history.add (Origin.SCANNED, g.codes[i].text, last_source == "batch" ? "image" : last_source, -1, g.codes[i].format.id ());
            }
            history.end_batch ();
        }

        private void scan_texture (Gdk.Texture texture, string source) {
            show_page ("busy");
            busy_page.description = "";
            busy_cancel.visible = false;
            var found = Scan.decode_texture (texture);
            show_decoded (found, source, source == "clipboard" ? _("Clipboard") : _("Picture"));
        }

        private void show_decoded (Decoded[] found, string source, string label) {
            last_source = source;
            if (found.length == 0) {
                nocode_page.title = _("No Code Found");
                nocode_page.description = source == "camera" ? "" : _("There is no code in this picture, or it is too small or blurry to read. Try a sharper picture, or crop it around the code.");
                show_page ("nocode");
                return;
            }
            var g = new ScanGroup (label);
            foreach (var d in found) g.codes.add (d);
            var list = new Gee.ArrayList<ScanGroup> ();
            list.add (g);
            remember_groups (list);
            if (found.length == 1) {
                groups = list;
                show_content (Content.parse_code (found[0].text, found[0].format));
                return;
            }
            show_codes (list, null);
        }

        private void show_codes (Gee.ArrayList<ScanGroup> list, string? note) {
            groups = list;
            Widget? child;
            while ((child = codes_groups.get_first_child ()) != null) codes_groups.remove (child);
            int total = Csv.count (list);
            if (list.size == 1) {
                codes_title.label = ngettext ("%d Code Found", "%d Codes Found", total).printf (total);
                codes_subtitle.label = _("In %s").printf (list[0].source);
            } else {
                codes_title.label = ngettext ("%d Code in %d Pictures", "%d Codes in %d Pictures", total).printf (total, list.size);
                int empty = 0;
                foreach (var g in list) if (g.codes.size == 0) empty++;
                string sub = empty > 0 ? ngettext ("%d picture has no code", "%d pictures have no code", empty).printf (empty) : _("Every picture has at least one code");
                codes_subtitle.label = note != null ? "%s. %s".printf (note, sub) : sub;
            }
            foreach (var g in list) {
                var group = new PreferencesGroup (list.size > 1 ? g.source : null);
                if (g.codes.size == 0) {
                    var row = new ActionRow (g.error != null ? _("Could not read this picture") : _("No code found"), g.error, "image-missing-symbolic");
                    row.activatable = false;
                    row.add_css_class ("dim-label");
                    group.add_row (row);
                }
                foreach (var d in g.codes) {
                    var c = Content.parse_code (d.text, d.format);
                    var row = nav_row (c.kind.icon_name (), c.title != "" ? c.title : c.kind.label (), c.summary (), () => {
                        show_content (c);
                        result_back.visible = true;
                    });
                    var copy = new Button.from_icon_name ("edit-copy-symbolic");
                    copy.add_css_class ("flat");
                    copy.valign = Align.CENTER;
                    copy.tooltip_text = _("Copy");
                    copy.clicked.connect (() => copy_text (d.text, _("Copied")));
                    row.add_suffix (copy);
                    group.add_row (row);
                }
                codes_groups.append (group);
            }
            show_page ("codes");
        }

        private void show_content (Content c) {
            current = c;
            result_back.visible = false;
            result_kind.label = c.summary ();
            result_icon.icon_name = c.kind.icon_name ();
            result_title.label = c.title != "" ? c.title : c.kind.label ();
            result_raw.label = c.raw;
            result_code.visible = true;
            try {
                if (c.format.is_linear ()) result_code.barcode = Barcode.encode (c.format, c.raw);
                else result_code.code = QrCode.encode_text (c.raw, QrEcLevel.MEDIUM);
            } catch (Error e) {
                result_code.visible = false;
            }

            Widget? child;
            while ((child = result_actions.get_first_child ()) != null) result_actions.remove (child);
            fill_actions (c);

            result_details.clear ();
            foreach (var f in c.fields) result_details.add_row (field_row (f));
            result_details.visible = c.fields.size > 0;
            show_page ("result");
        }

        private Button pill (string label, bool suggested, owned Callback cb) {
            var b = new Button.with_label (label);
            b.add_css_class ("pill");
            if (suggested) b.add_css_class ("suggested-action");
            b.clicked.connect (() => cb ());
            result_actions.append (b);
            return b;
        }

        private void fill_actions (Content c) {
            switch (c.kind) {
                case ContentKind.URL:
                    pill (_("Open"), true, () => launch_uri (c.url, null));
                    break;
                case ContentKind.WIFI:
                    Button? connect_button = null;
                    connect_button = pill (_("Connect"), true, () => join_wifi (c.wifi, connect_button));
                    break;
                case ContentKind.CONTACT:
                    pill (_("Add to Contacts"), true, () => open_contact (c));
                    break;
                case ContentKind.GEO:
                    pill (_("Show on Map"), true, () => launch_uri (c.raw, c.url));
                    break;
                case ContentKind.EMAIL:
                    pill (_("Write Email"), true, () => launch_uri (c.url, null));
                    break;
                case ContentKind.PHONE:
                    pill (_("Call"), true, () => launch_uri (c.url, null));
                    break;
                case ContentKind.SMS:
                    pill (_("Send Message"), true, () => launch_uri (c.url, null));
                    break;
                case ContentKind.OTP:
                    if (new DesktopAppInfo (AUTHENTICATOR_ID) != null) {
                        pill (_("Add to Authenticator"), true, () => add_to_authenticator (c));
                    }
                    break;
                case ContentKind.PRODUCT:
                    string code = c.field ("code") ?? c.raw.strip ();
                    pill (_("Search the Web"), true, () => launch_uri (Payload.product_search (code, search_engine ()), null));
                    if (c.field ("isbn") != null) pill (_("Find the Book"), false, () => launch_uri (Payload.book_lookup (code), null));
                    break;
                default:
                    break;
            }
            pill (_("Copy"), c.kind == ContentKind.TEXT, () => copy_current ());
        }

        private Widget field_row (Field f) {
            var row = new ActionRow (f.label, f.secret ? mask (f.value) : f.value);
            row.activatable = false;
            if (f.secret) {
                bool shown = false;
                var reveal = new Button.from_icon_name ("view-reveal-symbolic");
                reveal.add_css_class ("flat");
                reveal.valign = Align.CENTER;
                reveal.tooltip_text = _("Show");
                reveal.clicked.connect (() => {
                    shown = !shown;
                    row.subtitle = shown ? f.value : mask (f.value);
                    reveal.icon_name = shown ? "view-conceal-symbolic" : "view-reveal-symbolic";
                    reveal.tooltip_text = shown ? _("Hide") : _("Show");
                });
                row.add_suffix (reveal);
            }
            var copy = new Button.from_icon_name ("edit-copy-symbolic");
            copy.add_css_class ("flat");
            copy.valign = Align.CENTER;
            copy.tooltip_text = _("Copy %s").printf (f.label);
            copy.clicked.connect (() => copy_text (f.value, _("%s copied").printf (f.label)));
            row.add_suffix (copy);
            return row;
        }

        private static string mask (string v) {
            return string.nfill (int.min (int.max (v.char_count (), 8), 24), '*');
        }

        private void launch_uri (string? uri, string? fallback) {
            if (uri == null) return;
            var launcher = new UriLauncher (uri);
            launcher.launch.begin (this, null, (o, res) => {
                try {
                    launcher.launch.end (res);
                } catch (Error e) {
                    if (e is IOError.CANCELLED || e is DialogError) return;
                    if (fallback != null && fallback != uri) {
                        launch_uri (fallback, null);
                        return;
                    }
                    show_toast (_("No app can open this link"));
                }
            });
        }

        private void join_wifi (WifiInfo? info, Button? button) {
            if (info == null) return;
            if (button != null) button.sensitive = false;
            Network.connect.begin (info, (o, res) => {
                if (button != null) button.sensitive = true;
                try {
                    Network.connect.end (res);
                    show_toast (_("Connecting to %s").printf (info.ssid));
                } catch (NetworkError e) {
                    show_error (_("Could Not Join the Network"), e.message);
                }
            });
        }

        private void open_contact (Content c) {
            string vcard = c.raw;
            if (!Content.is_vcard (c.raw)) {
                var info = new ContactInfo ();
                info.name = c.field ("name") ?? "";
                info.org = c.field ("org") ?? "";
                info.phone = c.field ("phone") ?? "";
                info.email = c.field ("email") ?? "";
                info.url = c.field ("url") ?? "";
                info.address = c.field ("address") ?? "";
                info.note = c.field ("note") ?? "";
                vcard = Payload.contact (info);
            }
            string dir = Path.build_filename (Environment.get_user_cache_dir (), "singularity", "qrcodes");
            DirUtils.create_with_parents (dir, 0700);
            string path = Path.build_filename (dir, "contact-%s.vcf".printf (new DateTime.now_local ().format ("%Y%m%d-%H%M%S")));
            try {
                FileUtils.set_contents (path, vcard);
            } catch (Error e) {
                show_error (_("Could Not Save the Contact"), e.message);
                return;
            }
            var launcher = new FileLauncher (File.new_for_path (path));
            launcher.launch.begin (this, null, (o, res) => {
                try {
                    launcher.launch.end (res);
                } catch (Error e) {
                    if (!(e is IOError.CANCELLED || e is DialogError)) show_toast (_("No app can open contact cards"));
                }
            });
        }

        private void add_to_authenticator (Content c) {
            get_clipboard ().set_text (c.raw);
            var info = new DesktopAppInfo (AUTHENTICATOR_ID);
            if (info == null) return;
            try {
                info.launch (null, get_display ().get_app_launch_context ());
                show_toast (_("Setup link copied. In Authenticator, choose Add Account and paste it."));
            } catch (Error e) {
                show_error (_("Could Not Open Authenticator"), e.message);
            }
        }

        private string search_engine () {
            string engine = settings != null ? settings.get_string ("search-engine") : "duckduckgo";
            return engine in Payload.SEARCH_ENGINES ? engine : "duckduckgo";
        }

        private void scan_again () {
            if (last_source == "camera") start_camera ();
            else if (last_source == "screenshot") scan_screenshot ();
            else if (last_source == "image") open_image ();
            else if (last_source == "batch") open_batch ();
            else show_page ("scan");
        }

        private void schedule_update () {
            if (create_save_id != 0) Source.remove (create_save_id);
            create_save_id = Timeout.add (120, () => {
                create_save_id = 0;
                update_created ();
                return Source.REMOVE;
            });
        }

        private string build_payload () {
            switch (create_forms.visible_child_name) {
                case "wifi":
                    if (wifi_ssid.text.strip () == "") return "";
                    var info = new WifiInfo ();
                    info.ssid = wifi_ssid.text;
                    int idx = 0;
                    for (int i = 0; i < security_labels.length; i++) if (security_labels[i] == wifi_security.current_value) idx = i;
                    info.security = security_ids[idx];
                    info.password = wifi_password.text;
                    info.hidden = wifi_hidden.active;
                    return Payload.wifi (info);
                case "contact":
                    var c = new ContactInfo ();
                    c.name = contact_name.text;
                    c.org = contact_org.text;
                    c.phone = contact_phone.text;
                    c.email = contact_email.text;
                    c.url = contact_url.text;
                    c.address = contact_address.text;
                    c.note = contact_note.text;
                    return c.is_empty () ? "" : Payload.contact (c);
                case "barcode":
                    return bar_text.text;
                default:
                    return create_text.buffer.text;
            }
        }

        private void update_created () {
            if (create_forms == null) return;
            string payload = build_payload ();
            created_text = payload;
            created_bar = null;
            if (create_forms.visible_child_name == "barcode" && payload.strip () != "") {
                created = null;
                try {
                    created_bar = Barcode.encode (bar_format_value (), payload);
                    created_text = created_bar.text;
                    create_code.barcode = created_bar;
                    create_preview_stack.visible_child_name = "code";
                    create_info.label = created_bar.format.is_product ()
                        ? _("%s %s, %d modules wide").printf (created_bar.format.label (), created_bar.text, created_bar.total_width)
                        : _("%s, %d characters, %d modules wide").printf (created_bar.format.label (), payload.char_count (), created_bar.total_width);
                    create_info.remove_css_class ("error");
                } catch (EncodeError e) {
                    create_code.code = null;
                    create_preview_stack.visible_child_name = "empty";
                    create_info.label = e.message;
                    create_info.add_css_class ("error");
                }
            } else if (payload.strip () == "") {
                created = null;
                create_code.code = null;
                create_preview_stack.visible_child_name = "empty";
                create_info.label = "";
            } else {
                try {
                    created = QrCode.encode_text (payload, ec_level);
                    create_code.code = created;
                    create_preview_stack.visible_child_name = "code";
                    create_info.label = _("Version %d, %d by %d modules, %d bytes").printf (created.version, created.size, created.size, payload.data.length);
                    create_info.remove_css_class ("error");
                } catch (QrEncodeError e) {
                    created = null;
                    create_code.code = null;
                    create_preview_stack.visible_child_name = "empty";
                    create_info.label = _("This is too long for a QR code: %d bytes, the limit at this error correction level is %d.").printf (payload.data.length, QrCode.max_bytes (QrCode.MAX_VERSION, ec_level));
                    create_info.add_css_class ("error");
                }
            }
            sync_actions ();
        }

        private void remember_created () {
            if ((stack.visible_child_name ?? "") == "share") {
                if (shared != null) history.add (Origin.GENERATED, Payload.wifi (shared_info), "create");
                return;
            }
            if (created_bar != null) history.add (Origin.GENERATED, created_bar.text, "create", -1, created_bar.format.id ());
            else if (created_text.strip () != "") history.add (Origin.GENERATED, created_text, "create");
        }

        private string suggested_name (string ext) {
            string base_name = _("QR Code");
            if ((stack.visible_child_name ?? "") == "share" && shared_info != null) {
                string t = shared_info.ssid.replace ("/", " ").strip ();
                if (t != "" && t.char_count () <= 40) base_name = _("Wi-Fi %s").printf (t);
            } else if (created_bar != null) {
                base_name = _("Barcode %s").printf (created_bar.text.replace ("/", " ").strip ());
                if (base_name.char_count () > 48) base_name = _("Barcode");
            } else if (created_text != "") {
                var c = Content.parse (created_text);
                string t = c.title.replace ("/", " ").replace ("…", "").strip ();
                if (t != "" && t.char_count () <= 40) base_name = _("QR Code %s").printf (t);
            }
            return "%s.%s".printf (base_name, ext);
        }

        private QrCode? made_qr () {
            return (stack.visible_child_name ?? "") == "share" ? shared : created;
        }

        private Barcode? made_bar () {
            return (stack.visible_child_name ?? "") == "share" ? null : created_bar;
        }

        private void save_png () {
            var code = made_qr ();
            var bar = made_bar ();
            if (bar != null) {
                save_dialog (_("Save as PNG"), suggested_name ("png"), "png", _("PNG Image"), (path) => {
                    Render.save_barcode_png (bar, int.max (4, Render.barcode_module_for_width (bar, 1024)), path);
                });
                return;
            }
            if (code == null) return;
            save_dialog (_("Save as PNG"), suggested_name ("png"), "png", _("PNG Image"), (path) => {
                Render.save_png (code, int.max (8, Render.module_for_size (code, 1024)), path);
            });
        }

        private void save_svg () {
            var code = made_qr ();
            var bar = made_bar ();
            if (bar != null) {
                save_dialog (_("Save as SVG"), suggested_name ("svg"), "svg", _("SVG Image"), (path) => {
                    FileUtils.set_contents (path, Render.barcode_svg (bar));
                });
                return;
            }
            if (code == null) return;
            save_dialog (_("Save as SVG"), suggested_name ("svg"), "svg", _("SVG Image"), (path) => {
                FileUtils.set_contents (path, Render.svg (code));
            });
        }

        private delegate void Writer (string path) throws Error;

        private void save_dialog (string title, string name, string ext, string filter_name, owned Writer writer, string? folder = Environment.get_user_special_dir (UserDirectory.PICTURES), bool remember = true) {
            var dialog = new FileDialog ();
            dialog.title = title;
            dialog.initial_name = name;
            if (folder != null) dialog.initial_folder = File.new_for_path (folder);
            var filters = new GLib.ListStore (typeof (FileFilter));
            var f = new FileFilter ();
            f.name = filter_name;
            f.add_suffix (ext);
            filters.append (f);
            dialog.filters = filters;
            dialog.save.begin (this, null, (o, res) => {
                File? file = null;
                try {
                    file = dialog.save.end (res);
                } catch (Error e) {
                    return;
                }
                if (file == null || file.get_path () == null) return;
                string path = file.get_path ();
                if (!path.down ().has_suffix ("." + ext)) path += "." + ext;
                try {
                    writer (path);
                    if (remember) remember_created ();
                    show_toast (_("Saved %s").printf (Path.get_basename (path)));
                } catch (Error e) {
                    show_error (_("Could Not Save the Code"), e.message);
                }
            });
        }

        private void copy_current () {
            string name = stack.visible_child_name ?? "";
            var code = made_qr ();
            var bar = made_bar ();
            if (name == "result" && current != null) {
                copy_text (current.raw, _("Copied"));
            } else if (name == "codes") {
                string[] lines = {};
                foreach (var g in groups) foreach (var d in g.codes) lines += d.text;
                if (lines.length > 0) copy_text (string.joinv ("\n", lines), ngettext ("%d code copied", "%d codes copied", lines.length).printf (lines.length));
            } else if ((name == "create" || name == "share") && (code != null || bar != null)) {
                try {
                    var bytes = new Bytes.take (bar != null ? Render.barcode_png_bytes (bar, int.max (3, Render.barcode_module_for_width (bar, 768)))
                        : Render.png_bytes (code, int.max (8, Render.module_for_size (code, 768))));
                    var tex = Gdk.Texture.from_bytes (bytes);
                    get_clipboard ().set_texture (tex);
                    remember_created ();
                    show_toast (_("Image copied"));
                } catch (Error e) {
                    show_error (_("Could Not Copy the Code"), e.message);
                }
            }
        }

        private void copy_text (string text, string message) {
            get_clipboard ().set_text (text);
            show_toast (message);
        }

        private void fill_history () {
            foreach (var r in history_rows) history_group.remove_row (r);
            history_rows.clear ();
            var now = new DateTime.now_local ();
            foreach (var e in history.items) {
                var entry = e;
                var c = Content.parse_code (e.text, CodeFormat.from_id (e.format));
                string when = format_time (e.time, now);
                string what = e.origin == Origin.GENERATED ? _("Created %s").printf (when) : _("Scanned %s").printf (when);
                var row = new ActionRow (c.title != "" ? c.title : c.kind.label (), "%s, %s".printf (c.summary (), what), c.kind.icon_name ());
                row.activatable = true;
                row.activated.connect (() => open_entry (entry));
                var del = new Button.from_icon_name ("user-trash-symbolic");
                del.add_css_class ("flat");
                del.valign = Align.CENTER;
                del.tooltip_text = _("Remove from History");
                del.clicked.connect (() => history.remove (entry.id));
                row.add_suffix (del);
                var right = new GestureClick ();
                right.button = Gdk.BUTTON_SECONDARY;
                right.pressed.connect ((n, x, y) => history_menu (row, entry, x, y));
                row.add_controller (right);
                var press = new GestureLongPress ();
                press.pressed.connect ((x, y) => history_menu (row, entry, x, y));
                row.add_controller (press);
                history_group.add_row (row);
                history_rows.add (row);
            }
            history_stack.visible_child_name = history.items.size > 0 ? "list" : "empty";
            if (history.load_error != null) {
                history_error.label = _("The saved history could not be read: %s").printf (history.load_error);
                history_error.visible = true;
                history_stack.visible_child_name = "list";
            } else {
                history_error.visible = false;
            }
            if (stack != null) sync_actions ();
        }

        private void history_menu (Widget anchor, HistoryEntry entry, double x, double y) {
            var menu = new ContextMenu (anchor);
            menu.add_item (_("Open"), "go-next-symbolic", () => open_entry (entry));
            menu.add_item (_("Copy Text"), "edit-copy-symbolic", () => copy_text (entry.text, _("Copied")));
            menu.add_item (_("Edit as New Code"), "document-edit-symbolic", () => edit_as_new (entry.text, CodeFormat.from_id (entry.format)));
            menu.add_separator ();
            menu.add_item (_("Remove from History"), "user-trash-symbolic", () => history.remove (entry.id), "destructive");
            menu.pointing_to = { (int) x, (int) y, 1, 1 };
            menu.closed.connect (() => Idle.add (() => {
                menu.unparent ();
                return Source.REMOVE;
            }));
            menu.popup ();
        }

        private void open_entry (HistoryEntry entry) {
            last_source = "";
            current_from_history = true;
            show_content (Content.parse_code (entry.text, CodeFormat.from_id (entry.format)));
        }

        private void edit_as_new (string text, CodeFormat format = CodeFormat.QR) {
            var c = Content.parse (text);
            if (format.is_linear ()) {
                create_forms.visible_child_name = "barcode";
                bar_format.current_value = format.label ();
                update_bar_hint ();
                bar_text.text = text;
            } else if (c.kind == ContentKind.WIFI && c.wifi != null) {
                create_forms.visible_child_name = "wifi";
                wifi_ssid.text = c.wifi.ssid;
                int idx = 0;
                for (int i = 0; i < security_ids.length; i++) if (security_ids[i] == c.wifi.security) idx = i;
                wifi_security.current_value = security_labels[idx];
                wifi_password.visible = idx != 3;
                wifi_password.text = c.wifi.password;
                wifi_hidden.active = c.wifi.hidden;
            } else if (c.kind == ContentKind.CONTACT) {
                create_forms.visible_child_name = "contact";
                contact_name.text = c.field ("name") ?? "";
                contact_org.text = c.field ("org") ?? "";
                contact_phone.text = c.field ("phone") ?? "";
                contact_email.text = c.field ("email") ?? "";
                contact_url.text = c.field ("url") ?? "";
                contact_address.text = c.field ("address") ?? "";
                contact_note.text = c.field ("note") ?? "";
            } else {
                create_forms.visible_child_name = "text";
                create_text.buffer.text = text;
            }
            show_page ("create");
        }

        private void open_form (string kind) {
            create_forms.visible_child_name = kind;
            show_page ("create");
            Idle.add (() => {
                switch (kind) {
                    case "wifi": wifi_ssid.grab_focus (); break;
                    case "contact": contact_name.grab_focus (); break;
                    case "barcode": bar_text.grab_focus (); break;
                    default: break;
                }
                return Source.REMOVE;
            });
        }

        private void choose_contact () {
            if ((stack.visible_child_name ?? "") != "create" || create_forms.visible_child_name != "contact") open_form ("contact");
            var cards = ContactBook.read_all ();
            var picker = new ContactPicker ((Gtk.Application) application, cards);
            picker.transient_for = this;
            picker.chosen.connect ((card) => {
                var info = card.to_info ();
                contact_name.text = info.name;
                contact_org.text = info.org;
                contact_phone.text = info.phone;
                contact_email.text = info.email;
                contact_url.text = info.url;
                contact_address.text = info.address;
                contact_note.text = info.note.replace ("\r", "").replace ("\n", " ");
                update_created ();
                show_toast (_("Filled in from %s").printf (card.display_name ()));
            });
            picker.open_dialog ();
        }

        private void share_wifi () {
            show_page ("busy");
            busy_page.title = _("Reading the Wi-Fi Network…");
            busy_page.description = _("You may be asked to allow QR Codes to see the password.");
            busy_cancel.visible = false;
            Network.current_wifi.begin ((o, res) => {
                string? problem;
                WifiInfo info;
                try {
                    info = Network.current_wifi.end (res, out problem);
                } catch (NetworkError e) {
                    show_page ("create-home");
                    show_error (_("Could Not Share the Wi-Fi Network"), e.message);
                    return;
                }
                if (problem != null && info.security != "nopass" && info.password == "") {
                    show_page ("create-home");
                    var dlg = new ConfirmDialog ((Gtk.Application) application, _("Password Not Available"), "dialog-password",
                        _("%s You can type the password yourself to make the code.").printf (problem), _("Type the Password"), ConfirmDialog.ActionStyle.SUGGESTED);
                    dlg.transient_for = this;
                    dlg.modal = true;
                    dlg.response.connect ((r) => {
                        if (r != ConfirmDialog.Response.PRIMARY) return;
                        fill_wifi_form (info);
                        open_form ("wifi");
                        Idle.add (() => {
                            wifi_password.grab_focus ();
                            return Source.REMOVE;
                        });
                    });
                    dlg.present ();
                    return;
                }
                show_shared (info);
            });
        }

        private void fill_wifi_form (WifiInfo info) {
            wifi_ssid.text = info.ssid;
            int idx = 0;
            for (int i = 0; i < security_ids.length; i++) if (security_ids[i] == info.security) idx = i;
            wifi_security.current_value = security_labels[idx];
            wifi_password.visible = idx != 3;
            wifi_password.text = info.password;
            wifi_hidden.active = info.hidden;
        }

        private void show_shared (WifiInfo info) {
            try {
                shared = QrCode.encode_text (Payload.wifi (info), QrEcLevel.MEDIUM);
            } catch (QrEncodeError e) {
                show_page ("create-home");
                show_error (_("Could Not Share the Wi-Fi Network"), e.message);
                return;
            }
            shared_info = info;
            share_code.code = shared;
            share_name.label = info.ssid;
            share_detail.label = info.security == "nopass" ? _("Open network. Scan the code with a phone camera to join.")
                : _("%s. Scan the code with a phone camera to join without typing the password.").printf (info.security_label ());
            share_password.visible = info.security != "nopass";
            share_password.subtitle = mask (info.password);
            show_page ("share");
        }

        private void export_csv () {
            if (groups.size == 0) return;
            var list = groups;
            save_dialog (_("Export as CSV"), _("Scanned Codes.csv"), "csv", _("CSV Spreadsheet"), (path) => {
                FileUtils.set_contents (path, Csv.document (list));
            }, Environment.get_user_special_dir (UserDirectory.DOCUMENTS), false);
        }

        private static string format_time (int64 time, DateTime now) {
            var t = new DateTime.from_unix_local (time);
            if (t.get_year () == now.get_year () && t.get_day_of_year () == now.get_day_of_year ()) return _("today at %s").printf (t.format ("%H:%M"));
            var yesterday = now.add_days (-1);
            if (t.get_year () == yesterday.get_year () && t.get_day_of_year () == yesterday.get_day_of_year ()) return _("yesterday at %s").printf (t.format ("%H:%M"));
            return _("on %s").printf (t.format ("%x"));
        }

        private void confirm_clear () {
            if (history.items.size == 0) return;
            var dlg = new ConfirmDialog ((Gtk.Application) application, _("Clear History?"), "user-trash-symbolic",
                ngettext ("The saved code is removed. This cannot be undone.", "All %d saved codes are removed. This cannot be undone.", history.items.size).printf (history.items.size),
                _("Clear"), ConfirmDialog.ActionStyle.DESTRUCTIVE);
            dlg.transient_for = this;
            dlg.modal = true;
            dlg.response.connect ((r) => {
                if (r == ConfirmDialog.Response.PRIMARY) history.clear ();
            });
            dlg.present ();
        }

        private void show_error (string title, string message) {
            var dlg = new ConfirmDialog.message ((Gtk.Application) application, title, "dialog-error-symbolic", message);
            dlg.transient_for = this;
            dlg.modal = true;
            dlg.present ();
        }

        private void show_toast (string text) {
            if (last_toast != null) last_toast.dismiss ();
            last_toast = new Singularity.Widgets.Toast (text);
            last_toast.timeout = 3;
            add_toast (last_toast);
        }
    }
}
