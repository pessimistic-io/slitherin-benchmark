// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "./StratManager.sol";

abstract contract FeeManager is StratManager {
    uint constant public MAX_FEE = 1000;
    uint constant public MAX_WITHDRAWAL = 10000;

    uint constant public MAX_CALL_FEE = 111;
    uint constant public MAX_PERFORMANCE_FEE = 45;
    uint constant public MAX_STRATEGIST_FEE = 750;
    uint constant public MAX_WITHDRAWAL_FEE = 10;

    uint public callFee = 0;
    uint public performanceFee = 20;
    uint public strategistFee = 0;
    uint public withdrawalFee = 5;

    uint public companyFee = calculateCompanyFee();

    function setCallFee(uint256 _fee) public onlyManager {
        require(_fee <= MAX_CALL_FEE, "!cap");

        callFee = _fee;
        companyFee = calculateCompanyFee();
    }

    function setPerformanceFee(uint256 _fee) public onlyManager {
        require(_fee <= MAX_PERFORMANCE_FEE, "!cap");

        performanceFee = _fee;
        companyFee = calculateCompanyFee();
    }

    function setStrategistFee(uint256 _fee) public onlyManager {
        require(_fee <= MAX_STRATEGIST_FEE, "!cap");

        strategistFee = _fee;
        companyFee = calculateCompanyFee();
    }

    function setWithdrawalFee(uint256 _fee) public onlyManager {
        require(_fee <= MAX_WITHDRAWAL_FEE, "!cap");

        withdrawalFee = _fee;
    }

    function calculateCompanyFee() internal view returns (uint256) {
        return MAX_FEE - callFee - strategistFee;
    }
}
