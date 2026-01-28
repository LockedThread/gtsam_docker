"""
GTSAM Copyright 2010-2018, Georgia Tech Research Corporation,
Atlanta, Georgia 30332-0415
All Rights Reserved
Authors: Frank Dellaert, et al. (see THANKS for the full author list)
See LICENSE for the license information

Simple robotics example using odometry measurements and bearing-range (laser) measurements.
From borglab/gtsam python/gtsam/examples/PlanarSLAMExample.py (GTSAM 4.2.0).

Run inside container: python3 /examples/PlanarSLAMExample.py
"""
# pylint: disable=invalid-name, E1101

from __future__ import print_function

import sys
import gtsam
import numpy as np
from gtsam.symbol_shorthand import L, X

# Create noise models
PRIOR_NOISE = gtsam.noiseModel.Diagonal.Sigmas(np.array([0.3, 0.3, 0.1]))
ODOMETRY_NOISE = gtsam.noiseModel.Diagonal.Sigmas(np.array([0.2, 0.2, 0.1]))
MEASUREMENT_NOISE = gtsam.noiseModel.Diagonal.Sigmas(np.array([0.1, 0.2]))


def main():
    """Main runner."""
    # Create an empty nonlinear factor graph
    graph = gtsam.NonlinearFactorGraph()

    # Create the keys corresponding to unknown variables in the factor graph
    x1, x2, x3 = X(1), X(2), X(3)
    l1, l2 = L(4), L(5)

    # Add a prior on pose X1 at the origin
    graph.add(
        gtsam.PriorFactorPose2(x1, gtsam.Pose2(0.0, 0.0, 0.0), PRIOR_NOISE)
    )

    # Add odometry factors between X1,X2 and X2,X3
    graph.add(
        gtsam.BetweenFactorPose2(x1, x2, gtsam.Pose2(2.0, 0.0, 0.0), ODOMETRY_NOISE)
    )
    graph.add(
        gtsam.BetweenFactorPose2(x2, x3, gtsam.Pose2(2.0, 0.0, 0.0), ODOMETRY_NOISE)
    )

    # Add Range-Bearing measurements to two different landmarks L1 and L2
    graph.add(
        gtsam.BearingRangeFactor2D(
            x1, l1, gtsam.Rot2.fromDegrees(45), np.sqrt(4.0 + 4.0), MEASUREMENT_NOISE
        )
    )
    graph.add(
        gtsam.BearingRangeFactor2D(x2, l1, gtsam.Rot2.fromDegrees(90), 2.0, MEASUREMENT_NOISE)
    )
    graph.add(
        gtsam.BearingRangeFactor2D(x3, l2, gtsam.Rot2.fromDegrees(90), 2.0, MEASUREMENT_NOISE)
    )

    print("Factor Graph:\n{}".format(graph))

    # Create (deliberately inaccurate) initial estimate
    initial_estimate = gtsam.Values()
    initial_estimate.insert(x1, gtsam.Pose2(-0.25, 0.20, 0.15))
    initial_estimate.insert(x2, gtsam.Pose2(2.30, 0.10, -0.20))
    initial_estimate.insert(x3, gtsam.Pose2(4.10, 0.10, 0.10))
    initial_estimate.insert(l1, gtsam.Point2(1.80, 2.10))
    initial_estimate.insert(l2, gtsam.Point2(4.10, 1.80))

    print("Initial Estimate:\n{}".format(initial_estimate))

    # Optimize using Levenberg-Marquardt
    params = gtsam.LevenbergMarquardtParams()
    optimizer = gtsam.LevenbergMarquardtOptimizer(graph, initial_estimate, params)
    result = optimizer.optimize()
    print("\nFinal Result:\n{}".format(result))

    # Calculate and print marginal covariances
    marginals = gtsam.Marginals(graph, result)
    for (key, label) in [(x1, "X1"), (x2, "X2"), (x3, "X3"), (l1, "L1"), (l2, "L2")]:
        print("{} covariance:\n{}\n".format(label, marginals.marginalCovariance(key)))

    # Validation: expect result size and non-NaN covariances
    assert result.size() == 5, "Expected 5 values in result"
    _ = marginals.marginalCovariance(x1)  # will raise if invalid
    print("VALIDATION OK")
    return 0

if __name__ == "__main__":
    sys.exit(main())
