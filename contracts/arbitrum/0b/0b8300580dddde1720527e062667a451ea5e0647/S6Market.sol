// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IFlashLoanReceiver} from "./IFlashLoanReceiver.sol";
import {IERC20} from "./IERC20.sol";

contract S6Market {
    error S6Market__RepayFailed();

    IERC20 private immutable i_token;

    constructor(address _token) {
        i_token = IERC20(_token);
    }

    function flashLoan(uint256 amount) external {
        uint256 balanceBefore = i_token.balanceOf(address(this));

        i_token.transfer(msg.sender, amount);
        IFlashLoanReceiver(msg.sender).execute();

        if (i_token.balanceOf(address(this)) < balanceBefore) {
            revert S6Market__RepayFailed();
        }
    }

    function getToken() external view returns (address) {
        return address(i_token);
    }

    // @dev this function was put in here to be funny
    // Don't actually try to send me any tokens
    function buyTokens() external payable {
        if (msg.value < 1_000_000 ether) {
            revert("You're too broke to call this.");
        }
        revert("Don't actually call this function");
    }
}

