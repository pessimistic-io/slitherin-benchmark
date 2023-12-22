// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;

import "./SafeMath.sol";
import "./SafeERC20.sol";
import "./ERC721.sol";
import "./Counters.sol";
import "./ReentrancyGuard.sol";

import "./INFTHandler.sol";
import "./IMasterChef.sol";
import "./INFTPool.sol";
import "./IYieldBooster.sol";
import "./IXToken.sol";
import "./IERC20Metadata.sol";
import "./INFTPoolRewardManager.sol";

/*
 * This contract wraps ERC20 assets into non-fungible staking positions called spNFTs
 * spNFTs add the possibility to create an additional layer on liquidity providing lock features
 * spNFTs are yield-generating positions when the NFTPool contract has allocations from the Camelot Master
 */
contract NFTPool is ReentrancyGuard, INFTPool, ERC721("Arbidex staking position NFT", "spNFT") {
    using Address for address;
    using Counters for Counters.Counter;
    // using EnumerableSet for EnumerableSet.AddressSet;
    using SafeMath for uint256;
    using SafeERC20 for IERC20Metadata;

    // Info of each NFT (staked position).
    struct StakingPosition {
        uint256 amount; // How many lp tokens the user has provided
        uint256 amountWithMultiplier; // Amount + lock bonus faked amount (amount + amount*multiplier)
        uint256 startLockTime; // The time at which the user made his deposit
        uint256 lockDuration; // The lock duration in seconds
        uint256 lockMultiplier; // Active lock multiplier (times 1e2)
        uint256 rewardDebt; // Reward debt
        uint256 rewardDebtWETH;
        uint256 boostPoints; // Allocated xToken from yieldboost contract (optional)
        uint256 totalMultiplier; // lockMultiplier + allocated xToken boostPoints multiplier
        uint256 pendingXTokenRewards; // Not harvested xToken rewards
        uint256 pendingArxRewards; // Not harvested ARX rewards
        uint256 pendingWETHRewards; // Not harvested ARX rewards
    }

    Counters.Counter private _tokenIds;

    address public operator; // Used to delegate multiplier settings to project's owners
    IMasterChef public master; // Address of the master
    address public immutable factory; // NFTPoolFactory contract's address
    bool public initialized;

    IERC20Metadata private _lpToken; // Deposit token contract's address
    IERC20Metadata private _arxToken; // ARXToken contract's address
    IXToken private _xToken; // xToken contract's address
    INFTPoolRewardManager public rewardManager;
    uint256 private _lpSupply; // Sum of deposit tokens on this pool
    uint256 private _lpSupplyWithMultiplier; // Sum of deposit token on this pool including the user's total multiplier (lockMultiplier + boostPoints)
    uint256 private _accRewardsPerShare; // Accumulated Rewards (staked token) per share, times 1e18. See below
    uint256 private _accRewardsPerShareWETH;

    // readable via getMultiplierSettings
    uint256 public constant MAX_GLOBAL_MULTIPLIER_LIMIT = 25000; // 250%, high limit for maxGlobalMultiplier (100 = 1%)
    uint256 public constant MAX_LOCK_MULTIPLIER_LIMIT = 15000; // 150%, high limit for maxLockMultiplier (100 = 1%)
    uint256 public constant MAX_BOOST_MULTIPLIER_LIMIT = 15000; // 150%, high limit for maxBoostMultiplier (100 = 1%)
    uint256 private _maxGlobalMultiplier = 20000; // 200%
    uint256 private _maxLockDuration = 183 days; // 6 months, Capped lock duration to have the maximum bonus lockMultiplier
    uint256 private _maxLockMultiplier = 10000; // 100%, Max available lockMultiplier (100 = 1%)
    uint256 private _maxBoostMultiplier = 10000; // 100%, Max boost that can be earned from xToken yieldBooster

    uint256 private constant _TOTAL_REWARDS_SHARES = 10000; // 100%, high limit for xTokenRewardsShare
    uint256 public xTokenRewardsShare = 8000; // 80%, directly defines arxShare with the remaining value to 100%

    bool public emergencyUnlock; // Release all locks in case of emergency

    // readable via getStakingPosition
    mapping(uint256 => StakingPosition) internal _stakingPositions; // Info of each NFT position that stakes LP tokens

    /********************************************/
    /****************** EVENTS ******************/
    /********************************************/

    event AddToPosition(uint256 indexed tokenId, address user, uint256 amount);
    event CreatePosition(uint256 indexed tokenId, uint256 amount, uint256 lockDuration);
    event WithdrawFromPosition(uint256 indexed tokenId, uint256 amount);
    event EmergencyWithdraw(uint256 indexed tokenId, uint256 amount);
    event LockPosition(uint256 indexed tokenId, uint256 lockDuration);
    event HarvestPosition(uint256 indexed tokenId, address to, uint256 pending, uint256 pendingWETH);
    event SetBoost(uint256 indexed tokenId, uint256 boostPoints);

    event PoolUpdated(uint256 lastRewardTime, uint256 accRewardsPerShare, uint256 accRewardsPerShareWETH);

    event SetLockMultiplierSettings(uint256 maxLockDuration, uint256 maxLockMultiplier);
    event SetBoostMultiplierSettings(uint256 maxGlobalMultiplier, uint256 maxBoostMultiplier);
    event SetXTokenRewardsShare(uint256 xTokenRewardsShare);
    event SetUnlockOperator(address operator, bool isAdded);
    event SetEmergencyUnlock(bool emergencyUnlock);
    event SetOperator(address operator);
    event SetRewardManager(address manager);

    constructor() {
        factory = msg.sender;
    }

    function initialize(
        IMasterChef master_,
        IERC20Metadata arxToken,
        IXToken xToken,
        IERC20Metadata lpToken,
        INFTPoolRewardManager manager
    ) external {
        require(msg.sender == factory && !initialized, "FORBIDDEN");
        _lpToken = lpToken;
        master = master_;
        _arxToken = arxToken;
        _xToken = xToken;
        rewardManager = manager;
        initialized = true;

        // to convert main token to xToken
        _arxToken.approve(address(_xToken), type(uint256).max);
    }

    /***********************************************/
    /****************** MODIFIERS ******************/
    /***********************************************/

    /**
     * @dev Check if caller has operator rights
     */
    function _requireOnlyOwner() internal view {
        require(master.isUnlockOperator(msg.sender), "FORBIDDEN");
        // onlyOwner: caller is not the owner
    }

    /**
     * @dev Check if caller is a validated YieldBooster contract
     */
    function _requireOnlyYieldBooster() internal view {
        // onlyYieldBooster: caller has no yield boost rights
        require(msg.sender == yieldBooster(), "FORBIDDEN");
    }

    /**
     * @dev Check if a userAddress has privileged rights on a spNFT
     */
    function _requireOnlyOperatorOrOwnerOf(uint256 tokenId) internal view {
        // isApprovedOrOwner: caller has no rights on token
        require(ERC721._isApprovedOrOwner(msg.sender, tokenId), "FORBIDDEN");
    }

    /**
     * @dev Check if a userAddress has privileged rights on a spNFT
     */
    function _requireOnlyApprovedOrOwnerOf(uint256 tokenId) internal view {
        require(_exists(tokenId), "ERC721: operator query for nonexistent token");
        require(_isOwnerOf(msg.sender, tokenId) || getApproved(tokenId) == msg.sender, "FORBIDDEN");
    }

    /**
     * @dev Check if a msg.sender is owner of a spNFT
     */
    function _requireOnlyOwnerOf(uint256 tokenId) internal view {
        require(_exists(tokenId), "ERC721: operator query for nonexistent token");
        // onlyOwnerOf: caller has no rights on token
        require(_isOwnerOf(msg.sender, tokenId), "not owner");
    }

    /**************************************************/
    /****************** PUBLIC VIEWS ******************/
    /**************************************************/

    /**
     * @dev Returns this contract's owner (= master contract's owner)
     */
    function owner() public view returns (address) {
        return master.owner();
    }

    /**
     * @dev Get master-defined yield booster contract address
     */
    function yieldBooster() public view returns (address) {
        return master.yieldBooster();
    }

    /**
     * @dev Returns true if "tokenId" is an existing spNFT id
     */
    function exists(uint256 tokenId) external view override returns (bool) {
        return ERC721._exists(tokenId);
    }

    /**
     * @dev Returns last minted NFT id
     */
    function lastTokenId() external view returns (uint256) {
        return _tokenIds.current();
    }

    /**
     * @dev Returns true if emergency unlocks are activated on this pool or on the master
     */
    function isUnlocked() public view returns (bool) {
        return emergencyUnlock || master.emergencyUnlock();
    }

    /**
     * @dev Returns true if this pool currently has deposits
     */
    function hasDeposits() external view override returns (bool) {
        return _lpSupplyWithMultiplier > 0;
    }

    /**
     * @dev Returns general "pool" info for this contract
     */
    function getPoolInfo()
        external
        view
        override
        returns (
            address lpToken,
            address arxoken,
            address xToken,
            uint256 lastRewardTime,
            uint256 accRewardsPerShare,
            uint256 accRewardsPerShareWETH,
            uint256 lpSupply,
            uint256 lpSupplyWithMultiplier,
            uint256 allocPoint
        )
    {
        (, allocPoint, lastRewardTime, , , , ) = master.getPoolInfo(address(this));
        return (
            address(_lpToken),
            address(_arxToken),
            address(_xToken),
            lastRewardTime,
            _accRewardsPerShare,
            _accRewardsPerShareWETH,
            _lpSupply,
            _lpSupplyWithMultiplier,
            allocPoint
        );
    }

    /**
     * @dev Returns all multiplier settings for this contract
     */
    function getMultiplierSettings()
        external
        view
        returns (
            uint256 maxGlobalMultiplier,
            uint256 maxLockDuration,
            uint256 maxLockMultiplier,
            uint256 maxBoostMultiplier
        )
    {
        return (_maxGlobalMultiplier, _maxLockDuration, _maxLockMultiplier, _maxBoostMultiplier);
    }

    /**
     * @dev Returns bonus multiplier from YieldBooster contract for given "amount" (LP token staked) and "boostPoints" (result is *1e4)
     */
    function getMultiplierByBoostPoints(uint256 amount, uint256 boostPoints) public view returns (uint256) {
        if (boostPoints == 0 || amount == 0) return 0;

        address yieldBoosterAddress = yieldBooster();
        // only call yieldBooster contract if defined on master
        return
            yieldBoosterAddress != address(0)
                ? IYieldBooster(yieldBoosterAddress).getMultiplier(
                    address(this),
                    _maxBoostMultiplier,
                    amount,
                    _lpSupply,
                    boostPoints
                )
                : 0;
    }

    /**
     * @dev Returns expected multiplier for a "lockDuration" duration lock (result is *1e4)
     */
    function getMultiplierByLockDuration(uint256 lockDuration) public view returns (uint256) {
        // in case of emergency unlock
        if (isUnlocked()) return 0;

        if (_maxLockDuration == 0 || lockDuration == 0) return 0;

        // capped to maxLockDuration
        if (lockDuration >= _maxLockDuration) return _maxLockMultiplier;

        return _maxLockMultiplier.mul(lockDuration).div(_maxLockDuration);
    }

    /**
     * @dev Returns a position info
     */
    function getStakingPosition(
        uint256 tokenId
    )
        external
        view
        override
        returns (
            uint256 amount,
            uint256 amountWithMultiplier,
            uint256 startLockTime,
            uint256 lockDuration,
            uint256 lockMultiplier,
            uint256 rewardDebt,
            uint256 rewardDebtWETH,
            uint256 boostPoints,
            uint256 totalMultiplier
        )
    {
        StakingPosition storage position = _stakingPositions[tokenId];
        return (
            position.amount,
            position.amountWithMultiplier,
            position.startLockTime,
            position.lockDuration,
            position.lockMultiplier,
            position.rewardDebt,
            position.rewardDebtWETH,
            position.boostPoints,
            position.totalMultiplier
        );
    }

    /**
     * @dev Returns pending rewards for a position
     */
    function pendingRewards(uint256 tokenId) external view returns (uint256 mainAmount, uint256 wethAmount) {
        (
            ,
            ,
            uint256 lastRewardTime,
            uint256 reserve,
            uint256 reserveWETH,
            uint256 poolEmissionRate,
            uint256 poolEmissionRateWETH
        ) = master.getPoolInfo(address(this));

        StakingPosition storage position = _stakingPositions[tokenId];
        uint256 positionAmountMultiplied = position.amountWithMultiplier;
        uint256 accRewardsPerShare = _accRewardsPerShare;
        uint256 accRewardsPerShareWETH = _accRewardsPerShareWETH;

        bool timeHasPassed = _currentBlockTimestamp() > lastRewardTime;
        bool hasLpDeposits = _lpSupplyWithMultiplier > 0;

        if ((reserve > 0 || reserveWETH > 0 || timeHasPassed) && hasLpDeposits) {
            uint256 duration = _currentBlockTimestamp().sub(lastRewardTime);

            // adding reserve here in case master has been synced but not the pool
            uint256 tokenRewards = duration.mul(poolEmissionRate).add(reserve);
            accRewardsPerShare = accRewardsPerShare.add(tokenRewards.mul(1e18).div(_lpSupplyWithMultiplier));

            uint256 wethRewards = duration.mul(poolEmissionRateWETH).add(reserveWETH);
            accRewardsPerShareWETH = accRewardsPerShareWETH.add(wethRewards.mul(1e18).div(_lpSupplyWithMultiplier));
        }

        mainAmount = positionAmountMultiplied
            .mul(accRewardsPerShare)
            .div(1e18)
            .sub(position.rewardDebt)
            .add(position.pendingXTokenRewards)
            .add(position.pendingArxRewards);

        wethAmount = positionAmountMultiplied.mul(accRewardsPerShareWETH).div(1e18).sub(position.rewardDebtWETH).add(
            position.pendingWETHRewards
        );

        return (mainAmount, wethAmount);
    }

    function pendingAdditionalRewards(
        uint256 tokenId
    ) external view returns (address[] memory tokens, uint256[] memory rewardAmounts) {
        StakingPosition storage position = _stakingPositions[tokenId];
        (, , uint256 lastRewardTime, , , , ) = master.getPoolInfo(address(this));
        (tokens, rewardAmounts) = rewardManager.pendingAdditionalRewards(
            tokenId,
            position.amountWithMultiplier,
            _lpSupplyWithMultiplier,
            lastRewardTime
        );
    }

    /*******************************************************/
    /****************** OWNABLE FUNCTIONS ******************/
    /*******************************************************/

    /**
     * @dev Set lock multiplier settings
     *
     * maxLockMultiplier must be <= MAX_LOCK_MULTIPLIER_LIMIT
     * maxLockMultiplier must be <= _maxGlobalMultiplier - _maxBoostMultiplier
     *
     * Must only be called by the owner
     */
    function setLockMultiplierSettings(uint256 maxLockDuration, uint256 maxLockMultiplier) external {
        require(msg.sender == operator, "FORBIDDEN");
        // onlyOperatorOrOwner: caller has no operator rights
        require(
            maxLockMultiplier <= MAX_LOCK_MULTIPLIER_LIMIT &&
                maxLockMultiplier.add(_maxBoostMultiplier) <= _maxGlobalMultiplier,
            "too high"
        );
        // setLockSettings: maxGlobalMultiplier is too high
        _maxLockDuration = maxLockDuration;
        _maxLockMultiplier = maxLockMultiplier;

        emit SetLockMultiplierSettings(maxLockDuration, maxLockMultiplier);
    }

    /**
     * @dev Set global and boost multiplier settings
     *
     * maxGlobalMultiplier must be <= MAX_GLOBAL_MULTIPLIER_LIMIT
     * maxBoostMultiplier must be <= MAX_BOOST_MULTIPLIER_LIMIT
     * (maxBoostMultiplier + _maxLockMultiplier) must be <= _maxGlobalMultiplier
     *
     * Must only be called by the owner
     */
    function setBoostMultiplierSettings(uint256 maxGlobalMultiplier, uint256 maxBoostMultiplier) external {
        _requireOnlyOwner();
        require(maxGlobalMultiplier <= MAX_GLOBAL_MULTIPLIER_LIMIT, "too high");

        // setMultiplierSettings: maxGlobalMultiplier is too high
        require(
            maxBoostMultiplier <= MAX_BOOST_MULTIPLIER_LIMIT &&
                maxBoostMultiplier.add(_maxLockMultiplier) <= maxGlobalMultiplier,
            "too high"
        );
        // setLockSettings: maxGlobalMultiplier is too high
        _maxGlobalMultiplier = maxGlobalMultiplier;
        _maxBoostMultiplier = maxBoostMultiplier;

        emit SetBoostMultiplierSettings(maxGlobalMultiplier, maxBoostMultiplier);
    }

    /**
     * @dev Set the share of xToken for the distributed rewards
     * The share of ARX will incidently be 100% - xTokenRewardsShare
     *
     * Must only be called by the owner
     */
    function setXTokenRewardsShare(uint256 xTokenRewardsShare_) external {
        _requireOnlyOwner();
        require(xTokenRewardsShare_ <= _TOTAL_REWARDS_SHARES, "too high");

        xTokenRewardsShare = xTokenRewardsShare_;
        emit SetXTokenRewardsShare(xTokenRewardsShare_);
    }

    /**
     * @dev Set emergency unlock status
     *
     * Must only be called by the owner
     */
    function setEmergencyUnlock(bool emergencyUnlock_) external {
        _requireOnlyOwner();

        emergencyUnlock = emergencyUnlock_;
        emit SetEmergencyUnlock(emergencyUnlock);
    }

    /**
     * @dev Set operator (usually deposit token's project's owner) to adjust contract's settings
     *
     * Must only be called by the owner
     */
    function setOperator(address operator_) external {
        _requireOnlyOwner();

        operator = operator_;
        emit SetOperator(operator_);
    }

    /**
     * @dev Set operator (usually deposit token's project's owner) to adjust contract's settings
     *
     * Must only be called by the owner
     */
    function setRewardManager(address manager) external {
        _requireOnlyOwner();

        rewardManager = INFTPoolRewardManager(manager);
        emit SetRewardManager(manager);
    }

    /****************************************************************/
    /****************** EXTERNAL PUBLIC FUNCTIONS  ******************/
    /****************************************************************/

    /**
     * @dev Add nonReentrant to ERC721.transferFrom
     */
    function transferFrom(address from, address to, uint256 tokenId) public override(ERC721, IERC721) nonReentrant {
        ERC721.transferFrom(from, to, tokenId);
    }

    /**
     * @dev Add nonReentrant to ERC721.safeTransferFrom
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory _data
    ) public override(ERC721, IERC721) nonReentrant {
        ERC721.safeTransferFrom(from, to, tokenId, _data);
    }

    /**
     * @dev Updates rewards states of the given pool to be up-to-date
     */
    function updatePool() external nonReentrant {
        _updatePool();
    }

    /**
     * @dev Create a staking position (spNFT) with an optional lockDuration
     */
    function createPosition(uint256 amount, uint256 lockDuration) external nonReentrant {
        // no new lock can be set if the pool has been unlocked
        if (isUnlocked()) {
            require(lockDuration == 0, "locks disabled");
        }

        _updatePool();

        // handle tokens with transfer tax
        amount = _transferSupportingFeeOnTransfer(_lpToken, msg.sender, amount);
        require(amount != 0, "zero amount"); // createPosition: amount cannot be null

        // mint NFT position token
        uint256 currentTokenId = _mintNextTokenId(msg.sender);

        // calculate bonuses
        uint256 lockMultiplier = getMultiplierByLockDuration(lockDuration);
        uint256 amountWithMultiplier = amount.mul(lockMultiplier.add(1e4)).div(1e4);

        // create position
        _stakingPositions[currentTokenId] = StakingPosition({
            amount: amount,
            rewardDebt: amountWithMultiplier.mul(_accRewardsPerShare).div(1e18),
            rewardDebtWETH: amountWithMultiplier.mul(_accRewardsPerShareWETH).div(1e18),
            lockDuration: lockDuration,
            startLockTime: _currentBlockTimestamp(),
            lockMultiplier: lockMultiplier,
            amountWithMultiplier: amountWithMultiplier,
            boostPoints: 0,
            totalMultiplier: lockMultiplier,
            pendingArxRewards: 0,
            pendingXTokenRewards: 0,
            pendingWETHRewards: 0
        });

        // update total lp supply
        _lpSupply = _lpSupply.add(amount);
        _lpSupplyWithMultiplier = _lpSupplyWithMultiplier.add(amountWithMultiplier);

        rewardManager.updatePositionRewardDebts(amountWithMultiplier, currentTokenId);

        emit CreatePosition(currentTokenId, amount, lockDuration);
    }

    /**
     * @dev Add to an existing staking position
     *
     * Can only be called by spNFT's owner or operators
     */
    function addToPosition(uint256 tokenId, uint256 amountToAdd) external nonReentrant {
        _requireOnlyOperatorOrOwnerOf(tokenId);
        require(amountToAdd > 0, "0 amount"); // addToPosition: amount cannot be null

        _updatePool();
        address nftOwner = ERC721.ownerOf(tokenId);
        _harvestPosition(tokenId, nftOwner);

        StakingPosition storage position = _stakingPositions[tokenId];

        // if position is locked, renew the lock
        if (position.lockDuration > 0) {
            position.startLockTime = _currentBlockTimestamp();
            position.lockMultiplier = getMultiplierByLockDuration(position.lockDuration);
        }

        // handle tokens with transfer tax
        amountToAdd = _transferSupportingFeeOnTransfer(_lpToken, msg.sender, amountToAdd);

        // update position
        position.amount = position.amount.add(amountToAdd);
        _lpSupply = _lpSupply.add(amountToAdd);
        _updateBoostMultiplierInfoAndRewardDebt(position, tokenId);

        _checkOnAddToPosition(nftOwner, tokenId, amountToAdd);
        emit AddToPosition(tokenId, msg.sender, amountToAdd);
    }

    /**
     * @dev Assign "amount" of boost points to a position
     *
     * Can only be called by the master-defined YieldBooster contract
     */
    function boost(uint256 tokenId, uint256 amount) external override nonReentrant {
        _requireOnlyYieldBooster();
        require(ERC721._exists(tokenId), "invalid tokenId");

        _updatePool();
        _harvestPosition(tokenId, address(0));

        StakingPosition storage position = _stakingPositions[tokenId];

        // update position
        uint256 boostPoints = position.boostPoints.add(amount);
        position.boostPoints = boostPoints;
        _updateBoostMultiplierInfoAndRewardDebt(position, tokenId);
        emit SetBoost(tokenId, boostPoints);
    }

    /**
     * @dev Remove "amount" of boost points from a position
     *
     * Can only be called by the master-defined YieldBooster contract
     */
    function unboost(uint256 tokenId, uint256 amount) external override nonReentrant {
        _requireOnlyYieldBooster();

        _updatePool();
        _harvestPosition(tokenId, address(0));

        StakingPosition storage position = _stakingPositions[tokenId];

        // update position
        uint256 boostPoints = position.boostPoints.sub(amount);
        position.boostPoints = boostPoints;
        _updateBoostMultiplierInfoAndRewardDebt(position, tokenId);
        emit SetBoost(tokenId, boostPoints);
    }

    /**
     * @dev Harvest from a staking position
     *
     * Can only be called by spNFT's owner or approved address
     */
    function harvestPosition(uint256 tokenId) external nonReentrant {
        _requireOnlyApprovedOrOwnerOf(tokenId);

        _updatePool();
        _harvestPosition(tokenId, ERC721.ownerOf(tokenId));
        _updateBoostMultiplierInfoAndRewardDebt(_stakingPositions[tokenId], tokenId);
    }

    /**
     * @dev Harvest from a staking position to "to" address
     *
     * Can only be called by spNFT's owner or approved address
     * spNFT's owner must be a contract
     */
    function harvestPositionTo(uint256 tokenId, address to) external nonReentrant {
        _requireOnlyApprovedOrOwnerOf(tokenId);
        require(ERC721.ownerOf(tokenId).isContract(), "FORBIDDEN");

        _updatePool();
        _harvestPosition(tokenId, to);
        _updateBoostMultiplierInfoAndRewardDebt(_stakingPositions[tokenId], tokenId);
    }

    /**
     * @dev Harvest from multiple staking positions to "to" address
     *
     * Can only be called by spNFT's owner or approved address
     */
    function harvestPositionsTo(uint256[] calldata tokenIds, address to) external nonReentrant {
        _updatePool();

        uint256 length = tokenIds.length;

        for (uint256 i = 0; i < length; ++i) {
            uint256 tokenId = tokenIds[i];
            _requireOnlyApprovedOrOwnerOf(tokenId);
            address tokenOwner = ERC721.ownerOf(tokenId);
            // if sender is the current owner, must also be the harvest dst address
            // if sender is approved, current owner must be a contract
            require((msg.sender == tokenOwner && msg.sender == to) || tokenOwner.isContract(), "FORBIDDEN");

            _harvestPosition(tokenId, to);
            _updateBoostMultiplierInfoAndRewardDebt(_stakingPositions[tokenId], tokenId);
        }
    }

    /**
     * @dev Withdraw from a staking position
     *
     * Can only be called by spNFT's owner or approved address
     */
    function withdrawFromPosition(uint256 tokenId, uint256 amountToWithdraw) external nonReentrant {
        _requireOnlyApprovedOrOwnerOf(tokenId);

        _updatePool();
        address nftOwner = ERC721.ownerOf(tokenId);
        _withdrawFromPosition(nftOwner, tokenId, amountToWithdraw);
        _checkOnWithdraw(nftOwner, tokenId, amountToWithdraw);
    }

    /**
     * @dev Renew lock from a staking position
     *
     * Can only be called by spNFT's owner or approved address
     */
    function renewLockPosition(uint256 tokenId) external nonReentrant {
        _requireOnlyApprovedOrOwnerOf(tokenId);

        _updatePool();
        _lockPosition(tokenId, _stakingPositions[tokenId].lockDuration);
    }

    /**
     * @dev Lock a staking position (can be used to extend a lock)
     *
     * Can only be called by spNFT's owner or approved address
     */
    function lockPosition(uint256 tokenId, uint256 lockDuration) external nonReentrant {
        _requireOnlyApprovedOrOwnerOf(tokenId);

        _updatePool();
        _lockPosition(tokenId, lockDuration);
    }

    /**
     * Withdraw without caring about rewards, EMERGENCY ONLY
     *
     * Can only be called by spNFT's owner
     */
    function emergencyWithdraw(uint256 tokenId) external nonReentrant {
        _requireOnlyOwnerOf(tokenId);

        StakingPosition storage position = _stakingPositions[tokenId];

        require(
            master.isUnlockOperator(msg.sender) ||
                position.startLockTime.add(position.lockDuration) <= _currentBlockTimestamp() ||
                isUnlocked(),
            "locked"
        );
        // emergencyWithdraw: locked

        uint256 amount = position.amount;

        // update total lp supply
        _lpSupply = _lpSupply.sub(amount);
        _lpSupplyWithMultiplier = _lpSupplyWithMultiplier.sub(position.amountWithMultiplier);

        // destroy position (ignore boost points)
        _destroyPosition(tokenId, 0);

        emit EmergencyWithdraw(tokenId, amount);
        _lpToken.safeTransfer(msg.sender, amount);
    }

    /********************************************************/
    /****************** INTERNAL FUNCTIONS ******************/
    /********************************************************/

    /**
     * @dev Returns whether "userAddress" is the owner of "tokenId" spNFT
     */
    function _isOwnerOf(address userAddress, uint256 tokenId) internal view returns (bool) {
        return userAddress == ERC721.ownerOf(tokenId);
    }

    /**
     * @dev Updates rewards states of this pool to be up-to-date
     */
    function _updatePool() internal {
        uint256 lpSupplyMultiplied = _lpSupplyWithMultiplier; // stash

        // User current reward time before pool claims and updates it
        (, , uint256 currentLastRewardTime, , , , ) = master.getPoolInfo(address(this));
        rewardManager.updateRewardsPerShare(lpSupplyMultiplied, currentLastRewardTime);

        // Returns the amount of main token and WETH. Both amounts are transfered to this contract at this time
        (uint256 rewardAmount, uint256 amountWETH) = master.claimRewards();

        if (rewardAmount > 0) {
            _accRewardsPerShare = _accRewardsPerShare.add(rewardAmount.mul(1e18).div(lpSupplyMultiplied));
        }

        if (amountWETH > 0) {
            _accRewardsPerShareWETH = _accRewardsPerShareWETH.add(amountWETH.mul(1e18).div(lpSupplyMultiplied));
        }

        emit PoolUpdated(_currentBlockTimestamp(), _accRewardsPerShare, _accRewardsPerShareWETH);
    }

    /**
     * @dev Destroys spNFT
     *
     * "boostPointsToDeallocate" is set to 0 to ignore boost points handling if called during an emergencyWithdraw
     * Users should still be able to deallocate xToken from the YieldBooster contract
     */
    function _destroyPosition(uint256 tokenId, uint256 boostPoints) internal {
        // calls yieldBooster contract to deallocate the spNFT's owner boost points if any
        if (boostPoints > 0) {
            IYieldBooster(yieldBooster()).deallocateAllFromPool(msg.sender, tokenId);
        }

        // burn spNFT
        delete _stakingPositions[tokenId];
        ERC721._burn(tokenId);
    }

    /**
     * @dev Computes new tokenId and mint associated spNFT to "to" address
     */
    function _mintNextTokenId(address to) internal returns (uint256 tokenId) {
        _tokenIds.increment();
        tokenId = _tokenIds.current();
        _safeMint(to, tokenId);
    }

    /**
     * @dev Withdraw from a staking position and destroy it
     *
     * _updatePool() should be executed before calling this
     */
    function _withdrawFromPosition(address nftOwner, uint256 tokenId, uint256 amountToWithdraw) internal {
        require(amountToWithdraw > 0, "null");
        // withdrawFromPosition: amount cannot be null

        StakingPosition storage position = _stakingPositions[tokenId];
        require(
            master.isUnlockOperator(nftOwner) ||
                position.startLockTime.add(position.lockDuration) <= _currentBlockTimestamp() ||
                isUnlocked(),
            "locked"
        );
        // withdrawFromPosition: invalid amount
        require(position.amount >= amountToWithdraw, "invalid");

        _harvestPosition(tokenId, nftOwner);

        // update position
        position.amount = position.amount.sub(amountToWithdraw);

        // update total lp supply
        _lpSupply = _lpSupply.sub(amountToWithdraw);

        if (position.amount == 0) {
            // destroy if now empty
            _lpSupplyWithMultiplier = _lpSupplyWithMultiplier.sub(position.amountWithMultiplier);
            _destroyPosition(tokenId, position.boostPoints);
        } else {
            _updateBoostMultiplierInfoAndRewardDebt(position, tokenId);
        }

        emit WithdrawFromPosition(tokenId, amountToWithdraw);
        _lpToken.safeTransfer(nftOwner, amountToWithdraw);
    }

    /**
     * @dev updates position's boost multiplier, totalMultiplier, amountWithMultiplier (_lpSupplyWithMultiplier)
     * and rewardDebt without updating lockMultiplier
     */
    function _updateBoostMultiplierInfoAndRewardDebt(StakingPosition storage position, uint256 tokenId) internal {
        // keep the original lock multiplier and recompute current boostPoints multiplier
        uint256 newTotalMultiplier = getMultiplierByBoostPoints(position.amount, position.boostPoints).add(
            position.lockMultiplier
        );
        if (newTotalMultiplier > _maxGlobalMultiplier) newTotalMultiplier = _maxGlobalMultiplier;

        position.totalMultiplier = newTotalMultiplier;
        uint256 amountWithMultiplier = position.amount.mul(newTotalMultiplier.add(1e4)).div(1e4);

        uint256 lpSupplyMultiplied = _lpSupplyWithMultiplier;
        // update global supply
        _lpSupplyWithMultiplier = lpSupplyMultiplied.sub(position.amountWithMultiplier).add(amountWithMultiplier);
        position.amountWithMultiplier = amountWithMultiplier;

        position.rewardDebt = amountWithMultiplier.mul(_accRewardsPerShare).div(1e18);
        position.rewardDebtWETH = amountWithMultiplier.mul(_accRewardsPerShareWETH).div(1e18);

        rewardManager.updatePositionRewardDebts(amountWithMultiplier, tokenId);
    }

    /**
     * @dev Harvest rewards from a position
     * Will also update the position's totalMultiplier
     */
    function _harvestPosition(uint256 tokenId, address to) internal {
        StakingPosition storage position = _stakingPositions[tokenId];

        // compute position's pending rewards
        uint256 positionAmountMultiplied = position.amountWithMultiplier;
        uint256 pending = positionAmountMultiplied.mul(_accRewardsPerShare).div(1e18).sub(position.rewardDebt);
        uint256 pendingWETH = positionAmountMultiplied.mul(_accRewardsPerShareWETH).div(1e18).sub(
            position.rewardDebtWETH
        );

        // unlock the position if pool has been unlocked or position is unlocked
        if (isUnlocked() || position.startLockTime.add(position.lockDuration) <= _currentBlockTimestamp()) {
            position.lockDuration = 0;
            position.lockMultiplier = 0;
        }

        // transfer rewards
        if (
            pending > 0 ||
            pendingWETH > 0 ||
            position.pendingXTokenRewards > 0 ||
            position.pendingArxRewards > 0 ||
            position.pendingWETHRewards > 0
        ) {
            uint256 xTokenRewards = pending.mul(xTokenRewardsShare).div(_TOTAL_REWARDS_SHARES);
            uint256 arxAmount = pending.add(position.pendingArxRewards).sub(xTokenRewards);

            xTokenRewards = xTokenRewards.add(position.pendingXTokenRewards);

            // Stack rewards in a buffer if to is equal to address(0)
            if (address(0) == to) {
                position.pendingXTokenRewards = xTokenRewards;
                position.pendingArxRewards = arxAmount;
                position.pendingWETHRewards = pendingWETH;
            } else {
                // convert and send xToken + main token rewards
                position.pendingXTokenRewards = 0;
                position.pendingArxRewards = 0;
                position.pendingWETHRewards = 0;

                if (xTokenRewards > 0) xTokenRewards = _safeConvertTo(to, xTokenRewards);

                arxAmount = _safeRewardsTransfer(address(_arxToken), to, arxAmount);
                pendingWETH = _safeRewardsTransfer(master.wethToken(), to, pendingWETH);

                // forbidden to harvest if contract has not explicitly confirmed it handle it
                _checkOnNFTHarvest(to, tokenId, arxAmount, xTokenRewards);

                rewardManager.harvestAdditionalRewards(positionAmountMultiplied, to, tokenId);
            }
        }

        emit HarvestPosition(tokenId, to, pending, pendingWETH);
    }

    /**
     * @dev Renew lock from a staking position with "lockDuration"
     */
    function _lockPosition(uint256 tokenId, uint256 lockDuration) internal {
        require(!isUnlocked(), "locks disabled");

        StakingPosition storage position = _stakingPositions[tokenId];

        // for renew only, check if new lockDuration is at least = to the remaining active duration
        uint256 endTime = position.startLockTime.add(position.lockDuration);
        uint256 currentBlockTimestamp = _currentBlockTimestamp();
        if (endTime > currentBlockTimestamp) {
            require(lockDuration >= endTime.sub(currentBlockTimestamp) && lockDuration > 0, "invalid");
        }

        _harvestPosition(tokenId, msg.sender);

        // update position and total lp supply
        position.lockDuration = lockDuration;
        position.lockMultiplier = getMultiplierByLockDuration(lockDuration);
        position.startLockTime = currentBlockTimestamp;
        _updateBoostMultiplierInfoAndRewardDebt(position, tokenId);

        emit LockPosition(tokenId, lockDuration);
    }

    /**
     * @dev Handle deposits of tokens with transfer tax
     */
    function _transferSupportingFeeOnTransfer(
        IERC20Metadata token,
        address user,
        uint256 amount
    ) internal returns (uint256 receivedAmount) {
        uint256 previousBalance = token.balanceOf(address(this));
        token.safeTransferFrom(user, address(this), amount);
        return token.balanceOf(address(this)).sub(previousBalance);
    }

    /**
     * @dev Safe token transfer function, in case rounding error causes pool to not have enough tokens
     */
    function _safeRewardsTransfer(address tokenAddress, address to, uint256 amount) internal returns (uint256) {
        IERC20Metadata token = IERC20Metadata(tokenAddress);
        uint256 balance = token.balanceOf(address(this));
        // cap to available balance
        if (amount > balance) {
            amount = balance;
        }

        if (amount > 0) {
            token.safeTransfer(to, amount);
        }

        return amount;
    }

    /**
     * @dev Safe convert ARX to xToken function, in case rounding error causes pool to not have enough tokens
     */
    function _safeConvertTo(address to, uint256 amount) internal returns (uint256) {
        uint256 balance = _arxToken.balanceOf(address(this));
        // cap to available balance
        if (amount > balance) {
            amount = balance;
        }
        if (amount > 0) _xToken.convertTo(amount, to);
        return amount;
    }

    /**
     * @dev If NFT's owner is a contract, confirm whether it's able to handle rewards harvesting
     */
    function _checkOnNFTHarvest(address to, uint256 tokenId, uint256 arxAmount, uint256 xTokenAmount) internal {
        address nftOwner = ERC721.ownerOf(tokenId);
        if (nftOwner.isContract()) {
            bytes memory returndata = nftOwner.functionCall(
                abi.encodeWithSelector(
                    INFTHandler(nftOwner).onNFTHarvest.selector,
                    msg.sender,
                    to,
                    tokenId,
                    arxAmount,
                    xTokenAmount
                ),
                "non implemented"
            );
            require(abi.decode(returndata, (bool)), "FORBIDDEN");
        }
    }

    /**
     * @dev If NFT's owner is a contract, confirm whether it's able to handle addToPosition
     */
    function _checkOnAddToPosition(address nftOwner, uint256 tokenId, uint256 lpAmount) internal {
        if (nftOwner.isContract()) {
            bytes memory returndata = nftOwner.functionCall(
                abi.encodeWithSelector(
                    INFTHandler(nftOwner).onNFTAddToPosition.selector,
                    msg.sender,
                    tokenId,
                    lpAmount
                ),
                "non implemented"
            );
            require(abi.decode(returndata, (bool)), "FORBIDDEN");
        }
    }

    /**
     * @dev If NFT's owner is a contract, confirm whether it's able to handle withdrawals
     */
    function _checkOnWithdraw(address nftOwner, uint256 tokenId, uint256 lpAmount) internal {
        if (nftOwner.isContract()) {
            bytes memory returndata = nftOwner.functionCall(
                abi.encodeWithSelector(INFTHandler(nftOwner).onNFTWithdraw.selector, msg.sender, tokenId, lpAmount),
                "non implemented"
            );
            require(abi.decode(returndata, (bool)), "FORBIDDEN");
        }
    }

    /**
     * @dev Forbid transfer when spNFT's owner is a contract and an operator is trying to transfer it
     * This is made to avoid unintended side effects
     *
     * Contract owner can still implement it by itself if needed
     */
    function _beforeTokenTransfer(address from, address /*to*/, uint256 /*tokenId*/) internal view override {
        require(!from.isContract() || msg.sender == from, "FORBIDDEN");
    }

    /**
     * @dev Utility function to get the current block timestamp
     */
    function _currentBlockTimestamp() internal view virtual returns (uint256) {
        /* solhint-disable not-rely-on-time */
        return block.timestamp;
    }
}

