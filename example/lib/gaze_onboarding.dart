import 'package:cocoverse_ui/cocoverse_ui.dart';
import 'package:flutter/material.dart';

/// A phone onboarding screen. The two "o"s of "look" are [Gaze] eyes that
/// follow your finger, or the cursor, anywhere on the screen.
class GazeOnboarding extends StatelessWidget {
  /// Creates the screen.
  const GazeOnboarding({super.key});

  static const Color _paper = Color(0xFFEFE6DC);
  static const Color _ink = Color(0xFF17120F);
  static const Color _muted = Color(0xFFA9A39D);
  static const Color _body = Color(0xFF3A332E);
  static const Color _red = Color(0xFFFF1A00);

  /// One eye's box as a share of the headline's font size. Raise it for
  /// bigger eyes.
  static const double _eyeBox = 0.72;

  Widget _eye(double box) {
    return SizedBox(
      width: box,
      height: box,
      child: const Gaze(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _paper,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: LayoutBuilder(
              builder: (context, c) {
                // Lower this number for a bigger headline.
                final fs = ((c.maxWidth - 48) / 5.0).clamp(40.0, 96.0).toDouble();
                final headline = TextStyle(
                  fontSize: fs,
                  fontWeight: FontWeight.w800,
                  height: 1.0,
                  letterSpacing: -fs * 0.045,
                );
                final box = fs * _eyeBox;

                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: c.maxHeight - 36),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [

                                Container(
                                  width: 22,
                                  height: 22,
                                  alignment: Alignment.center,
                                  decoration: const BoxDecoration(
                                    color: _ink,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      color: _red,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                const Text(
                                  'Cocoverse',
                                  style: TextStyle(
                                    color: _ink,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const Spacer(),
                                IconButton(
                                  onPressed: () =>
                                      Navigator.of(context).maybePop(),
                                  icon: const Icon(Icons.close),
                                  color: _ink,
                                ),
                              ],
                            ),
                            const SizedBox(height: 28),
                            Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: _red,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                const Text(
                                  'FLUTTER UI, READY TO PASTE',
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11.5,
                                    letterSpacing: 1.6,
                                    color: Color(0xFF6B645E),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'Cool UI?',
                              maxLines: 1,
                              softWrap: false,
                              style: headline.copyWith(color: _muted),
                            ),
                            Text.rich(
                              TextSpan(
                                style: headline.copyWith(color: _ink),
                                children: [
                                  const TextSpan(text: 'l'),
                                  WidgetSpan(
                                    alignment: PlaceholderAlignment.middle,
                                    child: _eye(box),
                                  ),
                                  WidgetSpan(
                                    alignment: PlaceholderAlignment.middle,
                                    child: _eye(box),
                                  ),
                                const TextSpan(text: 'k here.'),
                                ],
                              ),
                              maxLines: 1,
                              softWrap: false,
                            ),
                            const SizedBox(height: 22),
                            const Text(
                              'Need a place for Flutter assets? Look no '
                              'further. Cocoverse is a marketplace of cool, '
                              'paste-in app UI: templates, components and '
                              'effects, ready to drop into your project. '
                              'No rebuilding from scratch.',
                              style: TextStyle(
                                color: _body,
                                fontSize: 17,
                                height: 1.45,
                              ),
                            ),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 32),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Material(
                                color: _red,
                                borderRadius: BorderRadius.circular(32),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(32),
                                  onTap: () {},
                                  child: const SizedBox(
                                    height: 60,
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          'Browse the library',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 17,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        SizedBox(width: 10),
                                        Icon(
                                          Icons.arrow_forward,
                                          color: Colors.white,
                                          size: 20,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Center(
                                child: TextButton(
                                  onPressed: () {},
                                  child: const Text(
                                    'See how it works',
                                    style: TextStyle(
                                      color: _ink,
                                      fontSize: 16,
                                      decoration: TextDecoration.underline,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}