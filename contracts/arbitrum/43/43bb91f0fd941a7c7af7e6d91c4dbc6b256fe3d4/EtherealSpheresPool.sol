// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./ERC721Holder.sol";
import "./ReentrancyGuard.sol";
import "./AccessControl.sol";
import "./SafeERC20.sol";
import "./EnumerableSet.sol";
import "./IERC721.sol";

import "./IEtherealSpheresPool.sol";

contract EtherealSpheresPool is IEtherealSpheresPool, ERC721Holder, ReentrancyGuard, AccessControl {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;
    
    uint256 public constant REWARDS_DURATION = 7 days;
    bytes32 public constant REWARD_PROVIDER_ROLE = keccak256("REWARD_PROVIDER_ROLE");

    uint256 public totalStake;
    uint256 public rewardRate;
    uint256 public storedRewardPerToken;
    uint256 public lastUpdateTime;
    uint256 public periodFinish;
    IERC721 public immutable etherealSpheres;
    IERC20 public immutable weth;

    EnumerableSet.AddressSet private _stakers;

    mapping(address => uint256) public stakeByAccount;
    mapping(address => uint256) public storedRewardByAccount;
    mapping(address => uint256) public rewardPerTokenPaidByAccount;
    mapping(address => EnumerableSet.UintSet) private _stakedTokenIdsByAccount;

    /// @param etherealSpheres_ EtherealSpheres contract address.
    /// @param weth_ WrappedEther contract address.
    /// @param feeConverter_ FeeConverter contract address.
    /// @param royaltyDistributor_ RoyaltyDistributor contract address.
    constructor(IERC721 etherealSpheres_, IERC20 weth_, address feeConverter_, address royaltyDistributor_) {
        etherealSpheres = etherealSpheres_;
        weth = weth_;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(REWARD_PROVIDER_ROLE, msg.sender);
        _grantRole(REWARD_PROVIDER_ROLE, feeConverter_);
        _grantRole(REWARD_PROVIDER_ROLE, royaltyDistributor_);
    }

    /// @inheritdoc IEtherealSpheresPool
    function provideReward(uint256 reward_) external onlyRole(REWARD_PROVIDER_ROLE) {
        _updateReward(address(0));
        if (block.timestamp >= periodFinish) {
            unchecked {
                rewardRate = reward_ / REWARDS_DURATION;
            }
        } else {
            unchecked {
                uint256 leftover = (periodFinish - block.timestamp) * rewardRate;
                rewardRate = (reward_ + leftover) / REWARDS_DURATION;
            }
        }
        if (rewardRate > weth.balanceOf(address(this)) / REWARDS_DURATION) {
            revert ProvidedRewardTooHigh();
        }
        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + REWARDS_DURATION;
        emit RewardProvided(reward_);
    }   

    /// @inheritdoc IEtherealSpheresPool
    function stake(uint256[] calldata tokenIds_) external {
        if (tokenIds_.length == 0) {
            revert InvalidArrayLength();
        }
        _updateReward(msg.sender);
        IERC721 m_etherealSpheres = etherealSpheres;
        for (uint256 i = 0; i < tokenIds_.length; ) {
            m_etherealSpheres.safeTransferFrom(msg.sender, address(this), tokenIds_[i]);
            _stakedTokenIdsByAccount[msg.sender].add(tokenIds_[i]);
            unchecked {
                i++;
            }
        }
        unchecked {
            totalStake += tokenIds_.length;
            stakeByAccount[msg.sender] += tokenIds_.length;
        }
        if (!_stakers.contains(msg.sender)) {
            _stakers.add(msg.sender);
        }
        emit Staked(msg.sender, tokenIds_);
    }

    /// @inheritdoc IEtherealSpheresPool
    function exit() external {
        uint256 length = _stakedTokenIdsByAccount[msg.sender].length();
        if (length == 0) {
            revert InvalidArrayLength();
        }
        uint256[] memory stakedTokenIdsByAccount = new uint256[](length);
        for (uint256 i = 0; i < length; ) {
            stakedTokenIdsByAccount[i] = _stakedTokenIdsByAccount[msg.sender].at(i);
            unchecked {
                i++;
            }
        }
        withdraw(stakedTokenIdsByAccount);
        getReward();
    }

    /// @inheritdoc IEtherealSpheresPool
    function getStakedTokenIdByAccountAt(address account_, uint256 index_) external view returns (uint256) {
        return _stakedTokenIdsByAccount[account_].at(index_);
    }

    /// @inheritdoc IEtherealSpheresPool
    function isStaker(address account_) external view returns (bool) {
        return _stakers.contains(account_);
    }

    /// @inheritdoc IEtherealSpheresPool
    function stakersLength() external view returns (uint256) {
        return _stakers.length();
    }

    /// @inheritdoc IEtherealSpheresPool
    function stakerAt(uint256 index_) external view returns (address) {
        return _stakers.at(index_);
    }

    /// @inheritdoc IEtherealSpheresPool
    function withdraw(uint256[] memory tokenIds_) public {
        if (tokenIds_.length == 0) {
            revert InvalidArrayLength();
        }
        _updateReward(msg.sender);
        IERC721 m_etherealSpheres = etherealSpheres;
        for (uint256 i = 0; i < tokenIds_.length; ) {
            if (!_stakedTokenIdsByAccount[msg.sender].contains(tokenIds_[i])) {
                revert IncorrectOwner(tokenIds_[i]);
            }
            m_etherealSpheres.safeTransferFrom(address(this), msg.sender, tokenIds_[i]);
            _stakedTokenIdsByAccount[msg.sender].remove(tokenIds_[i]);
            unchecked {
                i++;
            }
        }
        unchecked {
            totalStake -= tokenIds_.length;
            stakeByAccount[msg.sender] -= tokenIds_.length;
        }
        if (stakeByAccount[msg.sender] == 0) {
            _stakers.remove(msg.sender);
        }
        emit Withdrawn(msg.sender, tokenIds_);
    }

    /// @inheritdoc IEtherealSpheresPool
    function getReward() public nonReentrant {
        _updateReward(msg.sender);
        uint256 reward = storedRewardByAccount[msg.sender];
        if (reward > 0) {
            storedRewardByAccount[msg.sender] = 0;
            weth.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    /// @inheritdoc IEtherealSpheresPool
    function lastTimeRewardApplicable() public view returns (uint256) {
        uint256 m_periodFinish = periodFinish;
        return block.timestamp < m_periodFinish ? block.timestamp : m_periodFinish;
    }

    /// @inheritdoc IEtherealSpheresPool
    function rewardPerToken() public view returns (uint256) {
        uint256 m_totalStake = totalStake;
        if (m_totalStake == 0) {
            return storedRewardPerToken;
        }
        return
            (lastTimeRewardApplicable() - lastUpdateTime)
            * rewardRate
            * 1e18
            / m_totalStake
            + storedRewardPerToken;
    }

    /// @inheritdoc IEtherealSpheresPool
    function earned(address account_) public view returns (uint256) {
        return
            stakeByAccount[account_]
            * (rewardPerToken() - rewardPerTokenPaidByAccount[account_])
            / 1e18
            + storedRewardByAccount[account_];
    }

    /// @notice Updates the earned reward by `account_`.
    /// @param account_ Account address.
    function _updateReward(address account_) private {
        storedRewardPerToken = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account_ != address(0)) {
            storedRewardByAccount[account_] = earned(account_);
            rewardPerTokenPaidByAccount[account_] = storedRewardPerToken;
        }
    }
}
