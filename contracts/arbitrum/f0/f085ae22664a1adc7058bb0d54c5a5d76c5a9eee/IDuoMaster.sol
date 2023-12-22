// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IERC20.sol";
import {IStrategy} from "./IStrategy.sol";

interface IDuoMaster {
    function userShares(
        uint256 pidMonopoly,
        address user
    ) external view returns (uint256);

    function totalShares(uint256 pidMonopoly) external view returns (uint256);

    function actionFeeAddress() external view returns (address);

    function performanceFeeAddress() external view returns (address);

    function harvest(uint256 pid, address to) external;

    function deposit(
        uint256 pid,
        uint256 amount,
        address to,
        address referrer
    ) external;

    function withdraw(uint256 pid, uint256 amount, address to) external;

    function owner() external view returns (address);

    function add(
        uint256 alloc,
        uint16 depositBP,
        uint16 withdrawBP,
        IERC20 want,
        bool withUpdate,
        bool isWithdrawFee,
        IStrategy strat
    ) external;

    function set(
        uint256 pid,
        uint256 alloc,
        uint16 depositBP,
        uint16 withdrawBP,
        bool withUpdate,
        bool isWithdrawFee
    ) external;

    function userInfo(
        uint256 pid,
        address user
    )
        external
        view
        returns (uint256 amount, uint256 rewardDebt, uint256 lastTimeDeposit);

    function pendingEarnings(
        uint256 pid,
        address user
    ) external view returns (uint256);
}

