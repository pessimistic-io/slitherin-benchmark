// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./Ownable.sol";

interface IAccru {
    function balanceOf(address account) external view returns (uint256);

    function transfer(address to, uint256 value) external returns (bool);
}

contract MarketingVester is Ownable {
    address public accru;
    address public recipient;

    uint256 public vestingAmount;
    uint256 public vestingBegin;
    uint256 public vestingPeriod;
    uint256 public vestingEnd;
    uint256 public claimedAmount;

    uint256 public lastUpdate;

    constructor(
        address accru_,
        address recipient_,
        uint256 vestingAmount_,
        uint256 vestingBegin_,
        uint256 vestingPeriod_,
        uint256 vestingEnd_
    ) {
        require(vestingEnd_ > vestingBegin_, "VESTING_END_BEFORE_BEGIN");

        accru = accru_;
        recipient = recipient_;

        vestingAmount = vestingAmount_;
        vestingBegin = vestingBegin_;
        vestingPeriod = vestingPeriod_;
        vestingEnd = vestingEnd_;
    }

    function setRecipient(address recipient_) external onlyOwner {
        recipient = recipient_;
    }

    function claim() external onlyOwner {
        require(block.timestamp >= vestingBegin, "VESTING_NOT_STARTED");
        if (lastUpdate != 0) {
            require(
                block.timestamp >= lastUpdate + vestingPeriod,
                "CLAIM_TOO_EARLY"
            );
        }

        uint256 amount;
        if (block.timestamp >= vestingEnd) {
            amount = IAccru(accru).balanceOf(address(this));
        } else {
            amount = vestingAmount / 4;
            lastUpdate = block.timestamp;
        }
        require(amount > 0, "NOTHING_TO_CLAIM");
        claimedAmount += amount;
        require(claimedAmount <= vestingAmount, "EXCEEDS_VESTED_AMOUNT");

        IAccru(accru).transfer(recipient, amount);
    }
}

