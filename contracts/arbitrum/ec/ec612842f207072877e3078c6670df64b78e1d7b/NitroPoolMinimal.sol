// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "./SafeMath.sol";
import "./SafeERC20.sol";
import "./IERC20Metadata.sol";
import "./EnumerableSet.sol";
import "./ReentrancyGuard.sol";
import "./Ownable.sol";

import "./INitroPoolFactory.sol";
import "./INFTPool.sol";
import "./INFTHandler.sol";
import "./IProtocolToken.sol";
import "./IXToken.sol";
import "./INitroCustomReq.sol";

contract NitroPoolMinimal is ReentrancyGuard, Ownable, INFTHandler {
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20Metadata;
    using SafeERC20 for IXToken;
    using SafeERC20 for IProtocolToken;

    struct RewardInfo {
        uint256 accTokenPerShare;
        uint256 rewardPerSecond;
        uint256 startTime;
        uint256 PRECISION_FACTOR;
    }

    struct UserInfo {
        uint256 totalDepositAmount; // Save total deposit amount
    }

    struct PoolSettings {
        uint256 startTime; // Start of rewards distribution
        uint256 endTime; // End of rewards distribution
        uint256 harvestStartTime; // (optional) Time at which stakers will be allowed to harvest their rewards
        uint256 depositEndTime; // (optional) Time at which deposits won't be allowed anymore
        uint256 lockDurationReq; // (optional) required lock duration for positions
        uint256 lockEndReq; // (optional) required lock end time for positions
        uint256 depositAmountReq; // (optional) required deposit amount for positions
        bool whitelist; // (optional) to only allow whitelisted users to deposit
        string description; // Project's description for this NitroPool
    }

    uint8 public constant MAX_REWARDS = 8;

    PoolSettings public settings;

    bool public published; // Is pool published
    bool public emergencyClose; // When activated, can't distribute rewards anymore

    // Equals to `bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"))`
    // which can be also obtained as `IERC721Receiver(0).onERC721Received.selector`
    bytes4 private constant _ERC721_RECEIVED = 0x150b7a02;

    // pool info
    uint256 public totalDepositAmount;
    uint256 public lastRewardTime;

    uint256 public creationTime;
    uint256 public publishTime;

    address public treasury;

    INitroPoolFactory public factory;
    IProtocolToken public protocolToken;
    IXToken public xToken;
    INFTPool public nftPool;
    INitroCustomReq public customReqContract;

    // Rewards address Set
    EnumerableSet.AddressSet internal _rewardTokenAddresses;

    // token address => reward info
    mapping(address => RewardInfo) internal _rewardInfo;

    // Set of accounts permitted to perform reward management tasks
    EnumerableSet.AddressSet internal _operators;

    mapping(address => UserInfo) public userInfo;
    // user => token => debt
    mapping(address => mapping(address => uint256)) public userRewardDebts;
    mapping(uint256 => address) public tokenIdOwner; // save tokenId previous owner
    mapping(address => EnumerableSet.UintSet) private _userTokenIds; // save previous owner tokenIds

    // account => token => amount
    mapping(address => mapping(address => uint256)) private _userPendingRewardBuffer;

    // ======================================================================== //
    // ================================ EVENTS ================================ //
    // ======================================================================== //

    event ActivateEmergencyClose();
    event Publish();
    event Deposit(address indexed userAddress, uint256 tokenId, uint256 amount);
    event Harvest(address indexed userAddress, address rewardsToken, uint256 pending);
    event UpdatePool();
    event Withdraw(address indexed userAddress, uint256 tokenId, uint256 amount);
    event EmergencyWithdraw(address indexed userAddress, uint256 tokenId, uint256 amount);
    event WithdrawRewards(address token, uint256 amount, uint256 totalRewardsAmount);
    event OperatorAdded(address operator);
    event OperatorRemoved(address operator);
    event RewardAdded(address indexed token, uint256 startTime, uint256 rate);
    event RewardRateUpdated(address indexed token, uint256 rate);
    event RewardStartUpdated(address indexed token, uint256 newStart);
    event SetRequirements(uint256 lockDurationReq, uint256 lockEndReq, uint256 depositAmountReq, bool whitelist);
    event SetCustomReqContract(address contractAddress);

    // ======================================================================== //
    // ================================ ERRORS ================================ //
    // ======================================================================== //

    error TokenAlreadyAdded();
    error ZeroAddress(string shouldNotBeZeroAddress);
    error ArrayLengthMismatch();
    error InvalidOperator();
    error InvalidStartTime();
    error InvalidRewardStartTime();
    error InvalidEndTime();
    error ExceedsMaxTokenDecimals();
    error InvalidNFTPool();
    error InvalidOwner();
    error MaxRewardCount();
    error TokenNotAdded();
    error RewardAlreadyStarted();
    error NoRewardsAdded();
    error PoolNotStartedYet();
    error PoolAlreadyPublished();
    error PoolNotPublished();
    error InvalidDepositEndTime();
    error LockTimeEndRequirementNotMet();
    error LockDurationRequirementNotMet();
    error DepositorPoolBalanceTooLow();
    error InvalidCustomRequirement();
    error CannotHandleRewards();

    // ========================================================================== //
    // =============================== MODIFIERS ================================ //
    // ========================================================================== //

    modifier isValidNFTPool(address sender) {
        if (sender != address(nftPool)) revert InvalidNFTPool();
        _;
    }

    modifier onlyPoolOperator() {
        if (!_operators.contains(msg.sender)) revert InvalidOperator();
        _;
    }

    constructor(
        address _treasury,
        address initialOperator,
        INFTPool _nftPool,
        IERC20Metadata[] memory rewardTokens,
        uint256[] memory rewardStartTimes,
        uint256[] memory rewardsPerSecond,
        PoolSettings memory _settings,
        IProtocolToken _protocolToken,
        IXToken _xToken
    ) {
        if (_treasury == address(0) || address(_protocolToken) == address(0) || address(_xToken) == address(0)) {
            revert ZeroAddress({ shouldNotBeZeroAddress: "constructor arg zero address" });
        }
        if (_settings.startTime < block.timestamp) revert InvalidStartTime();
        if (_settings.endTime < _settings.startTime) revert InvalidEndTime();
        if (_settings.depositEndTime != 0 && _settings.startTime <= _settings.depositEndTime)
            revert InvalidDepositEndTime();

        uint256 rewardCount = rewardTokens.length;
        if (rewardStartTimes.length != rewardCount || rewardsPerSecond.length != rewardCount)
            revert ArrayLengthMismatch();

        factory = INitroPoolFactory(msg.sender);

        treasury = _treasury;
        _operators.add(initialOperator);
        nftPool = _nftPool;

        protocolToken = _protocolToken;
        xToken = _xToken;

        settings.startTime = _settings.startTime;
        settings.endTime = _settings.endTime;

        creationTime = block.timestamp;
        lastRewardTime = _settings.startTime;

        if (_settings.harvestStartTime == 0) {
            settings.harvestStartTime = _settings.startTime;
        } else {
            settings.harvestStartTime = _settings.harvestStartTime;
        }

        settings.depositEndTime = _settings.depositEndTime;
        settings.description = _settings.description;

        for (uint256 i = 0; i < rewardCount; ) {
            _addReward(rewardTokens[i], rewardStartTimes[i], rewardsPerSecond[i]);

            unchecked {
                ++i;
            }
        }

        _setRequirements(
            _settings.lockDurationReq,
            _settings.lockEndReq,
            _settings.depositAmountReq,
            _settings.whitelist
        );

        Ownable.transferOwnership(_treasury);
    }

    // ========================================================================= //
    // ================================= VIEW ================================== //
    // ========================================================================= //

    /**
     * @dev Returns the number of tokenIds from positions deposited by "account" address
     */
    function userTokenIdsLength(address account) external view returns (uint256) {
        return _userTokenIds[account].length();
    }

    /**
     * @dev Returns a position's tokenId deposited by "account" address from its "index"
     */
    function userTokenId(address account, uint256 index) external view returns (uint256) {
        return _userTokenIds[account].at(index);
    }

    function getRewardTokensInfo() external view returns (address[] memory tokens, RewardInfo[] memory rewards) {
        (address[] memory rewardAddresses, uint256 rewardCount) = _getBaseRewardsInfo();

        tokens = rewardAddresses;
        rewards = new RewardInfo[](rewardCount);

        for (uint256 i = 0; i < rewardCount; i++) {
            rewards[i] = _rewardInfo[rewardAddresses[i]];
        }
    }

    function pendingReward(
        address _user
    ) external view returns (address[] memory tokens, uint256[] memory rewardAmounts) {
        UserInfo storage user = userInfo[_user];

        (address[] memory rewardAddresses, uint256 rewardCount) = _getBaseRewardsInfo();

        tokens = rewardAddresses;
        rewardAmounts = new uint256[](rewardCount);

        // Stash loop items to reduce bytecode size
        RewardInfo memory reward;
        uint256 fromTime;
        uint256 rewardAmount;
        uint256 adjustedTokenPerShare;
        uint256 pendingForToken;
        uint256 blockTime = block.timestamp;

        // gas savings
        // Only need these combined checks once for all tokens instead of on each iteration
        bool shouldCheckRewards = blockTime > lastRewardTime && totalDepositAmount != 0;

        for (uint256 i = 0; i < rewardCount; ) {
            reward = _rewardInfo[rewardAddresses[i]];

            // Handle case of tokens added later also
            // Don't accumulate for rewards not active yet
            if (shouldCheckRewards && blockTime > reward.startTime) {
                // blockTime > reward.startTime. So reward is active at this point

                // Select proper "from" reference since tokens can be added at a later time
                // Using lastRewardTime alone would inflate/blow up the accPer for a token.
                fromTime = reward.startTime > lastRewardTime ? reward.startTime : lastRewardTime;

                rewardAmount = reward.rewardPerSecond * _getMultiplier(fromTime, blockTime);
                adjustedTokenPerShare =
                    reward.accTokenPerShare +
                    (rewardAmount * reward.PRECISION_FACTOR) /
                    totalDepositAmount;

                pendingForToken =
                    (user.totalDepositAmount * adjustedTokenPerShare) /
                    reward.PRECISION_FACTOR -
                    userRewardDebts[_user][rewardAddresses[i]];

                // Add any buffered amount for token
                pendingForToken += _userPendingRewardBuffer[_user][rewardAddresses[i]];

                rewardAmounts[i] = pendingForToken;
            } else {
                pendingForToken =
                    (user.totalDepositAmount * reward.accTokenPerShare) /
                    reward.PRECISION_FACTOR -
                    userRewardDebts[_user][rewardAddresses[i]];

                pendingForToken += _userPendingRewardBuffer[_user][rewardAddresses[i]];

                rewardAmounts[i] = pendingForToken;
            }

            unchecked {
                ++i;
            }
        }
    }

    // ========================================================================= //
    // ============================ EXTERNAL PUBLIC ============================ //
    // ========================================================================= //
    /**
     * @dev Automatically stakes transferred positions from a NFTPool
     * This acts as the sort of "deposit" function into this pool
     */
    function onERC721Received(
        address /*operator*/,
        address from,
        uint256 tokenId,
        bytes calldata /*data*/
    ) external override nonReentrant isValidNFTPool(msg.sender) returns (bytes4) {
        if (!published) revert PoolNotPublished();

        // save tokenId previous owner
        _userTokenIds[from].add(tokenId);
        tokenIdOwner[tokenId] = from;

        (uint256 amount, uint256 startLockTime, uint256 lockDuration) = _getStackingPosition(tokenId);
        _checkPositionRequirements(amount, startLockTime, lockDuration);

        _deposit(from, tokenId, amount);

        // allow depositor to interact with the staked position later
        nftPool.approve(from, tokenId);
        return _ERC721_RECEIVED;
    }

    /**
     * @dev Withdraw a position from the NitroPool
     *
     * Can only be called by the position's previous owner
     */
    function withdraw(uint256 tokenId) external virtual nonReentrant {
        if (msg.sender != tokenIdOwner[tokenId]) revert InvalidOwner();

        (uint256 amount, , ) = _getStackingPosition(tokenId);

        _updatePool();
        UserInfo storage user = userInfo[msg.sender];
        _harvest(user, msg.sender);

        user.totalDepositAmount -= amount;
        totalDepositAmount -= amount;

        _updateRewardDebt(user);

        // Remove from previous owners info
        _userTokenIds[msg.sender].remove(tokenId);
        delete tokenIdOwner[tokenId];

        nftPool.safeTransferFrom(address(this), msg.sender, tokenId);

        emit Withdraw(msg.sender, tokenId, amount);
    }

    /**
     * @dev Withdraw a position from the NitroPool without caring about rewards, EMERGENCY ONLY
     *
     * Can only be called by position's previous owner
     */
    function emergencyWithdraw(uint256 tokenId) external virtual nonReentrant {
        if (msg.sender != tokenIdOwner[tokenId]) revert InvalidOwner();

        (uint256 amount, , ) = _getStackingPosition(tokenId);
        UserInfo storage user = userInfo[msg.sender];
        user.totalDepositAmount -= amount;
        totalDepositAmount -= amount;

        _updateRewardDebt(user);

        // Remove from previous owners info
        _userTokenIds[msg.sender].remove(tokenId);
        delete tokenIdOwner[tokenId];

        nftPool.safeTransferFrom(address(this), msg.sender, tokenId);

        emit EmergencyWithdraw(msg.sender, tokenId, amount);
    }

    /**
     * @dev Harvest pending NitroPool rewards
     */
    function harvest() external nonReentrant {
        _updatePool();
        UserInfo storage user = userInfo[msg.sender];
        _harvest(user, msg.sender);
        _updateRewardDebt(user);
    }

    /**
     * @dev Allow stacked positions to be harvested
     *
     * "to" can be set to token's previous owner
     * "to" can be set to this address only if this contract is allowed to transfer xToken
     */
    function onNFTHarvest(
        address operator,
        address to,
        uint256 tokenId,
        uint256 protocolTokenAmount,
        uint256 xTokenAmount
    ) external override isValidNFTPool(msg.sender) returns (bool) {
        address _owner = tokenIdOwner[tokenId];

        if (operator != _owner) revert InvalidOperator();

        // If not whitelisted, the pool can't transfer/forward the xToken rewards owed to owner
        // require(to != address(this) || xToken.isTransferWhitelisted(address(this)), "cant handle rewards");
        if (to == address(this) && !xToken.isTransferWhitelisted(address(this))) revert CannotHandleRewards();

        // Redirect rewards to position's previous owner
        if (to == address(this)) {
            protocolToken.safeTransfer(_owner, protocolTokenAmount);
            xToken.safeTransfer(_owner, xTokenAmount);
        }

        return true;
    }

    /**
     * @dev Allow position's previous owner to add more assets to his position
     */
    function onNFTAddToPosition(
        address operator,
        uint256 tokenId,
        uint256 amount
    ) external override nonReentrant isValidNFTPool(msg.sender) returns (bool) {
        if (operator != tokenIdOwner[tokenId]) revert InvalidOperator();
        _deposit(operator, tokenId, amount);
        return true;
    }

    /**
     * @dev Disallow withdraw assets from a stacked position
     */
    function onNFTWithdraw(
        address /*operator*/,
        uint256 /*tokenId*/,
        uint256 /*amount*/
    ) external pure override returns (bool) {
        return false;
    }

    /**
     * @dev Update this NitroPool
     */
    function updatePool() external nonReentrant {
        _updatePool();
    }

    // =============================================================================== //
    // ========================= EXTERNAL OWNABLE FUNCTIONS ========================== //
    // =============================================================================== //

    /**
     * @dev Publish the Nitro Pool
     *
     * Must only be called by the owner
     */
    function publish() external onlyOwner {
        if (published) revert PoolAlreadyPublished();
        // This nitroPool is stale (Eg. publish should be called before the pools start time)
        if (settings.startTime > block.timestamp) revert PoolNotStartedYet();
        if (_rewardTokenAddresses.length() == 0) revert NoRewardsAdded();

        published = true;
        publishTime = block.timestamp;
        factory.publishNitroPool(address(nftPool));

        emit Publish();
    }

    /**
     * @dev Set an external custom requirement contract
     */
    function setCustomReqContract(address contractAddress) external onlyOwner {
        // Allow to disable customReq event if pool is published
        require(!published || contractAddress == address(0), "published");
        customReqContract = INitroCustomReq(contractAddress);

        emit SetCustomReqContract(contractAddress);
    }

    /**
     * @dev Set requirements that positions must meet to be staked on this Nitro Pool
     *
     * Must only be called by the owner
     */
    function setRequirements(
        uint256 lockDurationReq,
        uint256 lockEndReq,
        uint256 depositAmountReq,
        bool whitelist
    ) external onlyOwner {
        _setRequirements(lockDurationReq, lockEndReq, depositAmountReq, whitelist);
    }

    /**
     * @dev Emergency close
     *
     * Must only be called by the owner
     * Emergency only: if used, the whole pool is definitely made void
     * All rewards are automatically transferred to the emergency recovery address
     */
    function activateEmergencyClose() external nonReentrant onlyOwner {
        address emergencyRecoveryAddress = factory.emergencyRecoveryAddress();

        emergencyClose = true;
        emit ActivateEmergencyClose();

        (address[] memory rewardAddresses, uint256 rewardCount) = _getBaseRewardsInfo();

        for (uint256 i = 0; i < rewardCount; ) {
            IERC20Metadata token = IERC20Metadata(rewardAddresses[i]);
            _safeRewardsTransfer(token, emergencyRecoveryAddress, token.balanceOf(address(this)));

            unchecked {
                ++i;
            }
        }
    }

    function addReward(
        IERC20Metadata rewardToken,
        uint256 rewardStartTime,
        uint256 rewardPerSecond
    ) external onlyOwner {
        _addReward(rewardToken, rewardStartTime, rewardPerSecond);
    }

    function _addReward(IERC20Metadata rewardToken, uint256 rewardStartTime, uint256 rewardPerSecond) private {
        if (_rewardTokenAddresses.length() == MAX_REWARDS) revert MaxRewardCount();
        if (_rewardTokenAddresses.contains(address(rewardToken))) revert TokenAlreadyAdded();
        if (rewardStartTime < block.timestamp || rewardStartTime < settings.startTime) revert InvalidRewardStartTime();

        uint256 decimalsRewardToken = uint256(rewardToken.decimals());
        if (decimalsRewardToken >= 30) revert ExceedsMaxTokenDecimals();

        _rewardTokenAddresses.add(address(rewardToken));

        _rewardInfo[address(rewardToken)] = RewardInfo({
            accTokenPerShare: 0,
            rewardPerSecond: rewardPerSecond,
            startTime: rewardStartTime,
            PRECISION_FACTOR: uint256(10 ** (uint256(30) - decimalsRewardToken))
        });

        emit RewardAdded(address(rewardToken), rewardStartTime, rewardPerSecond);
    }

    function addPoolOperator(address operator) external onlyOwner {
        _operators.add(operator);
        emit OperatorRemoved(operator);
    }

    function removePoolOperator(address operator) external onlyOwner {
        if (!_operators.contains(operator)) revert InvalidOperator();

        _operators.remove(operator);
        emit OperatorRemoved(operator);
    }

    function updateRewardRate(address token, uint256 rate) external onlyOwner {
        _updateRewardRate(token, rate);
    }

    function _updateRewardRate(address rewardToken, uint256 rate) internal {
        _validateRewardToken(rewardToken);

        _rewardInfo[rewardToken].rewardPerSecond = rate;
        emit RewardRateUpdated(rewardToken, rate);
    }

    function updateRewardStart(address token, uint256 newStart) external onlyOwner {
        _updateRewardStart(token, newStart);
    }

    function _updateRewardStart(address rewardToken, uint256 newStart) internal {
        _validateRewardToken(rewardToken);

        RewardInfo storage reward = _rewardInfo[rewardToken];

        if (block.timestamp >= reward.startTime) revert RewardAlreadyStarted();
        if (newStart < block.timestamp) revert InvalidRewardStartTime();

        reward.startTime = newStart;

        emit RewardStartUpdated(rewardToken, newStart);
    }

    /**
     * @dev Transfer ownership of this NitroPool
     *
     * Must only be called by the owner of this contract
     */
    function transferOwnership(address newOwner) public override onlyOwner {
        _setNitroPoolOwner(newOwner);
        Ownable.transferOwnership(newOwner);
    }

    /**
     * @dev Transfer ownership of this NitroPool
     *
     * Must only be called by the owner of this contract
     */
    function renounceOwnership() public override onlyOwner {
        _setNitroPoolOwner(address(0));
        Ownable.renounceOwnership();
    }

    // =============================================================================== //
    // ========================= EXTERNAL OPERATOR FUNCTIONS ========================= //
    // =============================================================================== //

    function operatorAddReward(
        IERC20Metadata rewardToken,
        uint256 rewardStartTime,
        uint256 rewardPerSecond
    ) external nonReentrant onlyPoolOperator {
        _addReward(rewardToken, rewardStartTime, rewardPerSecond);
    }

    function operatorUpdateRewardRate(address token, uint256 rate) external onlyPoolOperator {
        _updateRewardRate(token, rate);
    }

    function operatorUpdateRewardStart(address token, uint256 newStart) external onlyPoolOperator {
        _updateRewardStart(token, newStart);
    }

    // ============================================================================= //
    // ================================= INTERNAL ================================== //
    // ============================================================================= //

    /**
     * @dev Set requirements that positions must meet to be staked on this Nitro Pool
     */
    function _setRequirements(
        uint256 lockDurationReq,
        uint256 lockEndReq,
        uint256 depositAmountReq,
        bool whitelist
    ) internal {
        require(lockEndReq == 0 || settings.startTime < lockEndReq, "invalid lockEnd");

        if (published) {
            // Can't decrease requirements if already published
            require(lockDurationReq >= settings.lockDurationReq, "invalid lockDuration");
            require(lockEndReq >= settings.lockEndReq, "invalid lockEnd");
            require(depositAmountReq >= settings.depositAmountReq, "invalid depositAmount");
            require(!settings.whitelist || settings.whitelist == whitelist, "invalid whitelist");
        }

        settings.lockDurationReq = lockDurationReq;
        settings.lockEndReq = lockEndReq;
        settings.depositAmountReq = depositAmountReq;
        settings.whitelist = whitelist;

        emit SetRequirements(lockDurationReq, lockEndReq, depositAmountReq, whitelist);
    }

    function _getBaseRewardsInfo() internal view returns (address[] memory rewardAddresses, uint256 rewardCount) {
        rewardAddresses = _rewardTokenAddresses.values();
        rewardCount = rewardAddresses.length;
    }

    /**
     * @dev Updates rewards states of this Nitro Pool to be up-to-date
     */
    function _updatePool() internal {
        uint256 currentBlockTimestamp = block.timestamp;

        if (currentBlockTimestamp <= lastRewardTime) return;

        // do nothing if there is no deposit
        if (totalDepositAmount == 0) {
            lastRewardTime = currentBlockTimestamp;
            emit UpdatePool();
            return;
        }

        (address[] memory rewardAddresses, uint256 rewardCount) = _getBaseRewardsInfo();
        uint256 fromTime;
        uint256 multiplier;
        uint256 rewardAmount;
        uint256 _startTime;

        for (uint256 i = 0; i < rewardCount; ) {
            RewardInfo storage reward = _rewardInfo[rewardAddresses[i]];
            _startTime = reward.startTime;

            // Handle case of tokens added later
            // Don't accumulate for rewards not active yet
            if (_startTime < block.timestamp) {
                // reward.startTime < block.timestamp (start is in the past). So reward is active.
                // Compare the reward start time to lastRewardTime.
                // Check is in the event reward emissions, should, have started.
                // But lastRewardTime is currently still some time before the rewards start time.
                // Meaning there has not been any triggers to updatePool since the rewards scheduled start time.

                fromTime = _startTime > lastRewardTime ? _startTime : lastRewardTime;
                multiplier = _getMultiplier(fromTime, block.timestamp);
                rewardAmount = reward.rewardPerSecond * multiplier;
                reward.accTokenPerShare += (rewardAmount * reward.PRECISION_FACTOR) / totalDepositAmount;
            }

            unchecked {
                ++i;
            }
        }

        lastRewardTime = currentBlockTimestamp;
        emit UpdatePool();
    }

    /**
     * @dev Add a user's deposited amount into this Nitro Pool
     */
    function _deposit(address account, uint256 tokenId, uint256 amount) internal {
        require(
            (settings.depositEndTime == 0 || settings.depositEndTime >= block.timestamp) && !emergencyClose,
            "not allowed"
        );

        if (address(customReqContract) != address(0)) {
            if (!customReqContract.canDeposit(account, tokenId)) revert InvalidCustomRequirement();
        }
        _updatePool();

        UserInfo storage user = userInfo[account];
        _harvest(user, account);

        user.totalDepositAmount += amount;
        totalDepositAmount += amount;

        _updateRewardDebt(user);

        emit Deposit(account, tokenId, amount);
    }

    /**
     * @dev Transfer to a user its pending rewards
     *
     * There may be local or custom requirements that prevent the user from being able to currently harvest.
     * In that case, any pending amounts are buffered for the user to be claimable later.
     */
    function _harvest(UserInfo storage user, address to) internal {
        uint256 userAmount = user.totalDepositAmount;
        // Check and exit early to reduce code nesting blocks below
        if (userAmount == 0) return;

        bool canHarvest = true;
        if (address(customReqContract) != address(0)) {
            canHarvest = customReqContract.canHarvest(to);
        }

        // We don't check for a short circuit option on canHarvest because rewards can be buffered for later

        (address[] memory rewardAddresses, uint256 rewardCount) = _getBaseRewardsInfo();
        RewardInfo memory reward;
        uint256 pendingForToken;
        address rewardAddress;

        for (uint256 i = 0; i < rewardCount; ) {
            rewardAddress = rewardAddresses[i];
            reward = _rewardInfo[rewardAddress];

            pendingForToken =
                (userAmount * reward.accTokenPerShare) /
                reward.PRECISION_FACTOR -
                userRewardDebts[msg.sender][rewardAddress];

            // Check if harvest is allowed
            if (block.timestamp < settings.harvestStartTime || !canHarvest) {
                // Buffer any pending amounts to be claimed later
                _userPendingRewardBuffer[msg.sender][rewardAddress] += pendingForToken;
            } else {
                // Otherwise complete harvest to user process
                if (pendingForToken > 0) {
                    _userPendingRewardBuffer[msg.sender][rewardAddress] = 0;
                    emit Harvest(to, rewardAddress, pendingForToken);
                    _safeRewardsTransfer(IERC20Metadata(rewardAddress), to, pendingForToken);
                }
            }

            unchecked {
                ++i;
            }
        }

        // Reward debts are handled/updated in each of the local calling functions afterwards as needed
    }

    /**
     * @dev Update a user's rewardDebt for rewardsToken1 and rewardsToken2
     */
    function _updateRewardDebt(UserInfo storage user) internal virtual {
        (address[] memory rewardAddresses, uint256 rewardCount) = _getBaseRewardsInfo();

        for (uint256 i = 0; i < rewardCount; ) {
            RewardInfo memory reward = _rewardInfo[rewardAddresses[i]];
            userRewardDebts[msg.sender][rewardAddresses[i]] =
                (user.totalDepositAmount * reward.accTokenPerShare) /
                reward.PRECISION_FACTOR;

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @dev Check whether a position with "tokenId" ID is meeting all of this Nitro Pool's active requirements
     */
    function _checkPositionRequirements(uint256 amount, uint256 startLockTime, uint256 lockDuration) internal virtual {
        // lock duration requirement
        if (settings.lockDurationReq > 0) {
            // For unlocked position that have not been updated yet
            if (block.timestamp > startLockTime + lockDuration && settings.lockDurationReq > lockDuration) {
                revert LockDurationRequirementNotMet();
            }
        }

        // lock end time requirement
        if (settings.lockEndReq > 0) {
            if (settings.lockEndReq > startLockTime + lockDuration) revert LockTimeEndRequirementNotMet();
        }

        // deposit amount requirement
        if (settings.depositAmountReq > 0) {
            if (settings.depositAmountReq > amount) revert DepositorPoolBalanceTooLow();
        }
    }

    function _validateRewardToken(address rewardToken) internal view {
        if (rewardToken == address(0)) revert ZeroAddress({ shouldNotBeZeroAddress: "rewardToken" });
        if (!_rewardTokenAddresses.contains(rewardToken)) revert TokenNotAdded();
    }

    /**
     * @dev Safe token transfer function, in case rounding error causes pool to not have enough tokens
     */
    function _safeRewardsTransfer(IERC20Metadata token, address to, uint256 amount) internal virtual {
        if (amount == 0) return;

        uint256 balance = token.balanceOf(address(this));

        // Cap to available balance
        if (amount > balance) {
            amount = balance;
        }

        token.safeTransfer(to, amount);
    }

    function _getStackingPosition(
        uint256 tokenId
    ) internal view returns (uint256 amount, uint256 startLockTime, uint256 lockDuration) {
        (amount, , startLockTime, lockDuration, , , , ) = nftPool.getStakingPosition(tokenId);
    }

    function _getMultiplier(uint256 _from, uint256 _to) internal view returns (uint256) {
        if (_to <= settings.endTime) {
            return _to - _from;
        } else if (_from >= settings.endTime) {
            return 0;
        } else {
            return settings.endTime - _from;
        }
    }

    function _setNitroPoolOwner(address newOwner) internal {
        factory.setNitroPoolOwner(owner(), newOwner);
    }
}

