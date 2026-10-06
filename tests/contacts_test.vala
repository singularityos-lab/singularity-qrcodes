using Singularity.Apps.QrCodes;

string fixtures;

void main (string[] args) {
    Test.init (ref args);
    fixtures = Path.build_filename (args.length > 1 ? args[1] : "tests/fixtures", "contacts");

    Test.add_func ("/contacts/read-both-stores", () => {
        var cards = ContactBook.read_all (Path.build_filename (fixtures, "local"), Path.build_filename (fixtures, "synced"));
        assert (cards.size == 4);
        assert (cards[0].display_name () == "Ada Lovelace");
        assert (cards[1].display_name () == "Bob Café");
        assert (cards[2].display_name () == "Grace Hopper");
        assert (cards[3].display_name () == "Only Company Inc");
        assert (cards[0].source == "On This Computer");
        assert (cards[1].source == "Online Account");
    });

    Test.add_func ("/contacts/fields", () => {
        var cards = ContactBook.read_dir (Path.build_filename (fixtures, "local"), "local");
        ContactCard? ada = null, grace = null;
        foreach (var c in cards) {
            if (c.uid == "ada-1") ada = c;
            if (c.uid == "urn:uuid:grace") grace = c;
        }
        assert (cards.size == 2);
        assert (ada != null && grace != null);
        assert (ada.org == "Analytical Engines, Ltd");
        assert (ada.phones.size == 2 && ada.phones[0] == "+44 20 7946 0000");
        assert (ada.emails.size == 1 && ada.emails[0] == "ada@example.org");
        assert (ada.addresses[0] == "12 St James, Square, London, SW1Y 4JH, United Kingdom");
        assert (ada.urls[0] == "https://example.org/ada");
        assert (ada.note == "First line\nsecond line with a very long text that the contacts app folds across two lines");
        assert (grace.name == "Grace Hopper");
        assert (grace.emails[0] == "grace@navy.example");
        assert (grace.phones[0] == "+1-555-0100");
    });

    Test.add_func ("/contacts/to-info", () => {
        var cards = ContactBook.parse ("BEGIN:VCARD\nFN:Linus\nTEL:1\nTEL:2\nEMAIL:a@b.c\nEND:VCARD\n", "x");
        assert (cards.size == 1);
        var info = cards[0].to_info ();
        assert (info.name == "Linus");
        assert (info.phone == "1");
        assert (info.email == "a@b.c");
        assert (info.org == "" && info.url == "");
        var c = Content.parse (Payload.contact (info));
        assert (c.kind == ContentKind.CONTACT);
        assert (c.field ("name") == "Linus");
        assert (c.field ("phone") == "1");
    });

    Test.add_func ("/contacts/search", () => {
        var cards = ContactBook.read_all (Path.build_filename (fixtures, "local"), Path.build_filename (fixtures, "synced"));
        int n = 0;
        foreach (var c in cards) if (c.matches ("BAKERY")) n++;
        assert (n == 1);
        n = 0;
        foreach (var c in cards) if (c.matches ("+44 20 7946")) n++;
        assert (n == 1);
        n = 0;
        foreach (var c in cards) if (c.matches ("navy.example")) n++;
        assert (n == 1);
        n = 0;
        foreach (var c in cards) if (c.matches ("")) n++;
        assert (n == 4);
    });

    Test.add_func ("/contacts/missing-and-broken", () => {
        assert (ContactBook.read_all ("/nonexistent/qrcodes/a", "/nonexistent/qrcodes/b").size == 0);
        assert (ContactBook.parse ("BEGIN:VCARD\nFN:Cut off", "x").size == 0);
        assert (ContactBook.parse ("", "x").size == 0);
        assert (ContactBook.parse ("FN:Outside\nBEGIN:VCARD\nFN:Inside\nEND:VCARD", "x").size == 1);
    });

    Test.run ();
}
