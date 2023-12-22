//SPDX-License-Identifier: MIT
import "./Ownable.sol";
import "./Pausable.sol";

import "./IEpochBasedLimiter.sol";

pragma solidity 0.8.17;

abstract contract EpochBasedLimiter is Ownable, Pausable, IEpochBasedLimiter {
    
    // Constants
    uint public constant MIN_EPOCH_DURATION = 30 minutes;
    uint public constant MAX_EPOCH_DURATION = 1 weeks;
    uint public immutable MAX_EPOCH_LIMIT;

    // Epoch params
    uint public epochDuration;
    uint public epochLimit;

    // Epoch state
    uint public currentEpoch;
    uint public currentEpochStart;
    uint public currentEpochCount;

    // Blacklist
    mapping(address => bool) public blacklist;

    // Events
    event EpochDurationUpdated(uint epochDuration);
    event EpochLimitUpdated(uint epochLimit);
    event EpochStarted(uint indexed epochId, uint epochStart);
    event Blacklisted(address indexed receiver, bool isBlacklisted);

    constructor(
        address _owner,
        uint _maxEpochLimit,
        uint _epochDuration,
        uint _epochLimit
    ) {
        require(
            _owner != address(0) &&
            _maxEpochLimit > 0 &&
            _epochDuration >= MIN_EPOCH_DURATION &&
            _epochDuration <= MAX_EPOCH_DURATION &&
            _epochLimit <= _maxEpochLimit,
            "WRONG_PARAMS"
        );

        MAX_EPOCH_LIMIT = _maxEpochLimit;

        epochDuration = _epochDuration;
        epochLimit = _epochLimit;

        currentEpoch = 1;
        currentEpochStart = block.timestamp;

        _transferOwnership(_owner);
    }

    // @notice Pause functions
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // @dev Updates duration of epoch in seconds
    function updateEpochDuration(uint _epochDuration) external onlyOwner {
        require(
            _epochDuration >= MIN_EPOCH_DURATION && _epochDuration <= MAX_EPOCH_DURATION,
            "INVALID_EPOCH_DURATION"
        );
        epochDuration = _epochDuration;

        emit EpochDurationUpdated(_epochDuration);
    }

    // @dev Update epoch limit
    function updateEpochLimit(uint _epochLimit) external onlyOwner {
        require(_epochLimit <= MAX_EPOCH_LIMIT, "INVALID_EPOCH_LIMIT");
        epochLimit = _epochLimit;

        emit EpochLimitUpdated(_epochLimit);
    }

    // @dev Adds address to blacklist. Prevents minting, burning, and using pending claims.
    function blacklistReceiver(address receiver, bool blacklisted) external onlyOwner {
        blacklist[receiver] = blacklisted;
        emit Blacklisted(receiver, blacklisted);
    }

    // @dev Tries to rotate epoch window
    function tryUpdateEpoch() public {
        if (block.timestamp >= currentEpochStart + epochDuration) {
            currentEpoch ++;
            currentEpochStart = block.timestamp;
            currentEpochCount = 0;
            
            emit EpochStarted(currentEpoch, currentEpochStart);
        }
    }
}

