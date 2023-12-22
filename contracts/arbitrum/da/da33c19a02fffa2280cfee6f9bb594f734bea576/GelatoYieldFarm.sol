// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

import { Initializable } from "./Initializable.sol";
import { ReentrancyGuardUpgradeable } from "./ReentrancyGuardUpgradeable.sol";
import { AccessControlUpgradeable } from "./AccessControlUpgradeable.sol";
import { IERC20Upgradeable } from "./IERC20Upgradeable.sol";
import { SafeERC20Upgradeable } from "./SafeERC20Upgradeable.sol";
import { AddressUpgradeable } from "./AddressUpgradeable.sol";

interface IPlatformTreasury {
    function setOperator(address _operator) external;

    function withdrawTo(address _token, uint256 _amountOut, address _recipient) external;
}

interface IParticipant {
    function distribute(address _rewardToken, uint256 _rewards) external;

    function setDistributor(address _distributor) external;
}

contract GelatoYieldFarm is AccessControlUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address;

    bytes32 public constant GELATO_ROLE = keccak256("GELATO_ROLE");

    address public platformTreasury;
    address public rewardToken;

    uint256 public lastHarvestTime;
    uint256 public lastHarvestRewards;
    uint256 public duration;
    uint256 public periodFinish = 0;
    uint256 public rewardRate = 0;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;

    uint256 private _totalIndex;
    uint256 private _totalWeight;
    mapping(address => uint256) private _weights;
    mapping(uint256 => address) private _indexToAddress;

    mapping(address => uint256) public rewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    event AddParticipant(address indexed _recipient, uint256 _weight, uint256 _totalWeight);
    event UpdateParticipant(address indexed _recipient, uint256 _oldWeight, uint256 _newWeight, uint256 _totalWeight);
    event Harvest(uint256 _reward, uint256 _timestamp, uint256 _blk);
    event Distribute(address indexed _recipient, uint256 _reward);

    modifier updateReward(address _recipient) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();

        if (_recipient != address(0)) {
            rewards[_recipient] = pendingRewards(_recipient);
            rewardPerTokenPaid[_recipient] = rewardPerTokenStored;
        }
        _;
    }

    // @custom:oz-upgrades-unsafe-allow constructor
    // solhint-disable-next-line no-empty-blocks
    constructor() initializer {}

    // solhint-disable-next-line no-empty-blocks
    receive() external payable {}

    /// @notice used to initialize the contract
    function initialize(address _owner, address _platformTreasury, address _rewardToken) external initializer {
        require(_owner != address(0), "GelatoYieldFarm: _owner cannot be 0x0");
        require(_platformTreasury != address(0), "GelatoYieldFarm: _platformTreasury cannot be 0x0");

        __ReentrancyGuard_init();
        __AccessControl_init();
        __ReentrancyGuard_init();

        _setupRole(DEFAULT_ADMIN_ROLE, _owner);
        _grantRole(GELATO_ROLE, _owner);

        platformTreasury = _platformTreasury;
        rewardToken = _rewardToken;
        duration = 7 days;
    }

    function totalWeight() public view returns (uint256) {
        return _totalWeight;
    }

    function weightOf(address _recipient) public view returns (uint256) {
        return _weights[_recipient];
    }

    function addParticipant(address _recipient, uint256 _weight) public updateReward(_recipient) onlyRole(DEFAULT_ADMIN_ROLE) {
        _weights[_recipient] += _weight;
        _totalWeight += _weight;
        _indexToAddress[_totalIndex] = _recipient;
        _totalIndex++;

        emit AddParticipant(_recipient, _weight, totalWeight());
    }

    function updateParticipant(address _recipient, uint256 _newWeight) public updateReward(_recipient) onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 oldWeight = _weights[_recipient];

        _totalWeight -= oldWeight;
        _totalWeight += _newWeight;

        _weights[_recipient] = _newWeight;

        emit UpdateParticipant(_recipient, oldWeight, _newWeight, totalWeight());
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return _min(block.timestamp, periodFinish);
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalWeight() == 0) {
            return rewardPerTokenStored;
        }

        return rewardPerTokenStored + ((lastTimeRewardApplicable() - lastUpdateTime) * rewardRate * 1e18) / totalWeight();
    }

    function pendingRewards(address _recipient) public view returns (uint256) {
        return (weightOf(_recipient) * (rewardPerToken() - rewardPerTokenPaid[_recipient])) / 1e18 + rewards[_recipient];
    }

    function _distribute(address _recipient) internal updateReward(_recipient) {
        uint256 reward = rewards[_recipient];

        if (reward > 0) {
            rewards[_recipient] = 0;

            _approve(rewardToken, _recipient, reward);
            IParticipant(_recipient).distribute(rewardToken, reward);

            emit Distribute(_recipient, reward);
        }
    }

    function distribute() public nonReentrant onlyRole(GELATO_ROLE) {
        for (uint256 i = 0; i < _totalIndex; i++) {
            _distribute(_indexToAddress[i]);
        }
    }

    function harvest() public nonReentrant onlyRole(GELATO_ROLE) updateReward(address(0)) {
        require(block.timestamp >= lastHarvestTime + duration, "Not ready for harvest yet");

        uint256 reward = IERC20Upgradeable(rewardToken).balanceOf(platformTreasury);

        if (reward > 0) {
            IPlatformTreasury(platformTreasury).withdrawTo(rewardToken, reward, address(this));

            if (block.timestamp >= periodFinish) {
                rewardRate = reward / duration;
            } else {
                uint256 remaining = periodFinish - block.timestamp;
                uint256 leftover = remaining * rewardRate;
                rewardRate = (reward + leftover) / duration;
            }

            lastHarvestRewards = reward;
            lastUpdateTime = block.timestamp;
            lastHarvestTime = block.timestamp;
            periodFinish = block.timestamp + duration;

            emit Harvest(reward, block.timestamp, block.number);
        }
    }

    function _approve(address _token, address _spender, uint256 _amount) internal {
        IERC20Upgradeable(_token).safeApprove(_spender, 0);
        IERC20Upgradeable(_token).safeApprove(_spender, _amount);
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}

