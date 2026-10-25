
/// Returns [0, 1, 2, ... count - 1], ready to be sorted by depth.
List<int> identityOrder(int count) => List<int>.generate(count, (i) => i);

/// Sorts [order] in place so the farthest items come first.
///
/// [depths] is indexed by item. A larger depth means farther from the camera,
/// so drawing in this order puts near items on top of far ones.
void sortBackToFront(List<int> order, List<double> depths) {
  order.sort((a, b) => depths[b].compareTo(depths[a]));
}