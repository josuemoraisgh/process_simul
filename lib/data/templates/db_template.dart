/// Default data for HART and Modbus tables, mirroring the Python template.
///
/// Each HART column entry: (byteSize, typeStr, [device0val, device1val, ...])
/// Device order: FV100CA, FIT100CA, FV100AR, FIT100AR, TIT100, FIT100V,
///               PIT100V, LIT100, PIT100A, FV100A, FIT100A
library;

const List<String> kHartDevices = [
  'FV100CA', 'FIT100CA', 'FV100AR', 'FIT100AR', 'TIT100',
  'FIT100V', 'PIT100V',  'LIT100',  'PIT100A',  'FV100A',  'FIT100A',
];

/// Columns shown in the main HART table view (subset of all columns).
const List<String> kHartVisibleCols = [
  'error_code', 'device_status', 'polling_address',
  'tag', 'message', 'descriptor', 'date',
  'PROCESS_VARIABLE', 'percent_of_range', 'loop_current',
  'upper_range_value', 'lower_range_value', 'process_variable_unit_code',
];

/// Tuple: (byteSize, typeStr, [v0, v1, ..., v10])
typedef ColSpec = (int, String, List<String>);

/// Full HART column definitions with default hex values per device.
final Map<String, ColSpec> kHartTemplate = {
  'frame_type':          (1, 'UNSIGNED', List.filled(11, '06')),
  'address_type':        (1, 'UNSIGNED', List.filled(11, '80')),
  'error_code':          (2, 'ENUM00',   List.filled(11, '0000')),
  'response_code':       (1, 'ENUM27',   List.filled(11, '00')),
  'device_status':       (1, 'BIT_ENUM02', List.filled(11, '40')),
  'comm_status':         (1, 'BIT_ENUM03', List.filled(11, '00')),
  'master_address':      (1, 'BIT_ENUM01', List.filled(11, 'BE')),
  'burst_mode':          (1, 'BIT_ENUM01', List.filled(11, '00')),
  'manufacturer_id':     (1, 'ENUM08',   List.filled(11, '3E')),
  'device_type':         (1, 'ENUM01',   const ['03','01','03','01','02','0A','0A','0A','0A','07','0A']),
  'request_preambles':   (1, 'UNSIGNED', List.filled(11, '05')),
  'hart_revision':       (1, 'UNSIGNED', List.filled(11, '05')),
  'universal_revision':  (1, 'UNSIGNED', List.filled(11, '05')),
  'transmitter_revision':(1, 'UNSIGNED', List.filled(11, '62')),
  'software_revision':   (1, 'UNSIGNED', List.filled(11, '03')),
  'hardware_revision':   (1, 'UNSIGNED', List.filled(11, '00')),
  'device_flags':        (1, 'BIT_ENUM04', List.filled(11, '06')),
  'device_id':           (3, 'UNSIGNED', List.filled(11, '029EB1')),
  'polling_address':     (1, 'UNSIGNED', const ['01','02','03','04','05','06','07','08','09','0A','0B']),
  'tag':                 (6, 'PACKED_ASCII', const [
    '0065B1C300C1', '189531C300C1', '0065B1C30052', '189531C30052',
    '014254C70C20', '006254C70C16', '010254C70C16', '00C254C70C20',
    '010254C70C01', '0065B1C30060', '010254C70C16',
  ]),
  'message':             (32, 'PACKED_ASCII', const [
    '40F4C90C93CE0443D281604C5953018041600C1820820820820820820820820820820820820',
    '34510910F4A010581605A04F803060820820820820820820820820820820820820820820820',
    '40F4C90C93CE0443D281604C595301804160052820820820820820820820820820820820820',
    '34510910F4A010581605A04F8014A0820820820820820820820820820820820820820820820',
    '34510910F4A010581414D405481515481820820820820820820820820820820820820820820',
    '34510910F4A010581605A04F8160503D2820820820820820820820820820820820820820820',
    '34510910F4A01058104854D304F8160503D2820820820820820820820820820820820820820',
    '34510910F4A010580E25614C8043E05150953013E0820820820820820820820820820820820',
    '34510910F4A01058104854D304F8014A0820820820820820820820820820820820820820820',
    '34510910F4A010581605A04F8014A0820820820820820820820820820820820820820820820',
    '34510910F4A01058104854D304F80416058140F4A0820820820820820820820820820820820',
  ]),
  'descriptor':          (12, 'PACKED_ASCII', List.filled(11, '505350152054552060820820')),
  'date':                (3, 'DATE', List.filled(11, '1D097D')),
  'PROCESS_VARIABLE':    (4, 'FLOAT', const [
    '@HART.FV100CA.percent_of_range * (HART.FV100CA.upper_range_value - HART.FV100CA.lower_range_value) + HART.FV100CA.lower_range_value',
    '@HART.FIT100CA.percent_of_range * (HART.FIT100CA.upper_range_value - HART.FIT100CA.lower_range_value) + HART.FIT100CA.lower_range_value',
    '@HART.FV100AR.percent_of_range * (HART.FV100AR.upper_range_value - HART.FV100AR.lower_range_value) + HART.FV100AR.lower_range_value',
    '@HART.FIT100AR.percent_of_range * (HART.FIT100AR.upper_range_value - HART.FIT100AR.lower_range_value) + HART.FIT100AR.lower_range_value',
    '@HART.TIT100.percent_of_range * (HART.TIT100.upper_range_value - HART.TIT100.lower_range_value) + HART.TIT100.lower_range_value',
    '@HART.FIT100V.percent_of_range * (HART.FIT100V.upper_range_value - HART.FIT100V.lower_range_value) + HART.FIT100V.lower_range_value',
    '@HART.PIT100V.percent_of_range * (HART.PIT100V.upper_range_value - HART.PIT100V.lower_range_value) + HART.PIT100V.lower_range_value',
    '@HART.LIT100.percent_of_range * (HART.LIT100.upper_range_value - HART.LIT100.lower_range_value) + HART.LIT100.lower_range_value',
    '@HART.PIT100A.percent_of_range * (HART.PIT100A.upper_range_value - HART.PIT100A.lower_range_value) + HART.PIT100A.lower_range_value',
    '@HART.FV100A.percent_of_range * (HART.FV100A.upper_range_value - HART.FV100A.lower_range_value) + HART.FV100A.lower_range_value',
    '@HART.FIT100A.percent_of_range * (HART.FIT100A.upper_range_value - HART.FIT100A.lower_range_value) + HART.FIT100A.lower_range_value',
  ]),
  'percent_of_range':    (4, 'FLOAT', List.filled(11, '00000000')),
  'loop_current':        (4, 'FLOAT', List.filled(11, '@4 + 16 * HART.FV100CA.percent_of_range')),
  'process_variable_unit_code': (1, 'UNSIGNED', const ['27','F0','27','F0','35','F0','C0','27','C0','27','C0']),
  'upper_range_value':   (4, 'FLOAT', const [
    '42C80000', // 100 %
    '44FA0000', // 2000 L/h → but use 100 for normalization
    '42C80000',
    '44FA0000',
    '43160000', // 150 °C
    '44FA0000',
    '41800000', // 16.0 bar
    '42C80000', // 100 %
    '41800000', // 16.0 bar
    '42C80000',
    '44FA0000',
  ]),
  'lower_range_value':   (4, 'FLOAT', List.filled(11, '00000000')),
  'sensor1_serial_number': (3, 'UNSIGNED', List.filled(11, '000001')),
  'pressure_upper_range_limit': (4, 'FLOAT', List.filled(11, '42C80000')),
  'pressure_lower_range_limit': (4, 'FLOAT', List.filled(11, '00000000')),
  'pressure_minimum_span': (4, 'FLOAT', List.filled(11, '00000000')),
  'pressure_damping_value': (4, 'FLOAT', List.filled(11, '3F800000')),
  'alarm_selection_code': (1, 'UNSIGNED', List.filled(11, '00')),
  'transfer_function_code': (1, 'UNSIGNED', List.filled(11, '01')),
  'write_protect_code':   (1, 'UNSIGNED', List.filled(11, '00')),
  'analog_output_numbers_code': (1, 'UNSIGNED', List.filled(11, '00')),
  'final_assembly_number': (3, 'UNSIGNED', List.filled(11, '000001')),
  'loop_current_mode':    (1, 'UNSIGNED', List.filled(11, '00')),
};

/// Modbus variable definitions.
/// Format: name → (byteSize, typeStr, mbPoint, address, formula)
const Map<String, (int, String, String, String, String)> kModbusTemplate = {
  'FIT100CA': (4, 'UNSIGNED', 'ir', '01', '@int(65535*HART.FIT100CA.percent_of_range)'),
  'FIT100AR': (4, 'UNSIGNED', 'ir', '02', '@int(65535*HART.FIT100AR.percent_of_range)'),
  'TIT100'  : (4, 'UNSIGNED', 'ir', '03', '@int(65535*HART.TIT100.percent_of_range)'),
  'PIT100V' : (4, 'UNSIGNED', 'ir', '05', '@int(65535*HART.PIT100V.percent_of_range)'),
  'LIT100'  : (4, 'UNSIGNED', 'ir', '06', '@int(65535*HART.LIT100.percent_of_range)'),
  'FIT100A' : (4, 'UNSIGNED', 'ir', '08', '@int(65535*HART.FIT100A.percent_of_range)'),
  'FV100CA' : (4, 'UNSIGNED', 'hr', '01', '3F000000'),
  'FV100AR' : (4, 'UNSIGNED', 'hr', '02', '3F000000'),
  'FIT100V' : (4, 'UNSIGNED', 'hr', '03', '3F000000'),
  'PIT100A' : (4, 'UNSIGNED', 'hr', '04', '3F000000'),
  'FV100A'  : (4, 'UNSIGNED', 'hr', '05', '3F000000'),
};
