"""
Minimal GTSAM sanity check for container validation.
Uses symbol_shorthand, Pose2, and Values (same API as PlanarSLAM/Odometry examples).
Avoids noiseModel.Diagonal.Sigmas(numpy_array), which can segfault when numpy
ABI doesn't match the version GTSAM was built against.

Run: python3 /examples/validate_gtsam.py
"""
from __future__ import print_function

import sys
import gtsam
from gtsam.symbol_shorthand import X

def main():
    # Core types from the official examples, no numpy
    x1 = X(1)
    values = gtsam.Values()
    values.insert(x1, gtsam.Pose2(0.0, 0.0, 0.0))
    assert values.size() == 1
    pose = values.atPose2(x1)
    assert pose.x() == 0.0 and pose.y() == 0.0
    graph = gtsam.NonlinearFactorGraph()
    assert graph.size() == 0
    print("VALIDATION OK")
    return 0

if __name__ == "__main__":
    sys.exit(main())
