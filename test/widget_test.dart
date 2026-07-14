import 'package:flutter_test/flutter_test.dart';
import 'package:process_simul/domain/entities/react_var.dart';
import 'package:process_simul/domain/enums/db_model.dart';

void main() {
  test('ReactVar classifies persisted literal, expression and TF values', () {
    final cell = ReactVar(
      tableName: 'HART',
      rowName: 'DEV',
      colName: 'PV',
      byteSize: 4,
      typeStr: 'FLOAT',
      rawValue: '3F800000',
    );

    expect(cell.model, DbModel.value);
    expect(cell.evaluatedHex, '3F800000');

    cell.setRawValue('@HART.DEV.INPUT * 2');
    expect(cell.model, DbModel.func);
    expect(cell.funcBody, 'HART.DEV.INPUT * 2');

    cell.setRawValue(r'$[1],[1,1],0,@HART.DEV.INPUT');
    expect(cell.model, DbModel.tFunc);
    expect(cell.tFuncBody, '[1],[1,1],0,@HART.DEV.INPUT');
  });
}
