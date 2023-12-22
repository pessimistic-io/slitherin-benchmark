// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;

import "./IOreoV3Factory.sol";
import "./INonfungiblePositionManager.sol";

import "./OreoV3LmPool.sol";

/// @dev This contract is for Master Chef to create a corresponding LmPool when
/// adding a new farming pool. As for why not just create LmPool inside the
/// Master Chef contract is merely due to the imcompatibility of the solidity
/// versions.
contract OreoV3LmPoolDeployer {
    address public immutable masterChef;

    modifier onlyMasterChef() {
        require(msg.sender == masterChef, "Not MC");
        _;
    }

    constructor(address _masterChef) {
        masterChef = _masterChef;
    }

    /// @dev Deploys a LmPool
    /// @param pool The contract address of the OreoSwap V3 pool
    function deploy(IOreoV3Pool pool) external onlyMasterChef returns (IOreoV3LmPool lmPool) {
        lmPool = new OreoV3LmPool(address(pool), masterChef, uint32(block.timestamp));
        IOreoV3Factory(INonfungiblePositionManager(IMasterChefV3(masterChef).nonfungiblePositionManager()).factory()).setLmPool(address(pool), address(lmPool));
    }
}

