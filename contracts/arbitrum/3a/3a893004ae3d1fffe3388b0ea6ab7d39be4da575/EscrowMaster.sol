// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./SafeMath.sol";
import "./ReentrancyGuard.sol";
import "./Ownable.sol";
import "./IEscrowMaster.sol";

contract EscrowMaster is ReentrancyGuard, Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct LockedReward {
        uint256 locked;
        uint256 timestamp;
    }
    // ----------- Events -----------

    event Lock(address indexed user, uint256 amount);
    event Claim(address indexed user, uint256 amount);

    // XMS token, or may be other token
    IERC20 public vestingToken;

    mapping(address => LockedReward[]) public userLockedRewards;

    uint256 public constant PERIOD = 3 days;

    uint256 public constant LOCKEDPERIODAMOUNT = 39;

    uint256 public totalLockedRewards;

    mapping(address => bool) public operators;

    modifier onlyOperator() {
        require(operators[msg.sender], "not operator");
        _;
    }

    constructor(address _vestingToken) {
        require(
            _vestingToken != address(0),
            "EscrowMaster::constructor: Zero address"
        );
        vestingToken = IERC20(_vestingToken);
        operators[msg.sender] = true;
    }

    function setOperator(address _operator) public onlyOwner {
        operators[_operator] = true;
    }

    function lock(address account, uint256 amount) public onlyOperator {
        LockedReward[] memory oldLockedRewards = userLockedRewards[account];
        uint256 currentTimestamp = block.timestamp;
        LockedReward memory lockedReward;
        uint256 claimableAmount;
        uint256 i = 0;
        for (; i < oldLockedRewards.length; ) {
            lockedReward = oldLockedRewards[i];
            if (
                lockedReward.locked > 0 &&
                currentTimestamp >= lockedReward.timestamp
            ) {
                claimableAmount = claimableAmount.add(lockedReward.locked);
                delete oldLockedRewards[i];
            }
            unchecked {
                ++i;
            }
        }

        uint256 newStartTimestamp = (currentTimestamp / PERIOD) * PERIOD;
        uint256 newTimestamp;
        LockedReward memory newLockedReward;
        uint256 jj = 0;
        delete userLockedRewards[account];
        if (claimableAmount > 0) {
            userLockedRewards[account].push(
                LockedReward({
                    locked: claimableAmount,
                    timestamp: newStartTimestamp
                })
            );
        }

        for (i = 0; i < LOCKEDPERIODAMOUNT; i++) {
            newTimestamp = newStartTimestamp.add((i + 1) * PERIOD);
            newLockedReward = LockedReward({
                locked: amount / LOCKEDPERIODAMOUNT,
                timestamp: newTimestamp
            });
            for (uint256 j = jj; j < oldLockedRewards.length; j++) {
                lockedReward = oldLockedRewards[j];
                if (lockedReward.timestamp == newTimestamp) {
                    newLockedReward.locked = newLockedReward.locked.add(
                        lockedReward.locked
                    );
                    jj = j + 1;
                    break;
                }
            }
            userLockedRewards[account].push(newLockedReward);
        }
        totalLockedRewards = totalLockedRewards.add(amount);
        emit Lock(account, amount);
    }

    function claim() public {
        LockedReward[] storage lockedRewards = userLockedRewards[msg.sender];
        uint256 currentTimestamp = block.timestamp;
        LockedReward memory lockedReward;
        uint256 claimableAmount;
        uint256 i = 0;
        for (; i < lockedRewards.length; ) {
            lockedReward = lockedRewards[i];
            if (
                lockedReward.locked > 0 &&
                currentTimestamp > lockedReward.timestamp
            ) {
                claimableAmount = claimableAmount.add(lockedReward.locked);
                delete lockedRewards[i];
            }
            unchecked {
                ++i;
            }
        }
        totalLockedRewards = totalLockedRewards.sub(claimableAmount);
        vestingToken.safeTransfer(msg.sender, claimableAmount);
        emit Claim(msg.sender, claimableAmount);
    }

    function getVestingAmount()
        public
        view
        returns (uint256 lockedAmount, uint256 claimableAmount)
    {
        LockedReward[] memory lockedRewards = userLockedRewards[msg.sender];
        uint256 currentTimestamp = block.timestamp;
        LockedReward memory lockedReward;
        for (uint256 i = 0; i < lockedRewards.length; i++) {
            lockedReward = lockedRewards[i];
            if (currentTimestamp > lockedReward.timestamp) {
                claimableAmount = claimableAmount.add(lockedReward.locked);
            } else {
                lockedAmount = lockedAmount.add(lockedReward.locked);
            }
        }
    }
}

