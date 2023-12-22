//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Lock } from "./Structs.sol";

interface IPepeLockUp {
    function initializePool(uint256 wethAmount, uint256 pegAmount, address poolAdmin) external;

    function updateRewards() external;

    function lock(uint256 wethAmount, uint256 pegAmount, uint256 minBlpOut) external;

    function unLock() external;

    function claimUsdcRewards() external;

    function pendingUsdcRewards(address _user) external view returns (uint256);

    function getLockDetails(address _user) external view returns (Lock memory);

    function lockDuration() external view returns (uint48);

    function setLockDuration(uint48 _lockDuration) external;

    function setFeeDistributor(address _feeDistributor) external;
}

