using Singularity.Apps.QrCodes;

string dir;

string fresh_path (string name) {
    string path = Path.build_filename (dir, name);
    FileUtils.remove (path);
    return path;
}

void main (string[] args) {
    Test.init (ref args);
    try {
        dir = DirUtils.make_tmp ("qrcodes-history-XXXXXX");
    } catch (Error e) {
        error ("%s", e.message);
    }

    Test.add_func ("/history/round-trip", () => {
        string path = fresh_path ("round.json");
        var h = new History (path);
        assert (h.items.size == 0);
        assert (h.load_error == null);
        h.add (Origin.SCANNED, "https://example.org", "camera", 1000);
        h.add (Origin.GENERATED, "WIFI:T:WPA;S:Home;P:x;;", "create", 2000);
        h.add (Origin.SCANNED, "line one\nline \"two\" ☕", "clipboard", 3000);
        var again = new History (path);
        assert (again.load_error == null);
        assert (again.items.size == 3);
        assert (again.items[0].text == "line one\nline \"two\" ☕");
        assert (again.items[0].source == "clipboard");
        assert (again.items[0].time == 3000);
        assert (again.items[1].origin == Origin.GENERATED);
        assert (again.items[1].id == h.items[1].id);
        assert (again.items[2].text == "https://example.org");
        FileUtils.remove (path);
    });

    Test.add_func ("/history/dedupe-and-order", () => {
        string path = fresh_path ("dedupe.json");
        var h = new History (path);
        h.add (Origin.SCANNED, "a", "image", 1);
        h.add (Origin.SCANNED, "b", "image", 2);
        h.add (Origin.SCANNED, "a", "camera", 3);
        assert (h.items.size == 2);
        assert (h.items[0].text == "a");
        assert (h.items[0].source == "camera");
        h.add (Origin.GENERATED, "a", "create", 4);
        assert (h.items.size == 3);
        FileUtils.remove (path);
    });

    Test.add_func ("/history/limit", () => {
        string path = fresh_path ("limit.json");
        var h = new History (path);
        for (int i = 0; i < History.LIMIT + 25; i++) h.add (Origin.SCANNED, "code %d".printf (i), "image", i);
        assert (h.items.size == History.LIMIT);
        assert (h.items[0].text == "code %d".printf (History.LIMIT + 24));
        assert (h.items[History.LIMIT - 1].text == "code 25");
        var again = new History (path);
        assert (again.items.size == History.LIMIT);
        FileUtils.remove (path);
    });

    Test.add_func ("/history/remove-and-clear", () => {
        string path = fresh_path ("remove.json");
        var h = new History (path);
        int changes = 0;
        h.changed.connect (() => changes++);
        var first = h.add (Origin.SCANNED, "one", "image", 1);
        h.add (Origin.SCANNED, "two", "image", 2);
        h.remove (first.id);
        h.remove ("missing");
        assert (h.items.size == 1);
        assert (new History (path).items.size == 1);
        h.clear ();
        assert (h.items.size == 0);
        assert (new History (path).items.size == 0);
        assert (changes == 4);
        FileUtils.remove (path);
    });

    Test.add_func ("/history/damaged", () => {
        string path = fresh_path ("broken.json");
        try {
            FileUtils.set_contents (path, "{ not json");
        } catch (Error e) {
            error ("%s", e.message);
        }
        var h = new History (path);
        assert (h.items.size == 0);
        assert (h.load_error != null);
        try {
            FileUtils.set_contents (path, "{\"a\": 1}");
            assert (new History (path).load_error != null);
            FileUtils.set_contents (path, "[{\"text\": \"ok\"}, 5, {\"origin\": \"generated\"}, {\"text\": \"\"}]");
        } catch (Error e) {
            error ("%s", e.message);
        }
        var partial = new History (path);
        assert (partial.load_error == null);
        assert (partial.items.size == 1);
        assert (partial.items[0].text == "ok");
        assert (partial.items[0].origin == Origin.SCANNED);
        FileUtils.remove (path);
    });

    Test.add_func ("/history/private-file", () => {
        string path = fresh_path ("mode.json");
        var h = new History (path);
        h.add (Origin.SCANNED, "secret", "image", 1);
        Posix.Stat st;
        assert (Posix.stat (path, out st) == 0);
        assert ((st.st_mode & 0077) == 0);
        FileUtils.remove (path);
    });

    Test.add_func ("/history/format", () => {
        string path = fresh_path ("format.json");
        var h = new History (path);
        h.add (Origin.SCANNED, "4006381333931", "camera", 10, "ean13");
        h.add (Origin.SCANNED, "4006381333931", "camera", 11, "code128");
        h.add (Origin.SCANNED, "plain", "camera", 12);
        assert (h.items.size == 3);
        var again = new History (path);
        assert (again.items[0].format == "qr");
        assert (again.items[1].format == "code128");
        assert (again.items[2].format == "ean13");
        again.add (Origin.SCANNED, "4006381333931", "image", 20, "ean13");
        assert (again.items.size == 3 && again.items[0].format == "ean13" && again.items[0].time == 20);
        FileUtils.remove (path);
    });

    Test.add_func ("/history/batch", () => {
        string path = fresh_path ("batch.json");
        var h = new History (path);
        int signals = 0;
        h.changed.connect (() => signals++);
        h.begin_batch ();
        for (int i = 0; i < 250; i++) h.add (Origin.SCANNED, "code %d".printf (i), "image", i);
        assert (signals == 0);
        assert (!FileUtils.test (path, FileTest.EXISTS));
        h.end_batch ();
        assert (signals == 1);
        assert (h.items.size == History.LIMIT);
        var again = new History (path);
        assert (again.items.size == History.LIMIT && again.items[0].text == "code 249");
        h.end_batch ();
        assert (signals == 1);
        FileUtils.remove (path);
    });

    Test.add_func ("/history/migrate-old-location", () => {
        string old_dir = Path.build_filename (dir, "decoder");
        string old_path = Path.build_filename (old_dir, "history.json");
        string new_path = Path.build_filename (dir, "qrcodes", "history.json");
        DirUtils.create_with_parents (old_dir, 0700);
        var h = new History (old_path);
        h.add (Origin.SCANNED, "kept", "image", 7);
        assert (History.migrate (old_path, new_path));
        assert (!FileUtils.test (old_path, FileTest.EXISTS));
        assert (!FileUtils.test (old_dir, FileTest.EXISTS));
        var moved = new History (new_path);
        assert (moved.items.size == 1 && moved.items[0].text == "kept");
        DirUtils.create_with_parents (old_dir, 0700);
        try {
            FileUtils.set_contents (old_path, "[]");
        } catch (Error e) {
            error ("%s", e.message);
        }
        assert (!History.migrate (old_path, new_path));
        assert (new History (new_path).items.size == 1);
        FileUtils.remove (old_path);
        DirUtils.remove (old_dir);
        FileUtils.remove (new_path);
        DirUtils.remove (Path.get_dirname (new_path));
    });

    int result = Test.run ();
    DirUtils.remove (dir);
    Process.exit (result);
}
