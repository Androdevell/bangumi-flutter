String collectionLabel({required int subjectType, required int status}) {
  final verb = switch (subjectType) {
    1 => '读',
    3 => '听',
    4 => '玩',
    _ => '看',
  };
  return switch (status) {
    1 => '想$verb',
    2 => '$verb过',
    3 => '在$verb',
    4 => '搁置',
    5 => '抛弃',
    _ => '',
  };
}
