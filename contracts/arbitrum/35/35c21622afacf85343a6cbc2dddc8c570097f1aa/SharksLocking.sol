// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;
import "./Sharks.sol";
import "./Math.sol";
import "./Strings.sol";
import "./AccessControl.sol";

contract SharksLocking is AccessControl {
    Sharks public sharks;

    uint256 public constant WEEK = 7 days;
    uint256 public xpPerWeek;
    uint256 public maxLockWeeksCount;
    mapping(uint256 => uint256) public lockedAt;
    mapping(uint256 => uint256) public lockedUntil;

    bytes32 public constant LOCK_MANAGER = keccak256("LOCK_MANAGER");

    event Locked(uint256 indexed tokenId, uint256 until, uint256 xpIncrease);
    event Relocked(uint256 indexed tokenId, uint256 until, uint256 xpIncrease);
    event Unlocked(uint256 indexed tokenId, uint256 lockedForWeeksCount);
    event XpPerWeekChanged(uint256 xpWeekWeek);
    event MaxLockWeeksCountChanged(uint256 maxLockWeeksCount);
    event LockUpdated(uint256 indexed tokenId, uint256 at, uint256 until, address lockManager);

    modifier onlySharkOwner(uint256 tokenId_) {
        require(sharks.ownerOf(tokenId_) == msg.sender, "SharksLocking: You do not own this shark");
        _;
    }

    constructor(address sharksAddress_) {
        sharks = Sharks(sharksAddress_);
        xpPerWeek = 168; // 1XP/h
        maxLockWeeksCount = 52;

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function lockMany(uint256[] calldata tokenIds_, uint256 weeksCount_) public {
        for (uint256 i = 0; i < tokenIds_.length; i++) {
            lock(tokenIds_[i], weeksCount_);
        }
    }

    function relockMany(uint256[] calldata tokenIds_, uint256 weeksCount_) public {
        for (uint256 i = 0; i < tokenIds_.length; i++) {
            relock(tokenIds_[i], weeksCount_);
        }
    }

    function unlockMany(uint256[] calldata tokenIds_) public {
        for (uint256 i = 0; i < tokenIds_.length; i++) {
            unlock(tokenIds_[i]);
        }
    }


    function lock(uint256 tokenId_, uint256 weeksCount_) public onlySharkOwner(tokenId_) {
        require(lockedUntil[tokenId_] == 0, "SharksLocking: already locked");
        require(weeksCount_ > 0, "SharksLocking: must lock for at least 1 week");
        require(weeksCount_ <= maxLockWeeksCount, "SharksLocking: cannot lock for more than maxLockWeeksCount");

        uint256 _xpIncrease = calculateXpIncrease(weeksCount_);
        uint256 _lockedUntilTimestamp = block.timestamp + weeksToSeconds(weeksCount_);

        lockedAt[tokenId_] = block.timestamp;
        lockedUntil[tokenId_] = _lockedUntilTimestamp;

        sharks.increaseXp(
            tokenId_,
            _xpIncrease
        );

        emit Locked(
            tokenId_,
            _lockedUntilTimestamp,
            _xpIncrease
        );
    }

    function relock(uint256 tokenId_, uint256 weeksCount_) public onlySharkOwner(tokenId_) {
        require(lockedUntil[tokenId_] > 0, "SharksLocking: not locked yet");
        require(weeksCount_ > 0, "SharksLocking: must relock for at least 1 week");
        require(weeksCount_ <= maxLockWeeksCount, "SharksLocking: cannot relock for more than maxLockWeeksCount");

        uint256 _weeksRemainingCount;
        uint256 _baseTimestamp;
        if (lockedUntil[tokenId_] > block.timestamp) {
            _weeksRemainingCount = ((lockedUntil[tokenId_] - block.timestamp) / WEEK) + 1;
            _baseTimestamp = lockedUntil[tokenId_];
        } else {
            _weeksRemainingCount = 0;
            _baseTimestamp = block.timestamp;
        }

        uint256 _actualMaxLockWeeksCount = maxLockWeeksCount - _weeksRemainingCount;

        if (weeksCount_ > _actualMaxLockWeeksCount) {
            revert(string(abi.encodePacked(
                "SharksLocking: can only relock for ",
                Strings.toString(_actualMaxLockWeeksCount),
                " weeks max "
            )));
        }

        uint256 _xpIncrease = calculateXpIncrease(weeksCount_);

        uint256 _lockedUntilTimestamp = _baseTimestamp + weeksToSeconds(weeksCount_);

        lockedUntil[tokenId_] = _lockedUntilTimestamp;

        sharks.increaseXp(
            tokenId_,
            _xpIncrease
        );

        emit Relocked(
            tokenId_,
            _lockedUntilTimestamp,
            _xpIncrease
        );
    }

    function unlock(uint256 tokenId_) public onlySharkOwner(tokenId_) {
        require(lockedUntil[tokenId_] > 0, "SharksLocking: not locked");
        require(block.timestamp > lockedUntil[tokenId_], "SharksLocking: cannot unlock yet");

        uint256 _lockedForWeeksCount = (lockedUntil[tokenId_] - lockedAt[tokenId_]) / WEEK;

        lockedAt[tokenId_] = 0;
        lockedUntil[tokenId_] = 0;

        emit Unlocked(
            tokenId_,
            _lockedForWeeksCount
        );
    }

    function updateLock(uint256 tokenId_, uint256 lockedAt_, uint256 lockedUntil_) public onlyRole(LOCK_MANAGER) {
        lockedAt[tokenId_] = lockedAt_;
        lockedUntil[tokenId_] = lockedUntil_;

        emit LockUpdated(
            tokenId_,
            lockedAt_,
            lockedUntil_,
            msg.sender
        );
    }

    function setXpPerWeek(uint256 xpPerWeek_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        xpPerWeek = xpPerWeek_;
        emit XpPerWeekChanged(xpPerWeek);
    }

    function setMaxLockWeeksCount(uint256 maxLockWeeksCount_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        maxLockWeeksCount = maxLockWeeksCount_;
        emit MaxLockWeeksCountChanged(maxLockWeeksCount);
    }

    function sharkCanBeTransferred(uint tokenId_) public view returns (bool) {
        if (lockedUntil[tokenId_] == 0) {
            return true;
        } else {
            return false;
        }
    }

    function calculateXpIncrease(uint256 weeksCount_) public view returns (uint256) {
        return weeksCount_ * xpPerWeek;
    }

    function weeksToSeconds(uint256 weeksCount_) public pure returns (uint256) {
        return weeksCount_ * WEEK;
    }
}

