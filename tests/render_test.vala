using Singularity;
using Singularity.Apps.QrCodes;

void main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/render/svg", () => {
        try {
            var qr = QrCode.encode_text ("HELLO WORLD", QrEcLevel.LOW, 4);
            string svg = Render.svg (qr);
            assert (svg.contains ("viewBox=\"0 0 29 29\""));
            assert (svg.has_suffix ("</svg>\n"));
            int dark = 0;
            for (int y = 0; y < qr.size; y++) for (int x = 0; x < qr.size; x++) if (qr.get_module (x, y)) dark++;
            int drawn = 0;
            MatchInfo info;
            var re = new Regex ("h([0-9]+)v1");
            re.match (svg, 0, out info);
            while (info.matches ()) {
                drawn += int.parse (info.fetch (1));
                info.next ();
            }
            assert (drawn == dark);
        } catch (Error e) {
            error ("%s", e.message);
        }
    });

    Test.run ();
}
