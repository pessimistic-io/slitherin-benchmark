// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./Address.sol";
import "./Ownable.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import {ZERO, ONE, UC, uc, into} from "./UC.sol";

contract BatchTransfer is Ownable {

    using Address for address payable;
    using SafeERC20 for IERC20;

    event BatchTransferERC20(address indexed token, address[] toAddresses, uint256 totalAmount);
    event BatchTransferERC20ManyAmount(address indexed token, address[] toAddresses, uint256[] amounts);
    event BatchTransferETH(address payable[] toAddresses, uint256 totalAmount);
    event BatchTransferManyAmountETH(address payable[] toAddresses, uint256[] amounts);

    function batchTransfer(address token, address[] memory toAddresses, uint256 amount) external onlyOwner {
        IERC20 erc20 = IERC20(token);
        uint totalAmount;
        for (UC i = ZERO; i < uc(toAddresses.length); i = i + ONE) {
            erc20.safeTransfer(toAddresses[i.into()], amount);
            totalAmount += amount;
        }
        emit BatchTransferERC20(token, toAddresses, totalAmount);
    }

    function batchTransferManyAmount(address token, address[] memory toAddresses, uint256[] memory amounts) external onlyOwner {
        IERC20 erc20 = IERC20(token);
        require(toAddresses.length == amounts.length, "unequal length");
        for (UC i = ZERO; i < uc(toAddresses.length); i = i + ONE) {
            erc20.safeTransfer(toAddresses[i.into()], amounts[i.into()]);
        }
        emit BatchTransferERC20ManyAmount(token, toAddresses, amounts);
    }

    function batchTransferETH(address payable[] memory toAddresses, uint256 amount) external payable {
        uint totalAmount;
        for (UC i = ZERO; i < uc(toAddresses.length); i = i + ONE) {
            toAddresses[i.into()].sendValue(amount);
            totalAmount += amount;
        }
        emit BatchTransferETH(toAddresses, totalAmount);
    }

    function batchTransferManyAmountETH(address payable[] memory toAddresses, uint256[] memory amounts) external payable {
        require(toAddresses.length == amounts.length, "unequal length");
        for (UC i = ZERO; i < uc(toAddresses.length); i = i + ONE) {
            toAddresses[i.into()].sendValue(amounts[i.into()]);
        }
        emit BatchTransferManyAmountETH(toAddresses, amounts);
    }
}

