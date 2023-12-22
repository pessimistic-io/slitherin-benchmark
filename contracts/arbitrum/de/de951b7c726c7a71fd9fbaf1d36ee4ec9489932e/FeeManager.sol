// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "./StratManager.sol";

abstract contract FeeManager is StratManager {
    uint public constant STRATEGIST_FEE = 112;
    uint public constant MAX_FEE = 1000;
    uint public constant MAX_CALL_FEE = 111;

    uint public constant PERFORMANCE_FEE_CAP = 150; //15% Cap
    uint public performanceFee = 50; //5% Initital

    uint public callFee = 111;
    uint public steakHutFee = MAX_FEE - STRATEGIST_FEE - callFee;

    /// -----------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------
    event SetCallFee(uint256 callFee, uint256 steakHutFee);
    event SetPerformanceFee(uint256 performanceFee);

    /// -----------------------------------------------------------
    /// Manager Functions
    /// -----------------------------------------------------------
    function setCallFee(uint256 _fee) external onlyManager {
        require(_fee <= MAX_CALL_FEE, "!cap");

        callFee = _fee;
        steakHutFee = MAX_FEE - STRATEGIST_FEE - callFee;

        emit SetCallFee(_fee, steakHutFee);
    }

    function setPerformanceFee(uint256 _fee) external onlyManager {
        require(_fee <= PERFORMANCE_FEE_CAP, "!cap");

        performanceFee = _fee;
        emit SetPerformanceFee(_fee);
    }
}

