/// How lengths are shown to the user. Stored lengths are always metres.
enum Units {
  feet('ft', 0.3048),
  metres('m', 1);

  const Units(this.symbol, this.metresPerUnit);

  final String symbol;
  final double metresPerUnit;

  double fromMetres(double metres) => metres / metresPerUnit;
  double toMetres(double value) => value * metresPerUnit;

  /// Net land area, stored in square metres; open boundaries show a dash.
  String formatArea(double? squareMetres) {
    if (squareMetres == null) return '—';
    final value = squareMetres / (metresPerUnit * metresPerUnit);
    final text = value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
    return '$text $symbol²';
  }

  /// A short, readable length such as "3.28 ft" or "0.125 m".
  String format(double metres) {
    final value = fromMetres(metres);
    final text = value >= 100
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '');
    return '$text $symbol';
  }
}
