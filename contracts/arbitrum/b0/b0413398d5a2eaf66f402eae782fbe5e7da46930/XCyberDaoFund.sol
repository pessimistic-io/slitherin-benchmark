// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "./Fund.sol";

contract XCyberDaoFund is Fund {
    uint256 public constant ALLOCATION = 6_000_000 * 1e18; // 20%
    uint256 public constant VESTING_DURATION = 3 * 365 * 24 * 3600; // 3 years
    uint256 public constant VESTING_START = 1654279200; // Fri June 03 2022 18:00:00 GMT+0000

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

