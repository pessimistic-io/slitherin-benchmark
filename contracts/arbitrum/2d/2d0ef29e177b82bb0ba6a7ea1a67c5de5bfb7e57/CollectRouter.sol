// SPDX-License-Identifier: No License
/**
 * @title Collect Router
 * @author 0xTaiga
 * @dev Allows for mass collection of the pools once they are expired
 */

import "./ILendingPool.sol";

 contract CollectRouter {
    function collect(address[] calldata _pools) external {
        for (uint256 i = 0; i < _pools.length; i++) {
            ILendingPool(_pools[i]).collect();
        }
    }
 }

