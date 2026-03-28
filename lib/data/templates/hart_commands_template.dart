/// Seed data for HART command definitions.
///
/// Each command maps to a description and JSON-compatible arrays:
///   req   – field names expected in the request body
///   resp  – field names whose hex values compose the response body
///   write – field names written from the request body
///
/// Special tokens:
///   $IDENTITY_BLOCK → expanded to the standard 12-byte identity block
///   $OK             → status bytes 00 00
///   $ERR:code       → error status byte
///
/// Mirrors the original Python hrt_transmitter_v6.py COMMANDS dict.
const Map<String, Map<String, dynamic>> kHartCommandsSeed = {
  '00': {
    'description': 'Read Unique Identifier',
    'req': <String>[],
    'resp': <String>[
      'error_code',
      r'$IDENTITY_BLOCK',
    ],
    'write': <String>[],
  },
  '01': {
    'description': 'Read Primary Variable',
    'req': <String>[],
    'resp': <String>[
      'process_variable_unit_code',
      'PROCESS_VARIABLE',
    ],
    'write': <String>[],
  },
  '02': {
    'description': 'Read Loop Current And Percent Of Range',
    'req': <String>[],
    'resp': <String>[
      'loop_current',
      'percent_of_range',
    ],
    'write': <String>[],
  },
  '03': {
    'description': 'Read Dynamic Variables And Loop Current',
    'req': <String>[],
    'resp': <String>[
      'loop_current',
      'process_variable_unit_code',
      'PROCESS_VARIABLE',
      'process_variable_unit_code',
      'PROCESS_VARIABLE',
      'process_variable_unit_code',
      'PROCESS_VARIABLE',
      'process_variable_unit_code',
      'PROCESS_VARIABLE',
    ],
    'write': <String>[],
  },
  '04': {
    'description': 'Read Loop Current And Percent Of Range',
    'req': <String>[],
    'resp': <String>[
      'loop_current',
      'percent_of_range',
    ],
    'write': <String>[],
  },
  '06': {
    'description': 'Write Polling Address',
    'req': <String>['polling_address'],
    'resp': <String>['polling_address'],
    'write': <String>['polling_address'],
  },
  '07': {
    'description': 'Read Loop Configuration',
    'req': <String>[],
    'resp': <String>[
      'polling_address',
      'loop_current_mode',
    ],
    'write': <String>[],
  },
  '0B': {
    'description': 'Read Unique Identifier Associated With Tag',
    'req': <String>['tag'],
    'resp': <String>[
      r'$IDENTITY_BLOCK',
    ],
    'write': <String>[],
  },
  '0C': {
    'description': 'Read Message',
    'req': <String>[],
    'resp': <String>['message'],
    'write': <String>[],
  },
  '0D': {
    'description': 'Read Tag, Descriptor, Date',
    'req': <String>[],
    'resp': <String>[
      'tag',
      'descriptor',
      'date',
    ],
    'write': <String>[],
  },
  '0E': {
    'description': 'Read Primary Variable Sensor Information',
    'req': <String>[],
    'resp': <String>[
      'sensor1_serial_number',
      'process_variable_unit_code',
      'pressure_upper_range_limit',
      'pressure_lower_range_limit',
      'pressure_minimum_span',
    ],
    'write': <String>[],
  },
  '0F': {
    'description': 'Read Device Output Information',
    'req': <String>[],
    'resp': <String>[
      'alarm_selection_code',
      'transfer_function_code',
      'process_variable_unit_code',
      'upper_range_value',
      'lower_range_value',
      'pressure_damping_value',
      'write_protect_code',
      'manufacturer_id',
      'analog_output_numbers_code',
    ],
    'write': <String>[],
  },
  '10': {
    'description': 'Read Final Assembly Number',
    'req': <String>[],
    'resp': <String>['final_assembly_number'],
    'write': <String>[],
  },
  '11': {
    'description': 'Write Message',
    'req': <String>['message'],
    'resp': <String>[],
    'write': <String>['message'],
  },
  '12': {
    'description': 'Write Tag, Descriptor, Date',
    'req': <String>['tag', 'descriptor', 'date'],
    'resp': <String>[],
    'write': <String>['tag', 'descriptor', 'date'],
  },
  '13': {
    'description': 'Read Final Assembly Number',
    'req': <String>[],
    'resp': <String>['final_assembly_number'],
    'write': <String>[],
  },
  '15': {
    'description': 'Write Output Information',
    'req': <String>[
      'alarm_selection_code',
      'transfer_function_code',
      'process_variable_unit_code',
      'upper_range_value',
      'lower_range_value',
    ],
    'resp': <String>[
      'alarm_selection_code',
      'transfer_function_code',
      'process_variable_unit_code',
      'upper_range_value',
      'lower_range_value',
      'pressure_damping_value',
      'write_protect_code',
      'manufacturer_id',
      'analog_output_numbers_code',
    ],
    'write': <String>[
      'alarm_selection_code',
      'transfer_function_code',
      'process_variable_unit_code',
      'upper_range_value',
      'lower_range_value',
    ],
  },
};
