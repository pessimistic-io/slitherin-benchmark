// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "./Ownable.sol";

abstract contract FeeManager is Ownable {
    uint public constant MAX_FEE = 1000;

    uint public constant PERFORMANCE_FEE_CAP = 150; //15% Cap
    uint public performanceFee = 50; //5% Initital

    uint public strategistFee = 200;
    uint public steakHutFee = MAX_FEE - strategistFee;

    /// -----------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------

    event SetPerformanceFee(uint256 performanceFee);
    event SetStrategistFee(uint256 strategistFee);

    /// -----------------------------------------------------------
    /// Manager Functions
    /// -----------------------------------------------------------
    function setPerformanceFee(uint256 _fee) external onlyOwner {
        require(_fee <= PERFORMANCE_FEE_CAP, "!cap");

        performanceFee = _fee;
        emit SetPerformanceFee(_fee);
    }

    function setStrategistFee(uint256 _fee) external onlyOwner {
        require(_fee <= MAX_FEE, "!cap");

        strategistFee = _fee;
        emit SetStrategistFee(_fee);
    }
}

