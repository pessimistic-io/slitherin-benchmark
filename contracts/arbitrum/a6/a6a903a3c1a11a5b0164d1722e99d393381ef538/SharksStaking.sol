// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;
import "./Sharks.sol";
import "./Ownable.sol";
import "./Math.sol";

contract SharksStaking is Ownable {
    Sharks public sharks;

    uint256 public constant DAY = 1 days;
    uint256 public xpPerDay;
    uint256 public maxStakeDaysCount;
    mapping(uint256 => uint256) public stakedUntil;

    event Staked(uint256 indexed tokenId, uint256 until);
    event Restaked(uint256 indexed tokenId, uint256 until);
    event Unstaked(uint256 indexed tokenId);
    event XpPerDayChanged(uint256 xpPerDay);
    event MaxStakeDaysCountChanged(uint256 maxStakeDaysCount);

    modifier onlySharkOwner(uint256 tokenId_) {
        require(sharks.ownerOf(tokenId_) == msg.sender, "You do not own this shark");
        _;
    }

    constructor(address sharksAddress_) {
        sharks = Sharks(sharksAddress_);
        xpPerDay = 192; // sharks cruise at 8km/h
        maxStakeDaysCount = 365;
    }

    function stake(uint256 tokenId_, uint256 daysCount_) external onlySharkOwner(tokenId_) {
        require(daysCount_ > 0, "must stake in the future");
        require(daysCount_ <= maxStakeDaysCount, "cannot stake for more than maxStakeDaysCount");

        if (stakedUntil[tokenId_] == 0) {
            sharks.increaseXp(tokenId_, daysCount_ * xpPerDay);
            stakedUntil[tokenId_] = block.timestamp + daysCount_ * DAY;
            emit Staked(tokenId_, stakedUntil[tokenId_]);
        } else {
            // Rounded towards 0, meaning 23:59 counts as 0 days.
            uint256 _stakedUntilInDays = (stakedUntil[tokenId_] - block.timestamp) / DAY;

            // Since we're restaking, maxStakeDaysCount should be 365-1=364
            uint256 _actualMaxStakeDaysCount = maxStakeDaysCount - _stakedUntilInDays - 1;

            uint256 _actualDaysCount = Math.min(daysCount_, _actualMaxStakeDaysCount);

            sharks.increaseXp(tokenId_, _actualDaysCount * xpPerDay);
            stakedUntil[tokenId_] += _actualDaysCount * DAY;
            emit Restaked(tokenId_, stakedUntil[tokenId_]);
        }
    }

    function unstake(uint256 tokenId_) external onlySharkOwner(tokenId_) {
        require(block.timestamp >= stakedUntil[tokenId_], "cannot unstake yet");

        stakedUntil[tokenId_] = 0;

        emit Unstaked(tokenId_);
    }

    function setXpPerDay(uint256 xpPerDay_) external onlyOwner {
        xpPerDay = xpPerDay_;
        emit XpPerDayChanged(xpPerDay);
    }

    function setMaxStakeDaysCount(uint256 maxStakeDaysCount_) external onlyOwner {
        maxStakeDaysCount = maxStakeDaysCount_;
        emit MaxStakeDaysCountChanged(maxStakeDaysCount);
    }

    function sharkCanBeTransferred(uint tokenId_) public view returns (bool) {
        if (stakedUntil[tokenId_] == 0) {
            return true;
        } else {
            return false;
        }
    }

}

