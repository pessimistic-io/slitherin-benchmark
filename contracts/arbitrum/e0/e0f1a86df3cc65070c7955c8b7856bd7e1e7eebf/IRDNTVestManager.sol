// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IERC20 } from "./IERC20.sol";

interface IRDNTVestManager {

    function scheduleVesting(
        address _for,
        uint256 _amount,
        uint256 _endTime
    ) external;

}

