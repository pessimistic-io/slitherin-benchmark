// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./SafeERC20.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";

contract AiDogeTool is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    address _tokenAddress;

    constructor(address tokenAddress) {
        _tokenAddress = tokenAddress;
    }

    function transferBatchValue(
        address[] calldata tos,
        uint256[] calldata amounts
    ) public onlyOwner {
        require(tos.length == amounts.length, "length error");
        IERC20 token = IERC20(_tokenAddress);
        for (uint256 i = 0; i < tos.length; i++) {
            token.safeTransferFrom(_msgSender(), tos[i], amounts[i]);
        }
    }

    function transferBatchValue(
        address[] calldata tos,
        uint256 amount
    ) public onlyOwner {
        IERC20 token = IERC20(_tokenAddress);
        for (uint256 i = 0; i < tos.length; i++) {
            token.safeTransferFrom(_msgSender(), tos[i], amount);
        }
    }
}

