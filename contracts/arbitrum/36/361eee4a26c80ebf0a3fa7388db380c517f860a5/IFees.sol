// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IFees {

    struct FundFees {
        uint256 live;
        uint256 sf;
        uint256 pf;
        uint256 mf;
    }


    /**
    * Events
    */
    event NewFund(uint256 fundId, uint256 sf, uint256 pf, uint256 mf);

    event SfCharged(uint256 indexed fundId, uint256 amount);
    event PfCharged(uint256 indexed fundId, uint256 amount);
    event MfCharged(uint256 indexed fundId, uint256 amount);
    event EfCharged(uint256 indexed fundId, uint256 amount);

    event Withdrawal(address indexed user, address token, uint256 amount);
    event WithdrawalFund(uint256 indexed fundId, address destination, address token, uint256 amount);

    event ServiceFeesChanged(uint256 sf, uint256 pf, uint256 mf);
    /**
    * Public
    */

    /**
    * Auth
    */

    function newFund(uint256 fundId, uint256 sf, uint256 pf, uint256 mf) external;

    /**
    * View
    */
    function fees(uint256 fundId) external view returns(uint256 sf, uint256 pf, uint256 mf);
    function serviceFees() external view returns(uint256 sf, uint256 pf, uint256 mf);
    function gatheredFees(uint256 fundId) external view returns(uint256 live, uint256 sf, uint256 pf, uint256 mf);

    function gatherSf(uint256 fundId, uint256 pending, address token) external returns(uint256);

    function gatherPf(uint256 fundId, uint256 pending, address token) external;

    function gatherMf(uint256 fundId, uint256 pending, address token, address manager) external;

    function gatherEf(uint256 fundId, uint256 amount, address token) external;
    function gatherCf(uint256 fundId, address payer, uint256 amount, address token) external;
    function calculatePF(uint256 fundId, uint256 amount) external view returns (uint256);

    function withdraw(address user, uint256 amount) external;

    function withdrawFund(uint256 fundId, address destination, uint256 amount) external;
}

