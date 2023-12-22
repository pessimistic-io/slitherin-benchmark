// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "./IERC20.sol";

interface IEscrowMaster {
    // ----------- Farms only State changing api -----------

    function lock(address, uint256) external;

    // ----------- state changing API -----------

    function claim() external;

    // ----------- Getters -----------

    function PERIOD() external view returns (uint256);

    function LOCKEDPERIODAMOUNT() external view returns (uint256);

    function vestingToken() external view returns (IERC20);

    function userLockedRewards(
        address account,
        uint256 idx
    ) external view returns (uint256, uint256);

    function totalLockedRewards() external view returns (uint256);

    function getVestingAmount() external view returns (uint256, uint256);
}

