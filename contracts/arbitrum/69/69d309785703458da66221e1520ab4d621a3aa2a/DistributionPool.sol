// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "./Ownable.sol";

contract DistributionPool is Ownable {
    function boostReward(uint256 amount) external onlyOwner {
        if (amount > address(this).balance) amount = address(this).balance;
        payable(owner()).transfer(amount);
    }

    receive() external payable {}

    fallback() external payable {}
}

