String homeGreetingFor(DateTime now, String studentName) {
  final greeting = switch (now.hour) {
    >= 5 && < 12 => 'Доброе утро',
    >= 12 && < 18 => 'Добрый день',
    >= 18 && < 23 => 'Добрый вечер',
    _ => 'Доброй ночи',
  };
  final name = studentName.trim();
  return name.isEmpty ? '$greeting!' : '$greeting, $name';
}

String russianDateLabel(DateTime date) {
  const weekdays = <String>[
    'Понедельник',
    'Вторник',
    'Среда',
    'Четверг',
    'Пятница',
    'Суббота',
    'Воскресенье',
  ];
  const months = <String>[
    'января',
    'февраля',
    'марта',
    'апреля',
    'мая',
    'июня',
    'июля',
    'августа',
    'сентября',
    'октября',
    'ноября',
    'декабря',
  ];
  return '${weekdays[date.weekday - 1]}, ${date.day} ${months[date.month - 1]}';
}
