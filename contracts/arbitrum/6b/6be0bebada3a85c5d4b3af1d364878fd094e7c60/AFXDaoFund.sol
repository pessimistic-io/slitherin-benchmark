// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "./Fund.sol";

contract AFXDaoFund is Fund {
    uint256 public constant ALLOCATION = 3_000_000 ether; // 10%
    uint256 public constant VESTING_DURATION = 3 * 365 * 24 * 3600; // 3 years
    uint256 public constant VESTING_START = 1676764800; // Sun Feb 19 2023 00:00:00 GMT+0000

    /*===================== VIEWS =====================*/

    function allocation() public pure override returns (uint256) {
        return ALLOCATION;
    }

    function vestingStart() public pure override returns (uint256) {
        return VESTING_START;
    }

    function vestingDuration() public pure override returns (uint256) {
        return VESTING_DURATION;
    }
}

