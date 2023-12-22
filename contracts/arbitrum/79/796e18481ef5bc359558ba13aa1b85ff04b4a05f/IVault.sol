// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {IERC721} from "./IERC721.sol";
import {IFundsCollector} from "./IFundsCollector.sol";
import {IDefii} from "./IDefii.sol";

interface IVault is IERC721, IFundsCollector {
    event FundsDeposited(
        address indexed token,
        uint256 positionId,
        uint256 amount
    );
    event FundsWithdrawn(
        address indexed token,
        uint256 positionId,
        uint256 amount
    );
    event FundsCollected(
        address indexed token,
        uint256 positionId,
        uint256 amount
    );

    error UnsupportedDefii(address defii);

    function deposit(address token, uint256 amount) external;

    function depositWithPermit(
        address token,
        uint256 amount,
        uint256 deadline,
        uint8 permitV,
        bytes32 permitR,
        bytes32 permitS
    ) external;

    function withdraw(
        address token,
        uint256 amount,
        uint256 positionId
    ) external;

    function enterDefii(
        address defii,
        uint256 positionId,
        uint256 amount,
        IDefii.Instruction[] calldata instructions
    ) external payable;

    function exitDefii(
        address defii,
        uint256 positionId,
        uint256 percentage,
        IDefii.Instruction[] calldata instructions
    ) external payable;
}

