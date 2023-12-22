// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "./IGlpWrapperHarvestor.sol";
import "./IMimCauldronDistributor.sol";

contract MimCauldronDistributorLens {
    error ErrCauldronNotFound(address);

    IGlpWrapperHarvestor public immutable harvestor;

    constructor(IGlpWrapperHarvestor _harvestor) {
        harvestor = _harvestor;
    }

    // returns the apy in bips scaled by 1e18
    function getCaulronTargetApy(address _cauldron) external view returns (uint256) {
        IMimCauldronDistributor distributor = harvestor.distributor();
        uint256 cauldronInfoCount = distributor.getCauldronInfoCount();

        for (uint256 i = 0; i < cauldronInfoCount; ) {
            (address cauldron, uint256 targetApyPerSecond, , , , , , ) = distributor.cauldronInfos(i);

            if (cauldron == _cauldron) {
                return targetApyPerSecond * 365 days;
            }

            // for the meme.
            unchecked {
                ++i;
            }
        }

        revert ErrCauldronNotFound(_cauldron);
    }
}

