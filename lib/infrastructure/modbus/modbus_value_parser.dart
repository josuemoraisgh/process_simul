/// Parses the literal (non-`@expression`) form of a Modbus table "formula"
/// cell into a numeric value.
///
/// Literal defaults follow the same raw-hex convention used everywhere else
/// in the app for [ReactVar.rawValue] (e.g. "3F000000", "0064"), so hex is
/// tried first; plain decimal is accepted as a fallback for values that
/// aren't valid hex.
class ModbusValueParser {
  ModbusValueParser._();

  static double parseLiteral(String formula) {
    final hexVal = int.tryParse(formula, radix: 16);
    if (hexVal != null) return hexVal.toDouble();
    return double.tryParse(formula) ?? 0;
  }
}
