// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./StratManager.sol";

abstract contract FeeManager is StratManager {
    uint public constant STRATEGIST_FEE = 112;
    uint public constant MAX_FEE = 1000;
    uint public constant MAX_CALL_FEE = 111;

    uint public constant WITHDRAWAL_FEE_CAP = 50;
    uint public constant WITHDRAWAL_MAX = 10000;

    uint public withdrawalFee = 10;

    uint public callFee = 111;
    uint public beefyFee = MAX_FEE - STRATEGIST_FEE - callFee;

    /**
     *@notice Set call fee
     *@param _fee fee amount
     */
    function setCallFee(uint256 _fee) public onlyManager {
        require(_fee <= MAX_CALL_FEE, "!cap");

        callFee = _fee;
        beefyFee = MAX_FEE - STRATEGIST_FEE - callFee;
    }

    /**
     *@notice Set withdrawal fee
     *@param _fee fee amount
     */
    function setWithdrawalFee(uint256 _fee) public onlyManager {
        require(_fee <= WITHDRAWAL_FEE_CAP, "!cap");

        withdrawalFee = _fee;
    }
}

