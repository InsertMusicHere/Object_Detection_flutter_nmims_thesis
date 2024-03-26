// import 'package:flutter/widgets.dart';
//
// /// Row for one Stats field
// class StatsWidget extends StatelessWidget {
//   final String left;
//   final String right;
//
//   const StatsWidget(this.left, this.right, {super.key});
//
//   @override
//   Widget build(BuildContext context) => Padding(
//     padding: const EdgeInsets.only(bottom: 8.0),
//     child: Row(
//       mainAxisAlignment: MainAxisAlignment.spaceBetween,
//       children: [Text(left), Text(right)],
//     ),
//   );
// }

import 'package:flutter/widgets.dart';

/// Row for one Stats field
class StatsWidget extends StatelessWidget {
  final String left;
  final String right;

  const StatsWidget(this.left, this.right, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8.0),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          flex: 1,
          child: Text(
            left,
            overflow: TextOverflow.visible, // TextOverflow.visible allows text to overflow
          ),
        ),
        Flexible(
          flex: 1,
          child: Text(
            right,
            overflow: TextOverflow.visible,
          ),
        ),
      ],
    ),
  );

}


// Saumitra -
// Milestone - 19th Jan 24
//
// 1. Define zone/quarter in which the object is present
// 2. Measure distance between non stationary objects.
//
// Long term - Voice module integration