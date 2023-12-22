//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { EsPegLock } from "./Structs.sol";

interface IPepeEsPegLockUp {
    function lock(uint256 wethAmount, uint256 esPegAmount, uint256 minBlpOut) external;

    function setRewardPool(address _rewwardPool) external;

    function setLockDuration(uint48 _lockDuration) external;

    function unlock() external;

    function pendingPegRewards(address _user) external view returns (uint256);

    function getLockDetails(address _user) external view returns (EsPegLock memory);
}

