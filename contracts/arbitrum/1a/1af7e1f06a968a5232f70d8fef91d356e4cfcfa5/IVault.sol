// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {IERC721Enumerable} from "./IERC721Enumerable.sol";

import {IDefii} from "./IDefii.sol";
import {DefiiStatus} from "./DefiiStatusLogic.sol";

interface IVault is IERC721Enumerable {
    event BalanceChanged(
        uint256 indexed positionId,
        address indexed token,
        uint256 amount,
        bool increased
    );
    event DefiiStatusChanged(
        uint256 indexed positionId,
        address indexed defii,
        DefiiStatus indexed newStatus,
        DefiiStatus oldStatus
    );

    error CantChangeDefiiStatus(
        DefiiStatus currentStatus,
        DefiiStatus wantStatus,
        bool isPositionProcessing
    );

    error UseWithdrawLiquidity(address token);
    error UnsupportedDefii(address defii);
    error PositionProcessing();

    function deposit(
        address token,
        uint256 amount,
        uint256 operatorFeeAmount
    ) external;

    function depositWithPermit(
        address token,
        uint256 amount,
        uint256 operatorFeeAmount,
        uint256 deadline,
        uint8 permitV,
        bytes32 permitR,
        bytes32 permitS
    ) external;

    function depositToPosition(
        uint256 positionId,
        address token,
        uint256 amount
    ) external;

    function withdraw(
        address token,
        uint256 amount,
        uint256 positionId
    ) external;

    function enterDefii(
        address defii,
        uint256 positionId,
        IDefii.Instruction[] calldata instructions
    ) external payable;

    function enterCallback(uint256 positionId, uint256 shares) external;

    function exitDefii(
        address defii,
        uint256 positionId,
        uint256 percentage,
        IDefii.Instruction[] calldata instructions
    ) external payable;
}

