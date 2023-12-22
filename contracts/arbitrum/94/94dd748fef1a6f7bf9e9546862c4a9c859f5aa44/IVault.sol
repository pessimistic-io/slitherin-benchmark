// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {IERC721} from "./IERC721.sol";
import {IFundsCollector} from "./IFundsCollector.sol";
import {IDefii} from "./IDefii.sol";

interface IVault is IERC721, IFundsCollector {
    event FundsDeposited(address user, uint256 amount);
    event WithdrawStarted(uint256 tokenId, uint256 percentage);

    error UnsupportedDefii(address defii);

    function deposit(uint256 amount) external;

    function startWithdraw(uint256 percentage) external;

    function enterDefii(
        address defii,
        uint256 tokenId,
        uint256 amount,
        IDefii.Instruction[] calldata instructions
    ) external payable;

    function exitDefii(
        address defii,
        uint256 tokenId,
        uint256 percentage,
        IDefii.Instruction[] calldata instructions
    ) external payable;

    function notion() external view returns (address);
}

