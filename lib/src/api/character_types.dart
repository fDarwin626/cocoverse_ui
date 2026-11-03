/// How a character feels, shown through its eyes.
enum CharacterMood {
  /// Eyes open, blinking now and then.
  neutral,

  /// Eyes squinted or curved, as in a smile.
  happy,

  /// Eyes shut and held shut, as when a password is being typed.
  closed,
}

/// What a character looks at when nothing from your code is steering it.
enum PointerFollow {
  /// It ignores the pointer.
  off,

  /// It looks at the pointer only while the pointer is over the widget.
  widget,

  /// It looks at the last touch or mouse position anywhere on the screen.
  screen,
}
