/// State model for the aquatubular boiler digital twin.
/// Each field maps to a SCADA variable for external binding.
class BoilerState {
  /// Water level 0.0–1.0 inside the steam drum.
  final double waterLevel;

  /// Flame on/off.
  final bool flameOn;

  /// Flame intensity 0.0–1.0 (also controls colour shift orange→blue).
  final double flameIntensity;

  /// Fan speeds 0.0–1.0 (controls rotation speed).
  final double forcedDraftFanSpeed;
  final double inducedDraftFanSpeed;

  /// Damper openings 0.0–1.0.
  final double airDamperOpen;
  final double flueGasDamperOpen;

  /// Fuel valve opening 0.0–1.0.
  final double fuelValveOpen;

  /// Optional: highlighted component name for SCADA selection.
  final String? highlightedComponent;

  /// Wave animation phase (driven by AnimationController).
  final double wavePhase;

  /// Fan animation phase (driven by AnimationController).
  final double fanPhase;

  const BoilerState({
    this.waterLevel = 0.65,
    this.flameOn = true,
    this.flameIntensity = 0.7,
    this.forcedDraftFanSpeed = 0.5,
    this.inducedDraftFanSpeed = 0.5,
    this.airDamperOpen = 0.6,
    this.flueGasDamperOpen = 0.6,
    this.fuelValveOpen = 0.5,
    this.highlightedComponent,
    this.wavePhase = 0.0,
    this.fanPhase = 0.0,
  });

  BoilerState copyWith({
    double? waterLevel,
    bool? flameOn,
    double? flameIntensity,
    double? forcedDraftFanSpeed,
    double? inducedDraftFanSpeed,
    double? airDamperOpen,
    double? flueGasDamperOpen,
    double? fuelValveOpen,
    String? highlightedComponent,
    double? wavePhase,
    double? fanPhase,
  }) {
    return BoilerState(
      waterLevel: waterLevel ?? this.waterLevel,
      flameOn: flameOn ?? this.flameOn,
      flameIntensity: flameIntensity ?? this.flameIntensity,
      forcedDraftFanSpeed: forcedDraftFanSpeed ?? this.forcedDraftFanSpeed,
      inducedDraftFanSpeed: inducedDraftFanSpeed ?? this.inducedDraftFanSpeed,
      airDamperOpen: airDamperOpen ?? this.airDamperOpen,
      flueGasDamperOpen: flueGasDamperOpen ?? this.flueGasDamperOpen,
      fuelValveOpen: fuelValveOpen ?? this.fuelValveOpen,
      highlightedComponent: highlightedComponent ?? this.highlightedComponent,
      wavePhase: wavePhase ?? this.wavePhase,
      fanPhase: fanPhase ?? this.fanPhase,
    );
  }
}
