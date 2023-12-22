// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./SafeERC20.sol";
import "./IERC20.sol";
import "./ExternalOwnable.sol";

contract Lock is ExternalOwnable {
    uint256 public constant Month = 30 days;
    uint256 public constant Quarter = 3 * Month;
    using SafeERC20 for IERC20;

    struct LockRecord {
        uint256 notifyTime;
        uint256 startUnLockTime;
        uint256 endUnLockTime;
        uint256 lastClaimTime;
    }

    LockRecord public record;
    uint256 public totalLockAmount;
    string public name;
    address public factory;
    uint8 public unlockType;

    constructor(
        string memory _name,
        address _factory,
        address _owner,
        uint256 _lockRangeTime,
        uint256 _finishRangeTime,
        uint8 _unlockType
    ) ExternalOwnable(_owner) {
        factory = _factory;
        name = _name;
        record.startUnLockTime = _lockRangeTime;
        record.endUnLockTime = _finishRangeTime;
        require(_unlockType == 1 || _unlockType == 2, "invalid unlock type");
        unlockType = _unlockType;
    }

    modifier onlyFactory() {
        require(factory == msg.sender, "only factory can do");
        _;
    }

    function claim(address _token) external onlyOwner {
        (uint256 amount, uint256 claimTime) = queryUnLockAmount();
        require(amount > 0, "no claim amount");
        IERC20(_token).safeTransfer(owner(), amount);
        record.lastClaimTime = claimTime;
    }

    function notify(uint256 _amount) external onlyFactory {
        totalLockAmount = _amount;
        record.notifyTime = block.timestamp;
        record.startUnLockTime += record.notifyTime;
        record.lastClaimTime = record.startUnLockTime;
        record.endUnLockTime += record.startUnLockTime;
    }

    function queryUnLockAmount() public view returns (uint256, uint256) {
        uint256 currentTime = block.timestamp;
        if (currentTime < record.startUnLockTime) {
            return (0, record.lastClaimTime);
        }

        if (currentTime >= record.endUnLockTime) {
            currentTime = record.endUnLockTime;
        }

        uint256 range = (currentTime - record.lastClaimTime) / Month;
        if (range == 0) {
            return (0, record.lastClaimTime);
        }

        uint256 rangeTime;
        if (unlockType == 1) {
            rangeTime = range * Month;
        } else {
            if (currentTime == record.endUnLockTime) {
                rangeTime = currentTime - record.lastClaimTime;
            } else {
                rangeTime = (range / 3) * Quarter;
            }
        }

        uint256 unlockAmount = (totalLockAmount /
            (record.endUnLockTime - record.startUnLockTime)) * rangeTime;

        return (unlockAmount, record.lastClaimTime + rangeTime);
    }
}

