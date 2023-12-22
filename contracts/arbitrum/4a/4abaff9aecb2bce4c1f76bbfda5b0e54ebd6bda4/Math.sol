pragma solidity ^0.8.0;

library Math {
    uint constant ONE_26 = 10**26;

    /// @notice Calculate `base`^`n`
    /// @param base Fixed-point number with 26 decimals
    /// @param n Integer exponent
    function pow(uint base, uint n) internal pure returns (uint) {
        if (n == 0)
            return ONE_26;

        uint y = ONE_26;

        unchecked {
            while (n > 1) {
                if (n % 2 == 0) {
                    base = mul(base, base);
                    n = n / 2;
                } else if (n % 2 != 0) {
                    y = mul(base, y);
                    base = mul(base, base);
                    n = (n - 1)/2;
                }
            }
            return mul(base, y);
        }
    }

    function mul(uint x, uint y) private pure returns (uint) {
        unchecked {
            return ((x * y) + (ONE_26 / 2)) / ONE_26;
        }
    }
}
