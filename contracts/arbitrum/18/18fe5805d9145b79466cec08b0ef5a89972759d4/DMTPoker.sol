// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {DMTPokerChips} from "./DMTPokerChips.sol";
import {OwnableOracle} from "./OwnableOracle.sol";
import {IERC20} from "./IERC20.sol";
import {Pausable} from "./Pausable.sol";

contract DMTPoker is DMTPokerChips, OwnableOracle, Pausable {
    IERC20 public dmt;
    uint256 public limit;

    event PayoutFailed(address indexed recipient, uint256 amount);
    event IndividualPayout(address indexed recipient, uint256 amount);
    event PayoutsComplete(uint256 successfulPayouts, uint256 failedPayouts);
    event ConvertedToChips(address indexed depositor, uint256 amountDeposited);

    constructor(address dmtAddress) OwnableOracle(msg.sender) {
        dmt = IERC20(dmtAddress);
    }

    function updateLimit(uint256 _limit) external onlyOwner {
        limit = _limit;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function convertToChips(uint256 amount) external whenNotPaused {
        if (dmt.balanceOf(address(this)) + amount >= limit) {
            revert("The poker contract has reached its limit for DMT deposits");
        }

        dmt.transferFrom(msg.sender, address(this), amount);
        mint(msg.sender, amount * 100);
        emit ConvertedToChips(msg.sender, amount);
    }

    function payouts(address[] memory recipients, uint256[] memory amounts) public onlyOracle whenNotPaused {
        require(recipients.length == amounts.length, "Arrays must have the same length");

        uint256 successfulPayouts = 0;
        uint256 failedPayouts = 0;
        for (uint256 i = 0; i < recipients.length; i++) {
            address recipient = recipients[i];
            uint256 amount = amounts[i];

            bool success = individualPayout(recipient, amount);
            if (success) {
                successfulPayouts++;
            } else {
                failedPayouts++;
            }
        }

        emit PayoutsComplete(successfulPayouts, failedPayouts);
    }

    function individualPayout(address recipient, uint256 amount) private returns (bool) {
        bool success = dmt.transfer(recipient, amount);
        if (!success) {
            emit PayoutFailed(recipient, amount);
            return false;
        }

        burn(recipient, balanceOf(recipient));
        emit IndividualPayout(recipient, amount);
        return true;
    }
}

