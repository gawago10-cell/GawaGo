import 'package:flutter_test/flutter_test.dart';
import 'package:gawago_mobile/src/shared/constants/gawago_options.dart';

void main() {
  test('the catalog lists the skilled trades, with Other last', () {
    for (final trade in [
      'Electrical Work',
      'Plumbing',
      'Carpentry',
      'Painting',
      'Aircon Repair',
      'Welding',
    ]) {
      expect(gawagoSkills, contains(trade));
    }
    expect(gawagoSkills.last, gawagoOtherSkill);
  });

  test('Other is never saved; the typed skill takes its place', () {
    expect(
      resolveWorkerSkills(['Electrical Work', 'Other'], '  Solar  Panels '),
      ['Electrical Work', 'Solar Panels'],
    );
    expect(resolveWorkerSkills(['Plumbing'], 'Masonry'), ['Plumbing']);
    expect(resolveWorkerSkills(['Plumbing', 'Other'], 'plumbing'), [
      'Plumbing',
    ]);
  });

  test('a skill choice needs one real skill, at most three', () {
    expect(workerSkillsProblem([], ''), 'Choose at least one skill.');
    expect(workerSkillsProblem(['Other'], ''), contains('Type the name'));
    expect(workerSkillsProblem(['Other'], 'other'), contains('Type the name'));
    expect(workerSkillsProblem(['Other'], 'Masonry'), isNull);
    expect(
      workerSkillsProblem([
        'Plumbing',
        'Carpentry',
        'Welding',
        'Other',
      ], 'Masonry'),
      contains('up to $maxWorkerSkills'),
    );
  });

  test('every Tayabas barangay is offered, including the town centre', () {
    expect(gawagoBarangays, hasLength(66));
    expect(gawagoBarangays, contains('San Diego Zone I'));
    expect(gawagoBarangays, contains('Angustias Zone IV'));
  });
}
