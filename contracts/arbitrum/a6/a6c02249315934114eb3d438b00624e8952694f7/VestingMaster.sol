// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./ReentrancyGuard.sol";
import "./SafeERC20.sol";

contract VestingMaster is ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct LockedReward {
        uint256 locked;
        uint256 timestamp;
    }

    IERC20 public immutable vestingToken;

    mapping(address => LockedReward[]) public userLockedRewards;

    uint256 public immutable period;

    uint256 public immutable lockedPeriodAmount;

    uint256 public totalLockedRewards;

    address public immutable MasterChef;

    event Lock(address indexed user, uint256 amount);
    event Claim(address indexed user, uint256 amount);

    modifier OnlyMasterChef() {
        require(msg.sender == MasterChef, "Not MasterChef");
        _;
    }

    constructor(
        address _MasterChef,
        uint256 _period,
        uint256 _lockedPeriodAmount,
        address _vestingToken
    ) {
        require(_vestingToken != address(0), "VestingMaster::constructor: Zero address");
        require(_period > 0, "VestingMaster::constructor: Period zero");
        require(_lockedPeriodAmount > 0, "VestingMaster::constructor: Period amount zero");
        MasterChef = _MasterChef;
        vestingToken = IERC20(_vestingToken);
        period = _period;
        lockedPeriodAmount = _lockedPeriodAmount;
    }

    function lock(address account, uint256 amount) external OnlyMasterChef nonReentrant {
        LockedReward[] memory oldLockedRewards = userLockedRewards[account];
        uint256 currentTimestamp = block.timestamp;
        LockedReward memory lockedReward;
        uint256 claimableAmount;
        for (uint256 i = 0; i < oldLockedRewards.length; i++) {
            lockedReward = oldLockedRewards[i];
            if (lockedReward.locked > 0 && currentTimestamp >= lockedReward.timestamp) {
                claimableAmount += lockedReward.locked;
                delete oldLockedRewards[i];
            }
        }

        uint256 newStartTimestamp = (currentTimestamp / period) * period;
        uint256 newTimestamp;
        LockedReward memory newLockedReward;
        uint256 jj = 0;
        delete userLockedRewards[account];
        if (claimableAmount > 0) {
            userLockedRewards[account].push(LockedReward({locked: claimableAmount, timestamp: newStartTimestamp}));
        }
        uint256 lockedAmount; // Deal with loss of precision.
        for (uint256 i = 0; i < lockedPeriodAmount; i++) {
            newTimestamp = newStartTimestamp + ((i + 1) * period);
            uint256 lockAmount = amount / lockedPeriodAmount;
            if (i < lockedPeriodAmount - 1) {
                lockedAmount += lockAmount;
            } else {
                lockAmount = amount - lockedAmount;
            }
            newLockedReward = LockedReward({locked: lockAmount, timestamp: newTimestamp});
            for (uint256 j = jj; j < oldLockedRewards.length; j++) {
                lockedReward = oldLockedRewards[j];
                if (lockedReward.timestamp == newTimestamp) {
                    newLockedReward.locked += lockedReward.locked;
                    jj = j + 1;
                    break;
                }
            }
            userLockedRewards[account].push(newLockedReward);
        }
        totalLockedRewards += amount;
        emit Lock(account, amount);
    }

    function claim() external nonReentrant {
        LockedReward[] storage lockedRewards = userLockedRewards[msg.sender];
        uint256 currentTimestamp = block.timestamp;
        LockedReward memory lockedReward;
        uint256 claimableAmount;
        for (uint256 i = 0; i < lockedRewards.length; i++) {
            lockedReward = lockedRewards[i];
            if (lockedReward.locked > 0 && currentTimestamp > lockedReward.timestamp) {
                claimableAmount += lockedReward.locked;
                delete lockedRewards[i];
            }
        }
        totalLockedRewards -= claimableAmount;
        vestingToken.safeTransfer(msg.sender, claimableAmount);
        emit Claim(msg.sender, claimableAmount);
    }

    function getVestingAmount() public view returns (uint256 lockedAmount, uint256 claimableAmount) {
        LockedReward[] memory lockedRewards = userLockedRewards[msg.sender];
        uint256 currentTimestamp = block.timestamp;
        LockedReward memory lockedReward;
        for (uint256 i = 0; i < lockedRewards.length; i++) {
            lockedReward = lockedRewards[i];
            if (currentTimestamp > lockedReward.timestamp) {
                claimableAmount += lockedReward.locked;
            } else {
                lockedAmount += lockedReward.locked;
            }
        }
    }
}

