// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { IRewardRouter } from "./IRewardRouter.sol";
import { BaseVault } from "./BaseVault.sol";

contract GmxYieldAdapter is BaseVault {
    // Reward router for GMX. Note that this must be V1, not V2, for now.
    address public rewardRouter;

    function initialize(
        address _controller,
        address _tau,
        address _collateralToken,
        address _rewardRouter
    ) external initializer {
        __BaseVault_init(_controller, _tau, _collateralToken);
        rewardRouter = _rewardRouter;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // Vault management functions

    /**
     * @dev function to collect yield from Gmx. Callable by anyone since we have sandwich attack protections in place.
     * Note that we do not vest any esGmx tokens. They are simply staked immediately. Long-term this will lead to greater protocol yield.
     */
    function collectYield() external whenNotPaused {
        IRewardRouter(rewardRouter).claimFees(); // Claim WETH yield from staked esGmx and Glp
        IRewardRouter(rewardRouter).compound(); // Claim and stake esGmx and bnGmx earned from staked esGmx and Glp
    }

    function updateRewardRouter(address _newRewardRouter) external onlyMultisig {
        rewardRouter = _newRewardRouter;
    }

    uint256[49] private __gap;
}

