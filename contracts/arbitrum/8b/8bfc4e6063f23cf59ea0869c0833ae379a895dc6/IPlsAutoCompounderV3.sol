// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IPlsAutoCompounderFactory } from "./IPlsAutoCompounderFactory.sol";

interface IPlsAutoCompounderV3 {
    function factory() external view returns (IPlsAutoCompounderFactory);

    function compounderOwner() external view returns (address);

    function totalPlsStaked() external view returns (uint256);

    function compounderPaused() external view returns (bool);

    function initialize(
        address _pls,
        address _esPls,
        address _plutusRouter,
        address _rewardTracker,
        address _stakedEsPlsTracker,
        address _lockedToken,
        address compounderOwner_
    ) external;

    function stakePls(address user, uint256 amount) external;

    function compoundPls(uint256 amount) external;

    function unStakePls() external;

    function stakeEsPls() external;

    function claimAndStakeEsPls() external;

    function unStakeEsPls(uint256 amount, bool unStakeAll) external;

    function compoundMpPls() external;

    function pauseCompounder() external;

    function unpauseCompounder() external;

    function toggleAutoExtend() external;

    function claimEsPls() external;

    function claimPlsStakeAndLockRewards(address rewardContract, bytes memory claimData) external;

    function transferRewardsOut(address[] memory tokens, address to) external returns (uint256[] memory);

    function vestEsPls(address target, bytes memory data) external;

    function claimVestedEsPls(address target, bytes memory data) external;
}

interface ITracker {
    function stakedAmounts(address _account) external view returns (uint256);

    function totalSupply() external view returns (uint256);
}

