"""
Validate that the installed GTSAM Python bindings and NumPy agree on the array ABI.

This intentionally exercises a small NumPy-backed GTSAM call that has exposed
mismatched NumPy/GTSAM builds in the past.
"""
import sys

import numpy as np
import gtsam


def main() -> int:
    sigmas = np.array([0.3, 0.3, 0.1], dtype=np.float64)
    model = gtsam.noiseModel.Diagonal.Sigmas(sigmas)
    returned_sigmas = model.sigmas()
    assert isinstance(returned_sigmas, np.ndarray)
    assert returned_sigmas.shape == (3,)
    np.testing.assert_allclose(returned_sigmas, sigmas)
    print(f"NUMPY ABI OK: numpy={np.__version__}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
