namespace Singularity.Apps.QrCodes {

    public enum CodeFormat {
        QR,
        EAN13,
        EAN8,
        UPCA,
        CODE128;

        public string id () {
            switch (this) {
                case EAN13: return "ean13";
                case EAN8: return "ean8";
                case UPCA: return "upca";
                case CODE128: return "code128";
                default: return "qr";
            }
        }

        public string label () {
            switch (this) {
                case EAN13: return _("EAN-13");
                case EAN8: return _("EAN-8");
                case UPCA: return _("UPC-A");
                case CODE128: return _("Code 128");
                default: return _("QR Code");
            }
        }

        public bool is_product () {
            return this == EAN13 || this == EAN8 || this == UPCA;
        }

        public bool is_linear () {
            return this != QR;
        }

        public int digits () {
            switch (this) {
                case EAN13: return 13;
                case EAN8: return 8;
                case UPCA: return 12;
                default: return 0;
            }
        }

        public static CodeFormat from_id (string? id) {
            switch (id) {
                case "ean13": return EAN13;
                case "ean8": return EAN8;
                case "upca": return UPCA;
                case "code128": return CODE128;
                default: return QR;
            }
        }

        public static CodeFormat[] barcodes () {
            return { EAN13, EAN8, UPCA, CODE128 };
        }
    }

    public class Decoded : Object {
        public CodeFormat format { get; construct; }
        public string text { get; construct; }

        public Decoded (CodeFormat format, string text) {
            Object (format: format, text: text);
        }
    }

    namespace Gtin {
        public bool all_digits (string s) {
            if (s == "") return false;
            for (int i = 0; i < s.length; i++) if (!s[i].isdigit ()) return false;
            return true;
        }

        public int check_digit (string payload) {
            int sum = 0;
            int weight = 3;
            for (int i = payload.length - 1; i >= 0; i--) {
                sum += (payload[i] - '0') * weight;
                weight = weight == 3 ? 1 : 3;
            }
            return (10 - sum % 10) % 10;
        }

        public bool valid (string code) {
            if (code.length < 2 || !all_digits (code)) return false;
            return check_digit (code.substring (0, code.length - 1)) == code[code.length - 1] - '0';
        }

        public bool is_isbn (string code) {
            return code.length == 13 && (code.has_prefix ("978") || code.has_prefix ("979"));
        }
    }
}
