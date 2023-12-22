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
}

