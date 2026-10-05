/// How lengths are shown to the user. Stored lengths are always metres.
enum Units {
  feet('ft', 0.3048),
  metres('m', 1);

  const Units(this.symbol, this.metresPerUnit);

  final String symbol;
  final double metresPerUnit;

  double fromMetres(double metres) => metres / metresPerUnit;
  double toMetres(double value) => value * metresPerUnit;

  /// The smaller unit for close measurements such as row and plant
  /// spacing: inches with feet, centimetres with metres.
  String get fineSymbol => switch (this) {
    feet => 'in',
    metres => 'cm',
  };
  double get metresPerFineUnit => switch (this) {
    feet => 0.0254,
    metres => 0.01,
  };
  double fineFromMetres(double metres) => metres / metresPerFineUnit;
  double fineToMetres(double value) => value * metresPerFineUnit;

  /// A short, readable length such as "3.28 ft" or "0.125 m".
  String format(double metres) {
    final value = fromMetres(metres);
    final text = value >= 100
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '');
    return '$text $symbol';
  }
}

/// How areas are shown to the user. Stored areas are always square metres.
enum AreaUnits {
  squareFeet('ft²', 0.09290304, 2),
  squareMetres('m²', 1, 2),
  acres('acres', 4046.8564224, 4);

  const AreaUnits(this.symbol, this.squareMetresPerUnit, this.decimals);

  final String symbol;
  final double squareMetresPerUnit;

  /// Garden plots are a small part of an acre, so acres keep more places.
  final int decimals;

  /// Net land area; open boundaries show a dash.
  String format(double? squareMetres) {
    if (squareMetres == null) return '—';
    final value = squareMetres / squareMetresPerUnit;
    final text = value
        .toStringAsFixed(decimals)
        .replaceFirst(RegExp(r'\.?0+$'), '');
    // "1 acre", but "0.5 acres" and "2 acres".
    final unit = this == acres && text == '1' ? 'acre' : symbol;
    return '$text $unit';
  }
}
