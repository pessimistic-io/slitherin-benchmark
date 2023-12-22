// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./SafeERC20Upgradeable.sol";
import "./ContextUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./CountersUpgradeable.sol";
import "./AddressUpgradeable.sol";
import "./ERC721Upgradeable.sol";
import "./ERC721EnumerableUpgradeable.sol";
import "./Initializable.sol";
import "./IStakingHubPositionManager.sol";
import "./IStakingHubNFTDescriptor.sol";

contract StakingHub is
    Initializable,
    ERC721Upgradeable,
    ERC721EnumerableUpgradeable,
    IStakingHubPositionManager,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using CountersUpgradeable for CountersUpgradeable.Counter;
    using AddressUpgradeable for address;

    address public token;
    address public tokenDescriptor;
    uint256 public undispatchedReward;
    uint256 public constant TWO_WEEKS_IN_SECONDS = 1209600;
    uint8 public constant LOW_TIER_RATIO = 20;
    uint8 public constant HIGH_TIER_RATIO = 80;

    CountersUpgradeable.Counter internal _stakingPositionCounter;

    mapping(uint256 => StakingPosition) internal _stakingPositions;

    struct OwnerPosition {
        uint256 id;
        uint256 amount;
        string jsonURI;
    }

    /**
     * @notice Staked event is triggered whenever a token holder create a new staking position
     * @param staker Address of the staker
     * @param amount Number of tokens staked
     * @param stakingPositionId The Id of the staking position that was created
     * @param unclaimedReward How much reward the staking position can claim
     * @param createdAt Time when tokens are staked
     * @param updatedAt Last update of the staking position
     *
     */
    event Staked(
        address indexed staker,
        uint256 amount,
        uint256 indexed stakingPositionId,
        uint256 unclaimedReward,
        uint256 createdAt,
        uint256 updatedAt
    );

    /**
     * @notice Unstaked event is triggered whenever the owner of the staking position want to unstake his tokens
     * @param staker Address of the staking position owner
     * @param amount Number of token unstaked
     * @param stakingPositionId Id of the staking position being unstaked
     * @param claimedAmount How much the staking position has claimed
     * @param updatedAt Time when token where unstaked
     *
     */
    event Unstaked(
        address indexed staker,
        uint256 amount,
        uint256 indexed stakingPositionId,
        uint256 claimedAmount,
        uint256 updatedAt
    );

    /**
     * @notice DispatchReward event fired every time reward funds are dispatched between staking position
     * @param amount The value of the reward to dispatch
     * @param receiveTime The time at which reward funds are received
     */
    event RewardDispatched(uint256 amount, uint256 receiveTime);

    /**
     * @notice Claim event fired every time a staker claim reward from his staking position
     * @param staker The address of the owner of the staking position
     * @param stakingPositionId The id of the staking position
     * @param amount How much was paid
     * @param claimTime The time at which the withdrawal was made
     */
    event Claim(
        address indexed staker,
        uint256 stakingPositionId,
        uint256 amount,
        uint256 claimTime
    );

    /**
     * @notice ClaimAll event fired when owner of multiple staking positions claim all the positions rewards at once
     * @param staker The address of the owner
     * @param stakingPositions An array of staking position ids
     * @param totalRewards The total amount of all unclaimed rewards for all owner's positions
     * @param claimTime The time at which the withdrawal was made
     */
    event ClaimAll(
        address staker,
        uint256[] stakingPositions,
        uint256 totalRewards,
        uint256 claimTime
    );

    modifier onlyPositionOwner(uint256 id) {
        require(_msgSender() == _ownerOf(id), 'Not the owner');
        _;
    }

    modifier onlyActivePosition(uint256 id) {
        require(_stakingPositions[id].amount > 0, 'Empty staking position');
        _;
    }

    modifier onlyExist(uint256 tokenId) {
        require(_exists(tokenId), 'Invalid token id');
        _;
    }

    function initialize(
        string memory name_,
        string memory symbol_,
        address token_
    ) public initializer {
        __ERC721_init(name_, symbol_);
        __ERC721Enumerable_init();
        __Pausable_init();
        __Ownable_init();
        token = token_;
        undispatchedReward = 0;
    }

    function stake(uint256 amount_) external whenNotPaused returns (uint256 stakingPositionId) {
        require(amount_ > 0, 'Staking amount must be higher than 0');
        require(
            IERC20Upgradeable(address(token)).balanceOf(_msgSender()) >= amount_,
            'Insufficient token balance'
        );
        require(
            IERC20Upgradeable(address(token)).allowance(_msgSender(), address(this)) >= amount_,
            'Token allowance must be increased'
        );

        _stakingPositionCounter.increment();
        stakingPositionId = _stakingPositionCounter.current();
        StakingPosition storage newStakingPosition = _stakingPositions[stakingPositionId];
        newStakingPosition.amount = amount_;
        newStakingPosition.unclaimedReward = 0;
        uint256 stakingTime = block.timestamp;
        newStakingPosition.createdAt = stakingTime;
        newStakingPosition.updatedAt = stakingTime;
        IERC20Upgradeable(address(token)).safeTransferFrom(_msgSender(), address(this), amount_);
        _safeMint(_msgSender(), stakingPositionId);

        emit Staked(_msgSender(), amount_, stakingPositionId, 0, stakingTime, stakingTime);
    }

    function unstake(
        uint256 stakingPositionId
    )
        external
        nonReentrant
        whenNotPaused
        onlyActivePosition(stakingPositionId)
        onlyPositionOwner(stakingPositionId)
        onlyExist(stakingPositionId)
        returns (uint256 stakedAmount, uint256 unclaimedReward)
    {
        StakingPosition storage stakingPositionToRemove = _stakingPositions[stakingPositionId];
        stakedAmount = stakingPositionToRemove.amount;
        unclaimedReward = stakingPositionToRemove.unclaimedReward;
        uint256 updatedTime = block.timestamp;
        if (unclaimedReward > 0) {
            stakingPositionToRemove.unclaimedReward = 0;
            payable(_msgSender()).transfer(unclaimedReward);
            emit Claim(_msgSender(), stakingPositionId, unclaimedReward, updatedTime);
        }
        stakingPositionToRemove.amount = 0;
        stakingPositionToRemove.updatedAt = updatedTime;
        IERC20Upgradeable(address(token)).safeTransfer(_msgSender(), stakedAmount);
        emit Unstaked(_msgSender(), stakedAmount, stakingPositionId, unclaimedReward, updatedTime);
    }

    function claim(
        uint256 stakingPositionId
    )
        external
        nonReentrant
        whenNotPaused
        onlyActivePosition(stakingPositionId)
        onlyPositionOwner(stakingPositionId)
        onlyExist(stakingPositionId)
    {
        require(_msgSender() != address(0), 'Cannot be zero address');
        StakingPosition storage stakingPosition = _stakingPositions[stakingPositionId];
        uint256 amountClaimed = stakingPosition.unclaimedReward;
        if (amountClaimed > 0) {
            stakingPosition.unclaimedReward = 0;
            stakingPosition.updatedAt = block.timestamp;
            payable(_msgSender()).transfer(amountClaimed);
            emit Claim(_msgSender(), stakingPositionId, amountClaimed, block.timestamp);
        }
    }

    function claimAll() external nonReentrant whenNotPaused {
        require(_msgSender() != address(0), 'Cannot be zero address');
        uint256 numberOfPositions = balanceOf(_msgSender());
        if (numberOfPositions > 0) {
            uint256[] memory arrStakingPositionIds = new uint256[](numberOfPositions);
            uint256 totalRewards = 0;
            for (uint256 i = 0; i < numberOfPositions; i++) {
                uint256 stakingPositionId = tokenOfOwnerByIndex(_msgSender(), i);
                StakingPosition storage stakingPosition = _stakingPositions[stakingPositionId];
                if (stakingPosition.unclaimedReward > 0) {
                    totalRewards += stakingPosition.unclaimedReward;
                    stakingPosition.unclaimedReward = 0;
                    stakingPosition.updatedAt = block.timestamp;
                }
                arrStakingPositionIds[i] = stakingPositionId;
            }
            if (totalRewards > 0) {
                payable(_msgSender()).transfer(totalRewards);
                emit ClaimAll(_msgSender(), arrStakingPositionIds, totalRewards, block.timestamp);
            }
        }
    }

    function createReward() external payable {
        require(msg.value > 0, 'Amount must be higher than 0');
        uint256 reward = msg.value;
        uint256 receivedAt = block.timestamp;
        // wait until at least 0.01 ether in dust has been reached before adding
        if (undispatchedReward > 0.01 ether && address(this).balance == undispatchedReward) {
            reward += undispatchedReward;
            undispatchedReward = 0;
        }
        undispatchedReward = _dispatchRewardBetweenStakingPositions(reward, receivedAt);
        emit RewardDispatched(msg.value, receivedAt);
    }

    function setDescriptor(address descriptor) external onlyOwner {
        tokenDescriptor = descriptor;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function getStakingPosition(
        uint256 tokenId
    ) public view override onlyExist(tokenId) returns (StakingPosition memory stakingPosition) {
        stakingPosition = _stakingPositions[tokenId];
    }

    function tokenURI(
        uint256 tokenId
    ) public view override(ERC721Upgradeable) returns (string memory) {
        return IStakingHubNFTDescriptor(tokenDescriptor).tokenURI(address(this), tokenId);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC721Upgradeable, ERC721EnumerableUpgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function totalSupply() public view override returns (uint256) {
        return _stakingPositionCounter.current();
    }

    function getPositionsOf(address positionOwner) public view returns (OwnerPosition[] memory) {
        uint256 numberOfPositions = balanceOf(positionOwner);
        OwnerPosition[] memory positions = new OwnerPosition[](numberOfPositions);
        //get all token ids
        for (uint256 i = 0; i < numberOfPositions; i++) {
            uint256 tokenId = tokenOfOwnerByIndex(positionOwner, i);
            StakingPosition memory sPosition = getStakingPosition(tokenId);
            OwnerPosition memory oPosition = OwnerPosition({
                id: tokenId,
                amount: sPosition.amount,
                jsonURI: tokenURI(tokenId)
            });
            positions[i] = oPosition;
        }
        return positions;
    }

    function getTotalStakedTokensOf(
        address positionOwner
    ) public view returns (uint256 totalStakedTokens) {
        totalStakedTokens = 0;
        uint256 numberOfPositions = balanceOf(positionOwner);
        for (uint256 i = 0; i < numberOfPositions; i++) {
            uint256 tokenId = tokenOfOwnerByIndex(positionOwner, i);
            StakingPosition memory sPosition = getStakingPosition(tokenId);
            totalStakedTokens += sPosition.amount;
        }
    }

    function getUnclaimedRewardsOf(
        address positionOwner
    ) public view returns (uint256 totalUnclaimedRewards) {
        totalUnclaimedRewards = 0;
        uint256 numberOfPositions = balanceOf(positionOwner);
        for (uint256 i = 0; i < numberOfPositions; i++) {
            uint256 tokenId = tokenOfOwnerByIndex(positionOwner, i);
            StakingPosition memory sPosition = getStakingPosition(tokenId);
            totalUnclaimedRewards += sPosition.unclaimedReward;
        }
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal override(ERC721Upgradeable, ERC721EnumerableUpgradeable) whenNotPaused {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    function _dispatchRewardBetweenStakingPositions(
        uint256 amountToDispatch,
        uint256 eligibleTime
    ) internal returns (uint256) {
        uint256 totalStakingPositions = totalSupply();
        uint256 totalTokenStaked = IERC20Upgradeable(address(token)).balanceOf(address(this));
        // any staking position created before this threshold is eligible to higher reward part
        uint256 stakingTimeThreshold = eligibleTime - TWO_WEEKS_IN_SECONDS;
        uint256 fullRewardTokenBalance = _getTotalTokenStakedMoreThanTwoWeeks(stakingTimeThreshold);
        uint256 verifyRewardSum = 0;
        for (uint256 j = 1; j <= totalStakingPositions; j++) {
            StakingPosition memory currentStakingPosition = getStakingPosition(j);
            uint256 rewardingAmount = 0;
            if (currentStakingPosition.amount > 0) {
                // staking position is created less than two weeks
                if (currentStakingPosition.createdAt >= stakingTimeThreshold) {
                    rewardingAmount =
                        (((amountToDispatch * currentStakingPosition.amount) / totalTokenStaked) *
                            LOW_TIER_RATIO) /
                        100;
                } else {
                    rewardingAmount =
                        ((((amountToDispatch * currentStakingPosition.amount) / totalTokenStaked) *
                            LOW_TIER_RATIO) / 100) +
                        ((((amountToDispatch * currentStakingPosition.amount) /
                            fullRewardTokenBalance) * HIGH_TIER_RATIO) / 100);
                }
                _increaseUnclaimedReward(j, rewardingAmount);
                verifyRewardSum += rewardingAmount;
            }
        }
        if (verifyRewardSum > amountToDispatch) {
            revert('Dispatching more reward then received');
        }
        return amountToDispatch - verifyRewardSum;
    }

    function _getTotalTokenStakedMoreThanTwoWeeks(
        uint256 threshold
    ) internal view returns (uint256 total) {
        uint256 totalStakingPositions = totalSupply();
        for (uint256 i = 1; i <= totalStakingPositions; i++) {
            StakingPosition memory currentStakingPosition = getStakingPosition(i);
            if (currentStakingPosition.amount > 0) {
                // staking position is created more than two weeks
                if (currentStakingPosition.createdAt < threshold) {
                    total += currentStakingPosition.amount;
                }
            }
        }
    }

    function _increaseUnclaimedReward(uint256 stakingPositionId, uint256 amount) internal {
        StakingPosition storage stakingPosition = _stakingPositions[stakingPositionId];
        stakingPosition.unclaimedReward += amount;
        stakingPosition.updatedAt = block.timestamp;
    }
}

