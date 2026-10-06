using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.QrCodes {

    public class ContactPicker : AppDialog {
        private const string CONTACTS_ID = "dev.sinty.contacts.desktop";

        private Gee.ArrayList<ContactCard> cards;
        private Singularity.Widgets.SearchEntry search;
        private PreferencesGroup group;
        private Stack stack;
        private Stack results;
        private StatusPage no_match;

        public signal void chosen (ContactCard card);

        public ContactPicker (Gtk.Application app, Gee.ArrayList<ContactCard> cards) {
            base (app, true);
            this.cards = cards;
            set_title (_("Choose a Contact"));
            set_default_size (440, 560);

            stack = new Stack ();
            stack.vexpand = true;

            var empty = new StatusPage ();
            empty.icon_name = "x-office-addressbook";
            empty.title = _("No Contacts");
            empty.description = _("People you add in Contacts appear here.");
            if (new DesktopAppInfo (CONTACTS_ID) != null) {
                var open = new Button.with_label (_("Open Contacts"));
                open.add_css_class ("pill");
                open.add_css_class ("suggested-action");
                open.halign = Align.CENTER;
                open.clicked.connect (open_contacts);
                empty.child = open;
            }
            stack.add_named (empty, "empty");

            var box = new Box (Orientation.VERTICAL, 12);
            box.margin_start = 18;
            box.margin_end = 18;
            box.margin_top = 6;
            box.margin_bottom = 18;
            search = new Singularity.Widgets.SearchEntry ();
            search.placeholder_text = _("Search by name, email or phone");
            search.search_changed.connect (fill);
            search.entry.activate.connect (() => {
                foreach (var c in cards) {
                    if (c.matches (search.text)) {
                        pick (c);
                        return;
                    }
                }
            });
            box.append (search);
            results = new Stack ();
            results.vexpand = true;
            group = new PreferencesGroup ();
            var scroll = new ScrolledWindow ();
            scroll.hscrollbar_policy = PolicyType.NEVER;
            scroll.vexpand = true;
            scroll.child = group;
            results.add_named (scroll, "list");
            no_match = new StatusPage ();
            no_match.icon_name = "system-search";
            no_match.title = _("No Matching Contacts");
            var clear = new Button.with_label (_("Clear Search"));
            clear.add_css_class ("pill");
            clear.add_css_class ("suggested-action");
            clear.halign = Align.CENTER;
            clear.clicked.connect (() => search.text = "");
            no_match.child = clear;
            results.add_named (no_match, "none");
            box.append (results);
            stack.add_named (box, "list");
            content_box.append (stack);

            if (cards.size == 0) {
                stack.visible_child_name = "empty";
            } else {
                stack.visible_child_name = "list";
                fill ();
            }
        }

        public override void open_dialog () {
            base.open_dialog ();
            if (cards.size > 0) search.grab_focus ();
        }

        private void fill () {
            group.clear ();
            int shown = 0;
            foreach (var card in cards) {
                if (!card.matches (search.text)) continue;
                var c = card;
                string detail = c.detail ();
                var row = new ActionRow (c.display_name (), detail != "" ? "%s, %s".printf (detail, c.source) : c.source, "avatar-default-symbolic");
                row.activatable = true;
                row.activated.connect (() => pick (c));
                group.add_row (row);
                shown++;
            }
            results.visible_child_name = shown > 0 ? "list" : "none";
        }

        private void pick (ContactCard card) {
            chosen (card);
            close_dialog ();
        }

        private void open_contacts () {
            var info = new DesktopAppInfo (CONTACTS_ID);
            if (info == null) return;
            try {
                info.launch (null, get_display ().get_app_launch_context ());
            } catch (Error e) {
                warning ("qrcodes: %s", e.message);
            }
            close_dialog ();
        }
    }
}
