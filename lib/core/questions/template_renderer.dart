/// Fills a question template's placeholders (architecture audit QG-2).
///
/// [objectTypeLabel] is the label of the object's node type, e.g. "region"
/// in "In which {object.type_label} is {subject.name} located?".
String renderPrompt(
  String template, {
  required String subjectName,
  required String objectName,
  required String objectTypeLabel,
}) => template
    .replaceAll('{subject.name}', subjectName)
    .replaceAll('{object.name}', objectName)
    .replaceAll('{object.type_label}', objectTypeLabel);
