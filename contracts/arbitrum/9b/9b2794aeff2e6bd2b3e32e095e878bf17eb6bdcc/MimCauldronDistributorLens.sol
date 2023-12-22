// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "./IGlpWrapperHarvestor.sol";
import "./IMimCauldronDistributor.sol";

contract MimCauldronDistributorLens {
    error ErrCauldronNotFound(address);

    uint256 internal constant MAX_UINT256 = 2**256 - 1;

    uint256 internal constant WAD = 1e18; // The scalar of ETH and most ERC20s.

    IGlpWrapperHarvestor public immutable harvestor;

    constructor(IGlpWrapperHarvestor _harvestor) {
        harvestor = _harvestor;
    }

    // Source: https://github.com/transmissions11/solmate/blob/main/src/utils/FixedPointMathLib.sol
    function mulWadUp(uint256 x, uint256 y) internal pure returns (uint256) {
        return mulDivUp(x, y, WAD); // Equivalent to (x * y) / WAD rounded up.
    }

    function mulDivUp(
        uint256 x,
        uint256 y,
        uint256 denominator
    ) internal pure returns (uint256 z) {
        /// @solidity memory-safe-assembly
        assembly {
            // Equivalent to require(denominator != 0 && (y == 0 || x <= type(uint256).max / y))
            if iszero(mul(denominator, iszero(mul(y, gt(x, div(MAX_UINT256, y)))))) {
                revert(0, 0)
            }

            // If x * y modulo the denominator is strictly greater than 0,
            // 1 is added to round up the division of x * y by the denominator.
            z := add(gt(mod(mul(x, y), denominator), 0), div(mul(x, y), denominator))
        }
    }

    // returns the apy in bips scaled by 1e18
    function getCaulronTargetApy(address _cauldron) external view returns (uint256) {
        IMimCauldronDistributor distributor = harvestor.distributor();
        uint256 cauldronInfoCount = distributor.getCauldronInfoCount();

        for (uint256 i = 0; i < cauldronInfoCount; ) {
            (address cauldron, uint256 targetApyPerSecond, , , , , , ) = distributor.cauldronInfos(i);

            if (cauldron == _cauldron) {
                return mulWadUp(targetApyPerSecond, 365 days);
            }

            // for the meme.
            unchecked {
                ++i;
            }
        }

        revert ErrCauldronNotFound(_cauldron);
    }
}

