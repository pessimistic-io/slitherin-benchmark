//SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

import "./SafeERC20Upgradeable.sol";
import "./IERC20Upgradeable.sol";
import "./OwnableUpgradeable.sol";

import "./EnumerableSetUpgradeable.sol";

import "./ReentrancyGuardUpgradeable.sol";

import "./AddressUpgradeable.sol";

import "./IERC721UpgradeableParallax.sol";
import "./IParallaxStrategy.sol";
import "./IParallax.sol";

import "./TokensRescuer.sol";
import "./Timelock.sol";

error OnlyNonZeroTotalSharesValue();
error OnlyActiveStrategy();
error OnlyValidFees();
error OnlyExistPosition();
error OnlyExistStrategy();
error OnlyContractAddress();
error OnlyAfterLock(uint32 remainTime);
error OnlyValidWithdrawalSharesAmount();
error CursorOutOfBounds();
error CursorIsLessThanOne();
error CapExceeded();
error CapTooSmall();
error CallerIsNotOwnerOrApproved();
error NoTokensToCLaim();
error StrategyAlreadyAdded();
error IncorrectRewards();

/**
 * @title Main contract of the system.
 *        This contract is responsible for interaction with all strategies,
 *        that is added to the system through this contract
 *        Direct interaction with strategies is not possible.
 *        Current contract supports 2 roles:
 *        simple user and owner of the contract.
 *        Simple user can only make deposits, withdrawals,
 *        transfers of NFTs (ERC-721 tokens) and compounds.
 *        The owner of the contract can execute all owner's methods.
 *        Each user can have many positions
 *        where he will able to deposit or withdraw.
 *        Each user position is represented as ERC-721 token
 *        and can be transferred or approved for transfer.
 *        In time of position creation user receives a new ERC-721 token.
 *        When user closes a position (removes all liquidity from the position),
 *        ERC-721 token linked to the position burns.
 */
contract ParallaxUpgradeable is
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    TokensRescuer,
    Timelock
{
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    struct Strategy {
        IFees.Fees fees;
        uint256 totalDeposited;
        uint256 totalStaked;
        uint256 totalShares;
        uint256 lastCompoundTimestamp;
        uint256 cap;
        uint256 rewardPerBlock;
        uint256 rewardPerShare;
        uint256 lastUpdatedBlockNumber;
        address strategy;
        uint32 timelock;
        bool isActive;
        IERC20Upgradeable rewardToken;
        uint256 usersCount;
        mapping(address => uint256) usersToId;
        mapping(uint256 => address) users;
    }

    struct UserPosition {
        uint256 tokenId;
        uint256 shares;
        uint256 lastStakedBlockNumber;
        uint256 reward;
        uint256 former;
        uint32 lastStakedTimestamp;
        bool created;
        bool closed;
    }

    struct TokenInfo {
        uint256 strategyId;
        uint256 positionId;
    }

    IERC721UpgradeableParallax public ERC721;

    uint256 public usersCount;
    uint256 public strategiesCount;
    uint256 public tokensCount;
    address public feesReceiver;

    mapping(address => mapping(address => bool)) public tokensWhitelist;
    mapping(address => uint256) public strategyToId;
    mapping(address => uint256) public userAmountStrategies;
    mapping(uint256 => Strategy) public strategies;
    mapping(uint256 => mapping(address => mapping(uint256 => UserPosition)))
        public positions;
    mapping(uint256 => mapping(address => uint256)) public positionsIndex;
    mapping(uint256 => mapping(address => uint256)) public positionsCount;
    mapping(uint256 => TokenInfo) public tokens;
    mapping(address => uint256) public usersToId;
    mapping(uint256 => address) public users;
    mapping(address => EnumerableSetUpgradeable.UintSet) private userToNftIds;

    /**
     * @param strategyId - an ID of an earning strategy.
     * @param positionId - an ID of a position.
     * @param user - a user who makes a staking.
     * @param amount - amount of staked tokens.
     * @param shares - fraction of the user's contribution
     * (calculated from the deposited amount and the total number of tokens)
     */
    event Staked(
        uint256 indexed strategyId,
        uint256 indexed positionId,
        address indexed user,
        uint256 amount,
        uint256 shares
    );

    /**
     * @param strategyId - an ID of an earning strategy.
     * @param positionId - an ID of a position.
     * @param user - a user who makes a withdrawal.
     * @param amount - amount of staked tokens (calculated from input shares).
     * @param shares - fraction of the user's contribution.
     */
    event Withdrawn(
        uint256 indexed strategyId,
        uint256 indexed positionId,
        address indexed user,
        uint256 amount,
        uint256 shares
    );

    /**
     * @param strategyId - an ID of an earning strategy.
     * @param blockNumber - block number in which the compound was made.
     * @param user - a user who makes compound.
     * @param amount - amount of staked tokens (calculated from input shares).
     */
    event Compounded(
        uint256 indexed strategyId,
        uint256 indexed blockNumber,
        address indexed user,
        uint256 amount
    );

    /**
     * @param strategyId - an ID of an earning strategy.
     * @param positionId - an ID of a position.
     * @param user - a user for whom the position was created.
     * @param blockNumber - block number in which the position was created.
     */
    event PositionCreated(
        uint256 indexed strategyId,
        uint256 indexed positionId,
        address indexed user,
        uint256 blockNumber
    );

    /**
     * @param strategyId - an ID of an earning strategy.
     * @param positionId - an ID of a position.
     * @param user - a user whose position is closed.
     * @param blockNumber - block number in which the position was closed.
     */
    event PositionClosed(
        uint256 indexed strategyId,
        uint256 indexed positionId,
        address indexed user,
        uint256 blockNumber
    );

    /**
     * @param strategyId - an ID of an earning strategy.
     * @param from - who sent the position.
     * @param fromPositionId - sender position ID.
     * @param to - recipient.
     * @param toPositionId - id of recipient's position.
     */
    event PositionTransferred(
        uint256 indexed strategyId,
        address indexed from,
        uint256 fromPositionId,
        address indexed to,
        uint256 toPositionId
    );

    modifier onlyAfterLock(
        address owner,
        uint256 strategyId,
        uint256 positionId
    ) {
        _onlyAfterLock(owner, strategyId, positionId);
        _;
    }

    modifier onlyContract(address addressToCheck) {
        _onlyContract(addressToCheck);
        _;
    }

    modifier onlyExistingStrategy(uint256 strategyId) {
        _onlyExistingStrategy(strategyId);
        _;
    }

    modifier onlyValidFees(address strategy, IFees.Fees calldata fees) {
        _onlyValidFees(strategy, fees);
        _;
    }

    modifier onlyValidWithdrawalSharesAmount(
        uint256 strategyId,
        uint256 positionId,
        uint256 shares
    ) {
        _onlyValidWithdrawalSharesAmount(strategyId, positionId, shares);
        _;
    }

    modifier cursorIsNotLessThanOne(uint256 cursor) {
        _cursorIsNotLessThanOne(cursor);
        _;
    }

    modifier cursorIsNotOutOfBounds(uint256 cursor, uint256 bounds) {
        _cursorIsNotOutOfBounds(cursor, bounds);
        _;
    }

    modifier isStrategyActive(uint256 strategyId) {
        _isStrategyActive(strategyId);
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes the contract.
     * @param initialFeesReceiver Arecipient of commissions.
     * @param initialERC721 An address of ERC-721 contract for positions.
     */
    function __Parallax_init(
        address initialFeesReceiver,
        IERC721UpgradeableParallax initialERC721
    ) external initializer {
        __Ownable_init_unchained();
        __ReentrancyGuard_init_unchained();
        __Parallax_init_unchained(initialFeesReceiver, initialERC721);
    }

    /**
     * @dev Whitelists a new token that can be accepted as the token for
     *      deposits and withdraws. Can only be called by the current owner.
     * @param strategyId An ID of an earning strategy. Must be an existing
     *                   earning strategy ID.
     * @param token An ddress of a new token to add.
     */
    function addToken(
        uint256 strategyId,
        address token
    )
        external
        onlyOwner
        onlyContract(token)
        onlyExistingStrategy(strategyId)
        onlyNonZeroAddress(token)
    {
        tokensWhitelist[strategies[strategyId].strategy][token] = true;
    }

    /**
     * @dev Removes a token from a whitelist of tokens that can be accepted as
     *      the tokens for deposits and withdraws. Can only be called by the
     *      current owner.
     * @param strategyId An ID of an earning strategy. Must be an existing
     *                   earning strategy ID.
     * @param token A token to remove.
     */
    function removeToken(
        uint256 strategyId,
        address token
    ) external onlyOwner onlyExistingStrategy(strategyId) {
        tokensWhitelist[strategies[strategyId].strategy][token] = false;
    }

    /**
     * @dev Registers a new earning strategy on this contract. An earning
     *      strategy must be deployed before the calling of this method. Can
     *      only be called by the current owner.
     * @param strategy An address of a new earning strategy that should be added.
     * @param timelock A number of seconds during which users can't withdraw
     *                 their deposits after last deposit. Applies only for
     *                 earning strategy that is adding. Can be updated later.
     * @param cap A cap for the amount of deposited LP tokens.
     * @param rewardPerBlock A reward amount that will be distributed between
     *                       all users in a strategy every block. Can be updated
     *                       later.
     * @param initialFees A fees that will be applied for earning strategy that
     *                    is adding. Currently only withdrawal fee is supported.
     *                    Applies only for earning strategy that is adding. Can
     *                    be updated later. Each fee should contain 2 decimals:
     *                    5 = 0.05%, 10 = 0.1%, 100 = 1%, 1000 = 10%.
     *  @param rewardToken A reward token in which rewards will be paid. Can be
     *                     updated later.
     */
    function addStrategy(
        address strategy,
        uint32 timelock,
        uint256 cap,
        uint256 rewardPerBlock,
        IFees.Fees calldata initialFees,
        IERC20Upgradeable rewardToken,
        bool isActive
    )
        external
        onlyOwner
        onlyContract(strategy)
        onlyValidFees(strategy, initialFees)
    {
        if (strategyToId[strategy] != 0) {
            revert StrategyAlreadyAdded();
        }

        if (address(rewardToken) == address(0) && rewardPerBlock != 0) {
            revert IncorrectRewards();
        }

        ++strategiesCount;

        Strategy storage newStrategy = strategies[strategiesCount];

        newStrategy.fees = initialFees;
        newStrategy.timelock = timelock;
        newStrategy.cap = cap;
        newStrategy.rewardPerBlock = rewardPerBlock;
        newStrategy.strategy = strategy;
        newStrategy.lastUpdatedBlockNumber = block.number;
        newStrategy.rewardToken = rewardToken;
        newStrategy.isActive = isActive;

        strategyToId[strategy] = strategiesCount;
    }

    /**
     * @dev Sets a new receiver for fees from all earning strategies. Can only
     *      be called by the current owner.
     * @param newFeesReceiver A wallet that will receive fees from all earning
     *                        strategies.
     */
    function setFeesReceiver(
        address newFeesReceiver
    ) external onlyOwner onlyNonZeroAddress(newFeesReceiver) {
        feesReceiver = newFeesReceiver;
    }

    /**
     * @dev Sets a new fees for an earning strategy. Can only be called by the
     *      current owner.
     * @param strategyId An ID of an earning strategy. Must be an existing
     *                   earning strategy ID.
     * @param newFees Fees that will be applied for earning strategy. Currently
     *                only withdrawal fee is supported. Each fee should contain
     *                2 decimals: 5 = 0.05%, 10 = 0.1%, 100 = 1%, 1000 = 10%.
     */
    function setFees(
        uint256 strategyId,
        IFees.Fees calldata newFees
    )
        external
        onlyExistingStrategy(strategyId)
        onlyValidFees(strategies[strategyId].strategy, newFees)
        onlyInternalCall
    {
        strategies[strategyId].fees = newFees;
    }

    /**
     * @dev Sets a timelock for withdrawals (in seconds). Timelock - period
     *      during which user is not able to make a withdrawal after last
     *      successful deposit. Can only be called by the current owner.
     * @param strategyId An ID of an earning strategy. Must be an existing
     *                   earning strategy ID.
     * @param timelock A new timelock for withdrawals (in seconds).
     */
    function setTimelock(
        uint256 strategyId,
        uint32 timelock
    ) external onlyExistingStrategy(strategyId) onlyInternalCall {
        strategies[strategyId].timelock = timelock;
    }

    /**
     * @dev Setups a reward amount that will be distributed between all users
     *      in a strategy every block. Can only be called by the current owner.
     * @param strategyId An ID of an earning strategy. Must be an existing
     *                   earning strategy ID.
     * @param newRewardToken A new reward token in which rewards will be paid.
     */
    function setRewardToken(
        uint256 strategyId,
        IERC20Upgradeable newRewardToken
    )
        external
        onlyExistingStrategy(strategyId)
        onlyNonZeroAddress(address(newRewardToken))
    {
        if (address(strategies[strategyId].rewardToken) != address(0)) {
            _onlyInternalCall();
        } else {
            _checkOwner();
        }

        strategies[strategyId].rewardToken = newRewardToken;
    }

    /**
     * @dev Sets a new cap for the amount of deposited LP tokens. A new cap must
     *      be more or equal to the amount of staked LP tokens. Can only be
     *      called by the current owner.
     * @param strategyId An ID of an earning strategy. Must be an existing
     *                   earning strategy ID.
     * @param cap A new cap for the amount of deposited LP tokens which will be
     *            applied for earning strategy.
     */
    function setCap(
        uint256 strategyId,
        uint256 cap
    ) external onlyOwner onlyExistingStrategy(strategyId) {
        if (cap < strategies[strategyId].totalStaked) {
            revert CapTooSmall();
        }

        strategies[strategyId].cap = cap;
    }

    /**
     * @dev Sets a value for an earning strategy (in reward token) after which
     *      compound must be executed. The compound operation is performed
     *      during every deposit and withdrawal. And sometimes there may not be
     *      enough reward tokens to complete all the exchanges and liquidity
     *      additions. As a result, deposit and withdrawal transactions may
     *      fail. To avoid such a problem, this value is provided. And if the
     *      number of rewards is even less than it, compound does not occur.
     *      As soon as there are more of them, a compound immediately occurs in
     *      time of first deposit or withdrawal. Can only be called by the
     *      current owner.
     * @param strategyId An ID of an earning strategy. Must be an existing
     *                   earning strategy ID.
     * @param compoundMinAmount A value in reward token after which compound
     *                          must be executed.
     */
    function setCompoundMinAmount(
        uint256 strategyId,
        uint256 compoundMinAmount
    ) external onlyOwner onlyExistingStrategy(strategyId) {
        IParallaxStrategy(strategies[strategyId].strategy).setCompoundMinAmount(
            compoundMinAmount
        );
    }

    /**
     * @notice Setups a reward amount that will be distributed between all users
     *         in a strategy every block. Can only be called by the current
     *         owner.
     * @param strategyId An ID of an earning strategy. Must be an existing
     *                   earning strategy ID.
     * @param rewardPerBlock A new reward per block.
     */
    function setRewardPerBlock(
        uint256 strategyId,
        uint256 rewardPerBlock
    ) external onlyOwner onlyExistingStrategy(strategyId) {
        _updateStrategyRewards(strategyId);

        strategies[strategyId].rewardPerBlock = rewardPerBlock;
    }

    /**
     * @notice Setups a strategy status. Sets permission or prohibition for
     *         depositing funds on the strategy. Can only be called by the
     *         current owner.
     * @param strategyId An ID of an earning strategy. Must be an existing
     *                   earning strategy ID.
     * @param flag A strategy status. `false` - not active, `true` - active.
     */
    function setStrategyStatus(
        uint256 strategyId,
        bool flag
    ) external onlyOwner onlyExistingStrategy(strategyId) {
        strategies[strategyId].isActive = flag;
    }

    /**
     * @notice Accepts deposits from users. This method accepts ERC-20 LP tokens
     *         that will be used in earning strategy. Appropriate amount of
     *         ERC-20 LP tokens must be approved for earning strategy in which
     *         it will be deposited. Can be called by anyone.
     * @param depositParams A parameters for deposit (for more details see a
     *                      specific earning strategy).
     * @return `positionId` and `true` if a position has just been created.
     */
    function deposit(
        IParallax.DepositLPs memory depositParams
    )
        external
        nonReentrant
        onlyExistingStrategy(depositParams.strategyId)
        isStrategyActive(depositParams.strategyId)
        returns (uint256, bool)
    {
        _compound(
            depositParams.strategyId,
            depositParams.compoundAmountsOutMin
        );

        IParallaxStrategy.DepositLPs memory params = IParallaxStrategy
            .DepositLPs({ amount: depositParams.amount, user: _msgSender() });
        uint256 deposited = IParallaxStrategy(
            strategies[depositParams.strategyId].strategy
        ).depositLPs(params);

        return
            _deposit(
                depositParams.strategyId,
                depositParams.positionId,
                deposited
            );
    }

    /**
     * @notice Accepts deposits from users. This method accepts a group of
     *         different ERC-20 tokens in equal part that will be used in
     *         earning strategy (for more detail s see the specific earning
     *         strategy documentation). Appropriate amount of all ERC-20 tokens
     *         must be approved for earning strategy in which it will be
     *         deposited. Can be called by anyone.
     * @param depositParams A parameters for deposit (for more details see a
     *                      specific earning strategy).
     * @return `positionId` and `true` if a position has just been created.
     */
    function deposit(
        IParallax.DepositTokens memory depositParams
    )
        external
        nonReentrant
        onlyExistingStrategy(depositParams.strategyId)
        isStrategyActive(depositParams.strategyId)
        returns (uint256, bool)
    {
        _compound(
            depositParams.strategyId,
            depositParams.compoundAmountsOutMin
        );

        IParallaxStrategy.DepositTokens memory params = IParallaxStrategy
            .DepositTokens({
                amountsOutMin: depositParams.amountsOutMin,
                amount: depositParams.amount,
                user: _msgSender()
            });
        uint256 deposited = IParallaxStrategy(
            strategies[depositParams.strategyId].strategy
        ).depositTokens(params);

        return
            _deposit(
                depositParams.strategyId,
                depositParams.positionId,
                deposited
            );
    }

    /**
     * @notice Accepts deposits from users. This method accepts ETH tokens that
     *         will be used in earning strategy. ETH tokens must be attached to
     *         the transaction. Can be called by anyone.
     * @param depositParams A parameters for deposit (for more details see a
     *                      specific earning strategy).
     * @return `positionId` and `true` if a position has just been created.
     */
    function deposit(
        IParallax.DepositNativeTokens memory depositParams
    )
        external
        payable
        nonReentrant
        onlyExistingStrategy(depositParams.strategyId)
        isStrategyActive(depositParams.strategyId)
        returns (uint256, bool)
    {
        _compound(
            depositParams.strategyId,
            depositParams.compoundAmountsOutMin
        );

        IParallaxStrategy.SwapNativeTokenAndDeposit
            memory params = IParallaxStrategy.SwapNativeTokenAndDeposit({
                amountsOutMin: depositParams.amountsOutMin,
                paths: depositParams.paths
            });
        uint256 deposited = IParallaxStrategy(
            strategies[depositParams.strategyId].strategy
        ).swapNativeTokenAndDeposit{ value: msg.value }(params);

        return
            _deposit(
                depositParams.strategyId,
                depositParams.positionId,
                deposited
            );
    }

    /**
     * @notice Accepts deposits from users. This method accepts any whitelisted
     *         ERC-20 tokens that will be used in earning strategy. Appropriate
     *         amount of ERC-20 tokens must be approved for earning strategy in
     *         which it will be deposited. Can be called by anyone.
     * @param depositParams A parameters parameters for deposit (for more
     *                      details see a specific earning strategy).
     * @return `positionId` and `true` if a position has just been created.
     */
    function deposit(
        IParallax.DepositERC20Token memory depositParams
    )
        external
        nonReentrant
        onlyExistingStrategy(depositParams.strategyId)
        isStrategyActive(depositParams.strategyId)
        returns (uint256, bool)
    {
        _compound(
            depositParams.strategyId,
            depositParams.compoundAmountsOutMin
        );

        IParallaxStrategy.SwapERC20TokenAndDeposit
            memory params = IParallaxStrategy.SwapERC20TokenAndDeposit({
                amountsOutMin: depositParams.amountsOutMin,
                paths: depositParams.paths,
                amount: depositParams.amount,
                token: depositParams.token,
                user: _msgSender()
            });
        uint256 deposited = IParallaxStrategy(
            strategies[depositParams.strategyId].strategy
        ).swapERC20TokenAndDeposit(params);

        return
            _deposit(
                depositParams.strategyId,
                depositParams.positionId,
                deposited
            );
    }

    /**
     * @notice A withdraws users' deposits + reinvested yield. This method
     *         allows to withdraw ERC-20 LP tokens that were used in earning
     *         strategy. Can be called by anyone.
     * @param withdrawParams A parameters for withdraw (for more details see a
     *                       specific earning strategy).
     * @return `true` if a position was closed.
     */
    function withdraw(
        IParallax.WithdrawLPs memory withdrawParams
    )
        external
        nonReentrant
        onlyAfterLock(
            _msgSender(),
            withdrawParams.strategyId,
            withdrawParams.positionId
        )
        onlyExistingStrategy(withdrawParams.strategyId)
        onlyValidWithdrawalSharesAmount(
            withdrawParams.strategyId,
            withdrawParams.positionId,
            withdrawParams.shares
        )
        returns (bool)
    {
        _compound(
            withdrawParams.strategyId,
            withdrawParams.compoundAmountsOutMin
        );

        (uint256 amount, uint256 earned, bool closed) = _withdraw(
            withdrawParams.strategyId,
            withdrawParams.positionId,
            withdrawParams.shares
        );
        IParallaxStrategy.WithdrawLPs memory params = IParallaxStrategy
            .WithdrawLPs({
                amount: amount,
                earned: earned,
                receiver: _msgSender()
            });

        IParallaxStrategy(strategies[withdrawParams.strategyId].strategy)
            .withdrawLPs(params);

        return closed;
    }

    /**
     * @notice A withdraws users' deposits without reinvested yield. This method
     *         allows to withdraw ERC-20 LP tokens that were used in earning
     *         strategy Can be called by anyone.
     * @param withdrawParams A parameters for withdraw (for more details see a
     *                       specific earning strategy).
     * @return `true` if the position was closed.
     */
    function emergencyWithdraw(
        IParallax.EmergencyWithdraw memory withdrawParams
    )
        external
        nonReentrant
        onlyAfterLock(
            _msgSender(),
            withdrawParams.strategyId,
            withdrawParams.positionId
        )
        onlyExistingStrategy(withdrawParams.strategyId)
        onlyValidWithdrawalSharesAmount(
            withdrawParams.strategyId,
            withdrawParams.positionId,
            withdrawParams.shares
        )
        returns (bool)
    {
        (uint256 amount, uint256 earned, bool closed) = _withdraw(
            withdrawParams.strategyId,
            withdrawParams.positionId,
            withdrawParams.shares
        );
        IParallaxStrategy.WithdrawLPs memory params = IParallaxStrategy
            .WithdrawLPs({
                amount: amount,
                earned: earned,
                receiver: _msgSender()
            });

        IParallaxStrategy(strategies[withdrawParams.strategyId].strategy)
            .withdrawLPs(params);

        return closed;
    }

    /**
     * @notice Withdraws users' deposits + reinvested yield. This method allows
     *         to withdraw a group of ERC-20 tokens in equal parts that were
     *         used in earning strategy (for more details see the specific
     *         earning strategy documentation). Can be called by anyone.
     * @param withdrawParams A parameters for withdraw (for more details see a
     *                       specific earning strategy).
     * @return `true` if a position was closed.
     */
    function withdraw(
        IParallax.WithdrawTokens memory withdrawParams
    )
        external
        nonReentrant
        onlyAfterLock(
            _msgSender(),
            withdrawParams.strategyId,
            withdrawParams.positionId
        )
        onlyExistingStrategy(withdrawParams.strategyId)
        onlyValidWithdrawalSharesAmount(
            withdrawParams.strategyId,
            withdrawParams.positionId,
            withdrawParams.shares
        )
        returns (bool)
    {
        _compound(
            withdrawParams.strategyId,
            withdrawParams.compoundAmountsOutMin
        );

        (uint256 amount, uint256 earned, bool closed) = _withdraw(
            withdrawParams.strategyId,
            withdrawParams.positionId,
            withdrawParams.shares
        );
        IParallaxStrategy.WithdrawTokens memory params = IParallaxStrategy
            .WithdrawTokens({
                amountsOutMin: withdrawParams.amountsOutMin,
                amount: amount,
                earned: earned,
                receiver: _msgSender()
            });

        IParallaxStrategy(strategies[withdrawParams.strategyId].strategy)
            .withdrawTokens(params);

        return closed;
    }

    /**
     * @notice Withdraws users' deposits + reinvested yield. This method allows
     *         to withdraw ETH tokens that were used in earning strategy.Can be
     *         called by anyone.
     * @param withdrawParams A parameters for withdraw (for more details see a
     *                       specific earning strategy).
     * @return `true` if a position was closed.
     */
    function withdraw(
        IParallax.WithdrawNativeToken memory withdrawParams
    )
        external
        nonReentrant
        onlyAfterLock(
            _msgSender(),
            withdrawParams.strategyId,
            withdrawParams.positionId
        )
        onlyExistingStrategy(withdrawParams.strategyId)
        onlyValidWithdrawalSharesAmount(
            withdrawParams.strategyId,
            withdrawParams.positionId,
            withdrawParams.shares
        )
        returns (bool)
    {
        _compound(
            withdrawParams.strategyId,
            withdrawParams.compoundAmountsOutMin
        );

        (uint256 amount, uint256 earned, bool closed) = _withdraw(
            withdrawParams.strategyId,
            withdrawParams.positionId,
            withdrawParams.shares
        );
        IParallaxStrategy.WithdrawAndSwapForNativeToken
            memory params = IParallaxStrategy.WithdrawAndSwapForNativeToken({
                amountsOutMin: withdrawParams.amountsOutMin,
                paths: withdrawParams.paths,
                amount: amount,
                earned: earned,
                receiver: _msgSender()
            });

        IParallaxStrategy(strategies[withdrawParams.strategyId].strategy)
            .withdrawAndSwapForNativeToken(params);

        return closed;
    }

    /**
     * @notice Withdraws users' deposits + reinvested yield. This method allows
     *         to withdraw any whitelisted ERC-20 tokens that were used in
     *         earning strategy. Can be called by anyone.
     * @param withdrawParams A parameters for withdraw (for more details see a
     *                       specific earning strategy).
     * @return `true` if a position was closed.
     */
    function withdraw(
        IParallax.WithdrawERC20Token memory withdrawParams
    )
        external
        nonReentrant
        onlyAfterLock(
            _msgSender(),
            withdrawParams.strategyId,
            withdrawParams.positionId
        )
        onlyExistingStrategy(withdrawParams.strategyId)
        onlyValidWithdrawalSharesAmount(
            withdrawParams.strategyId,
            withdrawParams.positionId,
            withdrawParams.shares
        )
        returns (bool)
    {
        _compound(
            withdrawParams.strategyId,
            withdrawParams.compoundAmountsOutMin
        );

        (uint256 amount, uint256 earned, bool closed) = _withdraw(
            withdrawParams.strategyId,
            withdrawParams.positionId,
            withdrawParams.shares
        );
        IParallaxStrategy.WithdrawAndSwapForERC20Token
            memory params = IParallaxStrategy.WithdrawAndSwapForERC20Token({
                amountsOutMin: withdrawParams.amountsOutMin,
                paths: withdrawParams.paths,
                amount: amount,
                earned: earned,
                token: withdrawParams.token,
                receiver: _msgSender()
            });

        IParallaxStrategy(strategies[withdrawParams.strategyId].strategy)
            .withdrawAndSwapForERC20Token(params);

        return closed;
    }

    /**
     * @notice Claims all rewards from earning strategy and reinvests them to
     *         increase future rewards. Can be called by anyone.
     * @param strategyId An ID of an earning strategy. Must be an existing
     *                   earning strategy ID.
     * @param amountsOutMin An array of minimum values that will be received
     *                      during exchanges, withdrawals or deposits of
     *                      liquidity, etc. The length of the array is unique
     *                      for each earning strategy. See the specific earning
     *                      strategy documentation for more details.
     */
    function compound(
        uint256 strategyId,
        uint256[] memory amountsOutMin
    ) external nonReentrant onlyExistingStrategy(strategyId) {
        _compound(strategyId, amountsOutMin);
    }

    /**
     * @notice Claims tokens that were distributed on users deposit and earned
     *         by a specific position of a user. Can be called by anyone.
     * @param strategyId An ID of an earning strategy. Must be an existing
     *                   earning strategy ID.
     * @param positionId An ID of a position. Must be an existing position ID.
     */
    function claim(
        uint256 strategyId,
        uint256 positionId
    ) external nonReentrant onlyExistingStrategy(strategyId) {
        _claim(strategyId, _msgSender(), positionId);
    }

    /**
     * @notice Adds a new transaction to the execution queue. Can only be called
     *         by the current owner.
     * @param transaction structure of:
     *                    dest - the address on which the method will be called;
     *                    value - the value of wei to send;
     *                    signature - method signature;
     *                    data - method call payload;
     *                    exTime - the time from which the transaction can be
     *                             executed. Must be less than the current
     *                             `block.timestamp` + `DELAY`.
     * @return A transaction hash.
     */
    function addTransaction(
        Timelock.Transaction memory transaction
    ) external onlyOwner returns (bytes32) {
        return _addTransaction(transaction);
    }

    /**
     * @notice Removes a transaction from the execution queue. Can only be
     *         called by the current owner.
     * @param transaction structure of:
     *                    dest - the address on which the method will be called;
     *                    value - the value of wei to send;
     *                    signature - method signature;
     *                    data - method call payload;
     *                    exTime - the time from which the transaction can be
     *                             executed. Must be less than the current
     *                             `block.timestamp` + `DELAY`.
     */
    function removeTransaction(
        Timelock.Transaction memory transaction
    ) external onlyOwner {
        _removeTransaction(transaction);
    }

    /**
     * @notice Executes a transaction from the queue. Can only be called by the
     *         current owner.
     * @param transaction structure of:
     *                    dest - the address on which the method will be called;
     *                    value - the value of wei to send;
     *                    signature - method signature;
     *                    data - method call payload;
     *                    exTime - the time from which the transaction can be
     *                             executed. Must be less than the current
     *                             `block.timestamp` + `DELAY`.
     * @return Returned data.
     */
    function executeTransaction(
        Timelock.Transaction memory transaction
    ) external onlyOwner returns (bytes memory) {
        return _executeTransaction(transaction);
    }

    /**
     * @notice Returns a withdrawal fee for a specified earning strategy.
     *         Can be called by anyone.
     * @param strategy An ddress of an earning strategy to retrieve a withdrawal
     *                 fee.
     * @return A withdrawal fee.
     */
    function getWithdrawalFee(
        address strategy
    ) external view returns (uint256) {
        return strategies[strategyToId[strategy]].fees.withdrawalFee;
    }

    /**
     * @notice Returns an amount of strategy final tokens (LPs) that are staked
     *         under a specified shares amount. Can be called by anyone.
     * @dev Staked == deposited + earned.
     * @param strategyId An ID of an earning strategy. Must be an existing
     *                   earning strategy ID.
     * @param shares An amount of shares for which to calculate a staked
     *               amount of tokens.
     * @return An amount of tokens that are staked under the shares amount.
     */
    function getStakedBySharesAmount(
        uint256 strategyId,
        uint256 shares
    ) external view onlyExistingStrategy(strategyId) returns (uint256) {
        return _getStakedBySharesAmount(strategyId, shares);
    }

    /**
     * @notice Returns an amount of strategy final (LPs) tokens earned by the
     *         specified shares amount in a specified earning strategy. Can be
     *         called by anyone.
     * @param strategyId An ID of an earning strategy. Must be an existing
     *                   earning strategy ID.
     * @param shares An amount of shares for which to calculate an earned
     *               amount of tokens.
     * @return An amount of earned by shares tokens.
     */
    function getEarnedBySharesAmount(
        uint256 strategyId,
        uint256 shares
    ) external view onlyExistingStrategy(strategyId) returns (uint256) {
        return _getEarnedBySharesAmount(strategyId, shares);
    }

    /**
     * @notice Returns an amount of strategy final tokens (LPs) earned by the
     *         specified user in a specified earning strategy. Can be called by
     *         anyone.
     * @param strategyId An ID of an earning strategy. Must be an existing
     *                   earning strategy ID.
     * @param user A user to check earned tokens amount.
     * @param positionId An ID of a position. Must be an existing position ID.
     * @return An amount of earned by user tokens.
     */
    function getEarnedByUserAmount(
        uint256 strategyId,
        address user,
        uint256 positionId
    ) external view onlyExistingStrategy(strategyId) returns (uint256) {
        return
            _getEarnedBySharesAmount(
                strategyId,
                positions[strategyId][user][positionId].shares
            );
    }

    /**
     * @notice Returns claimable by the user amount of reward token in the
     *         position. Can be called by anyone.
     * @param strategyId An ID of an earning strategy. Must be an existing
     *                   earning strategy ID.
     * @param user A user to check earned reward tokens amount.
     * @param positionId An ID of a position. Must be an existing position ID.
     * @return Claimable by the user amount.
     */
    function getClaimableRewards(
        uint256 strategyId,
        address user,
        uint256 positionId
    ) external view returns (uint256) {
        UserPosition memory position = positions[strategyId][user][positionId];
        uint256 newRewards = (_getStakedBySharesAmount(
            strategyId,
            position.shares
        ) * _getUpdatedRewardPerShare(strategyId)) - position.former;
        uint256 claimableRewards = position.reward + newRewards;

        return claimableRewards / 1 ether;
    }

    /**
     * @notice Returns an address of a user by unique ID in an earning strategy.
     *         Can be called by anyone.
     * @param strategyId An ID of an earning strategy. Must be an existing
     *                   earning strategy ID.
     * @param userId An ID for which need to retrieve an address of a user.
     * @return An address of a user by him unique ID.
     */
    function getStrategyUserById(
        uint256 strategyId,
        uint256 userId
    ) external view returns (address) {
        return strategies[strategyId].users[userId];
    }

    /**
     * @notice Returns a unique ID for a user in an earning strategy. Can be
     *         called by anyone.
     * @param strategyId An ID of an earning strategy. Must be an existing
     *                   earning strategy ID.
     * @param user A user for whom to retrieve an ID.
     * @return A unique ID for a user.
     */
    function getIdByUserInStrategy(
        uint256 strategyId,
        address user
    ) external view onlyExistingStrategy(strategyId) returns (uint256) {
        return strategies[strategyId].usersToId[user];
    }

    /**
     * @notice Returns a list of NFT IDs that belongs to a specified user.
     * @param user A user for whom to retrieve a list of his NFT IDs.
     * @param cursor An ID from which to start reading of users from mapping.
     * @param howMany An amount of NFT IDs to retrieve by one request.
     * @return A list of NFT IDs that belongs to a specified user.
     */
    function getNftIdsByUser(
        address user,
        uint256 cursor,
        uint256 howMany
    ) external view cursorIsNotLessThanOne(cursor) returns (uint256[] memory) {
        uint256 upperBound = cursor + howMany;
        uint256 setLength = userToNftIds[user].length();

        if (setLength > 0) {
            _cursorIsNotOutOfBounds(cursor, setLength);
        }

        if (upperBound - 1 > setLength) {
            upperBound = setLength + 1;
            howMany = upperBound - cursor;
        }

        uint256[] memory result = new uint256[](howMany);
        uint256 j = 0;

        for (uint256 i = cursor; i < upperBound; ++i) {
            result[j] = userToNftIds[user].at(i - 1);
            ++j;
        }

        return result;
    }

    /**
     * @notice Returns a list of users that participates at least in one
     *         registered earning strategy. Can be called by anyone.
     * @param cursor An ID from which to start reading of users from mapping.
     * @param howMany An amount of users to retrieve by one request.
     * @return A list of users' addresses.
     */
    function getUsers(
        uint256 cursor,
        uint256 howMany
    )
        external
        view
        cursorIsNotLessThanOne(cursor)
        cursorIsNotOutOfBounds(cursor, usersCount)
        returns (address[] memory)
    {
        uint256 upperBound = cursor + howMany;

        if (upperBound - 1 > usersCount) {
            upperBound = usersCount + 1;
            howMany = upperBound - cursor;
        }

        address[] memory result = new address[](howMany);
        uint256 j = 0;

        for (uint256 i = cursor; i < upperBound; ++i) {
            result[j] = users[i];
            ++j;
        }

        return result;
    }

    /**
     * @notice Returns a list of users that participates in a specified earning
     *         strategy. Can be called by anyone.
     * @param strategyId An ID of an earning strategy. Must be an existing
     *                   earning strategy ID.
     * @param cursor An ID from which to start reading of users from mapping.
     * @param howMany An amount of users to retrieve by one request.
     * @return A list of users' addresses.
     */
    function getUsersByStrategy(
        uint256 strategyId,
        uint256 cursor,
        uint256 howMany
    )
        external
        view
        onlyExistingStrategy(strategyId)
        cursorIsNotLessThanOne(cursor)
        returns (address[] memory)
    {
        Strategy storage strategy = strategies[strategyId];

        _cursorIsNotOutOfBounds(cursor, strategy.usersCount);

        uint256 upperBound = cursor + howMany;

        if (upperBound - 1 > strategy.usersCount) {
            upperBound = strategy.usersCount + 1;
            howMany = upperBound - cursor;
        }

        address[] memory result = new address[](howMany);
        uint256 j = 0;

        for (uint256 i = cursor; i < upperBound; ++i) {
            result[j] = strategy.users[i];
            ++j;
        }

        return result;
    }

    /// @inheritdoc ITokensRescuer
    function rescueNativeToken(
        uint256 amount,
        address receiver
    ) external onlyOwner {
        _rescueNativeToken(amount, receiver);
    }

    /**
     * @dev Withdraws an ETH token that accidentally ended up on an earning
     *      strategy contract and cannot be used in any way. Can only be called
     *      by the current owner.
     * @param strategyId An ID of an earning strategy. Must be an existing
     *                   earning strategy ID.
     * @param amount A number of tokens to withdraw from this contract.
     * @param receiver A wallet that will receive withdrawing tokens.
     */
    function rescueNativeToken(
        uint256 strategyId,
        uint256 amount,
        address receiver
    ) external onlyOwner onlyExistingStrategy(strategyId) {
        IParallaxStrategy(strategies[strategyId].strategy).rescueNativeToken(
            amount,
            receiver
        );
    }

    /// @inheritdoc ITokensRescuer
    function rescueERC20Token(
        address token,
        uint256 amount,
        address receiver
    ) external onlyOwner {
        _rescueERC20Token(token, amount, receiver);
    }

    /**
     * @dev Withdraws an ERC-20 token that accidentally ended up on an earning
     *      strategy contract and cannot be used in any way. Can only be called
     *      by the current owner.
     * @param strategyId An ID of an earning strategy. Must be an existing
     *                   earning strategy ID.
     * @param token A number of tokens to withdraw from this contract.
     * @param amount A number of tokens to withdraw from this contract.
     * @param receiver A wallet that will receive withdrawing tokens.
     */
    function rescueERC20Token(
        uint256 strategyId,
        address token,
        uint256 amount,
        address receiver
    ) external onlyOwner onlyExistingStrategy(strategyId) {
        IParallaxStrategy(strategies[strategyId].strategy).rescueERC20Token(
            token,
            amount,
            receiver
        );
    }

    /**
     * @notice Safely transfers ERC-721 token (user position), checking first
     *         that recipient's contract are aware of the ERC-721 protocol to
     *         prevent tokens from being forever locked. Can be called by anyone.
     * @param from A wallet from which token (user position) will be transferred.
     * @param to A wallet to which token (user position) will be transferred.
     * @param tokenId An ID of token to transfer.
     * @param data Additional encoded data that can be used somehow in time of
     *             tokens (users' positions) transfer.
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) public nonReentrant {
        address owner = ERC721.ownerOf(tokenId);
        address sender = _msgSender();

        if (
            sender != owner &&
            !ERC721.isApprovedForAll(owner, sender) &&
            ERC721.getApproved(tokenId) != sender
        ) {
            revert CallerIsNotOwnerOrApproved();
        }

        ERC721.safeTransferFrom(from, to, tokenId, data);

        userToNftIds[from].remove(tokenId);
        userToNftIds[to].add(tokenId);

        _transferPositionFrom(from, to, tokenId);
    }

    /**
     * @dev Initializes the contract (unchained).
     * @param initialFeesReceiver A recipient of commissions.
     * @param initialERC721 An address of ERC-721 contract for positions.
     */
    function __Parallax_init_unchained(
        address initialFeesReceiver,
        IERC721UpgradeableParallax initialERC721
    ) internal onlyInitializing onlyNonZeroAddress(initialFeesReceiver) {
        feesReceiver = initialFeesReceiver;
        ERC721 = initialERC721;
    }

    /**
     * @notice Allows to update position information at the time of deposit.
     * @param strategyId An ID of an earning strategy.
     * @param positionId An ID of a position.
     * @param amount An amount of staked tokens (LPs).
     * @return Position ID and position status (created or updated).
     */
    function _deposit(
        uint256 strategyId,
        uint256 positionId,
        uint256 amount
    ) private returns (uint256, bool) {
        uint256 cap = strategies[strategyId].cap;

        if (cap > 0 && strategies[strategyId].totalStaked + amount > cap) {
            revert CapExceeded();
        }

        bool created;

        if (positionId == 0) {
            positionId = ++positionsIndex[strategyId][_msgSender()];
            ++positionsCount[strategyId][_msgSender()];

            _addNewUserIfNeeded(strategyId, _msgSender());

            uint256 tokenId = tokensCount;

            positions[strategyId][_msgSender()][positionId].tokenId = tokenId;
            positions[strategyId][_msgSender()][positionId].created = true;

            tokens[tokenId].strategyId = strategyId;
            tokens[tokenId].positionId = positionId;

            ERC721.mint(_msgSender(), tokenId);

            userToNftIds[_msgSender()].add(tokenId);

            ++tokensCount;

            created = true;

            emit PositionCreated(
                strategyId,
                positionId,
                _msgSender(),
                block.number
            );
        } else {
            UserPosition memory positionToCheck = positions[strategyId][
                _msgSender()
            ][positionId];

            _onlyExistingPosition(positionToCheck);
        }

        uint256 totalShares = strategies[strategyId].totalShares;
        uint256 shares = totalShares == 0
            ? amount
            : (amount * totalShares) / strategies[strategyId].totalStaked;
        uint256 rewardPerShare = strategies[strategyId].rewardPerShare;
        UserPosition storage position = positions[strategyId][_msgSender()][
            positionId
        ];

        position.reward +=
            (_getStakedBySharesAmount(strategyId, position.shares) *
                rewardPerShare) -
            position.former;
        position.shares += shares;
        position.former =
            _getStakedBySharesAmount(strategyId, position.shares) *
            rewardPerShare;
        position.lastStakedBlockNumber = block.number;
        position.lastStakedTimestamp = uint32(block.timestamp);

        strategies[strategyId].totalDeposited += amount;
        strategies[strategyId].totalStaked += amount;
        strategies[strategyId].totalShares += shares;

        emit Staked(strategyId, positionId, _msgSender(), amount, shares);

        return (positionId, created);
    }

    /**
     * @notice Allows to update position information at the time of withdrawal.
     * @param strategyId An ID of an earning strategy.
     * @param positionId An ID of a position.
     * @param shares An amount of shares for which to calculate a staked amount
     *               of tokens.
     * @return Staked by shares amount, earned by shares amount, and position
     *         status.
     */
    function _withdraw(
        uint256 strategyId,
        uint256 positionId,
        uint256 shares
    ) private returns (uint256, uint256, bool) {
        UserPosition storage position = positions[strategyId][_msgSender()][
            positionId
        ];

        _onlyExistingPosition(position);

        uint256 stakedBySharesAmount = _getStakedBySharesAmount(
            strategyId,
            shares
        );
        uint256 earnedBySharesAmount = _getEarnedBySharesAmount(
            strategyId,
            shares
        );
        uint256 rewardPerShare = strategies[strategyId].rewardPerShare;
        bool closed;

        position.reward +=
            (_getStakedBySharesAmount(strategyId, position.shares) *
                rewardPerShare) -
            position.former;
        position.shares -= shares;
        position.former =
            _getStakedBySharesAmount(strategyId, position.shares) *
            rewardPerShare;

        strategies[strategyId].totalDeposited -=
            stakedBySharesAmount -
            earnedBySharesAmount;
        strategies[strategyId].totalStaked -= stakedBySharesAmount;
        strategies[strategyId].totalShares -= shares;

        if (position.shares == 0) {
            position.closed = true;
            --positionsCount[strategyId][_msgSender()];

            _deleteUserIfNeeded(strategyId, _msgSender());

            ERC721.burn(position.tokenId);

            userToNftIds[_msgSender()].remove(position.tokenId);

            closed = true;

            emit PositionClosed(
                strategyId,
                positionId,
                _msgSender(),
                block.number
            );
        }

        emit Withdrawn(
            strategyId,
            positionId,
            _msgSender(),
            stakedBySharesAmount,
            shares
        );

        return (stakedBySharesAmount, earnedBySharesAmount, closed);
    }

    /**
     * @notice Claims all rewards from an earning strategy and reinvests them to
     *         increase future rewards.
     * @param strategyId An ID of an earning strategy.
     * @param amountsOutMin An array of minimum values that will be received
     *                      during exchanges, withdrawals or deposits of
     *                      liquidity, etc. The length of the array is unique
     *                      for each earning strategy. See the specific earning
     *                      strategy documentation for more details.
     */
    function _compound(
        uint256 strategyId,
        uint256[] memory amountsOutMin
    ) private {
        _updateStrategyRewards(strategyId);

        uint256 compounded = IParallaxStrategy(strategies[strategyId].strategy)
            .compound(amountsOutMin);

        strategies[strategyId].totalStaked += compounded;
        strategies[strategyId].lastCompoundTimestamp = block.timestamp;

        emit Compounded(strategyId, block.number, _msgSender(), compounded);
    }

    /**
     * @notice Сlaims tokens that were distributed on users deposit and earned
     *         by a specific position of a user.
     * @param strategyId An ID of an earning strategy.
     * @param positionId An ID of a position.
     */
    function _claim(
        uint256 strategyId,
        address user,
        uint256 positionId
    ) private {
        _updateStrategyRewards(strategyId);

        UserPosition storage position = positions[strategyId][user][positionId];
        uint256 rewardPerShare = strategies[strategyId].rewardPerShare;

        position.reward +=
            (_getStakedBySharesAmount(strategyId, position.shares) *
                rewardPerShare) -
            position.former;

        uint256 value = position.reward / 1 ether;
        IERC20Upgradeable rewardToken = IERC20Upgradeable(
            strategies[strategyId].rewardToken
        );

        if (value == 0) return;

        if (rewardToken.balanceOf(address(this)) >= value) {
            position.reward -= value * 1 ether;
            position.former =
                _getStakedBySharesAmount(strategyId, position.shares) *
                rewardPerShare;

            rewardToken.safeTransfer(user, value);
        } else {
            revert NoTokensToCLaim();
        }
    }

    /**
     * @notice Allows to transfer a position to another user. Also, monitors
     *         user migration (if this was a last position for a sender, or a
     *         first position for a recipient). It is important to note that
     *         position of a sender is not deleted, it is only closed. A sender
     *         can claim rewards after a position transfer. Timelock for
     *         withdrawal remains the same.
     * @param from A wallet from which token (user position) will be transferred.
     * @param to A wallet to which token (user position) will be transferred.
     * @param tokenId An ID of a token to transfer which is related to user
     *                position.
     */
    function _transferPositionFrom(
        address from,
        address to,
        uint256 tokenId
    ) private {
        TokenInfo storage tokenInfo = tokens[tokenId];
        uint256 strategyId = tokenInfo.strategyId;

        uint256 fromPositionId = tokenInfo.positionId;
        uint256 toPositionId = ++positionsIndex[strategyId][to];

        if (from != to) {
            ++positionsCount[strategyId][to];
            --positionsCount[strategyId][from];

            _addNewUserIfNeeded(strategyId, to);
            _deleteUserIfNeeded(strategyId, from);
        }

        tokenInfo.positionId = toPositionId;

        UserPosition storage fromUserPosition = positions[strategyId][from][
            fromPositionId
        ];
        UserPosition storage toUserPosition = positions[strategyId][to][
            toPositionId
        ];

        _updateStrategyRewards(strategyId);

        uint256 rewardPerShare = strategies[strategyId].rewardPerShare;

        fromUserPosition.reward +=
            (_getStakedBySharesAmount(strategyId, fromUserPosition.shares) *
                rewardPerShare) -
            fromUserPosition.former;

        fromUserPosition.former = 0;

        toUserPosition.tokenId = tokenId;
        toUserPosition.shares = fromUserPosition.shares;
        toUserPosition.lastStakedBlockNumber = fromUserPosition
            .lastStakedBlockNumber;
        toUserPosition.lastStakedTimestamp = fromUserPosition
            .lastStakedTimestamp;
        toUserPosition.created = true;

        fromUserPosition.shares = 0;
        fromUserPosition.closed = true;

        emit PositionTransferred(
            strategyId,
            from,
            fromPositionId,
            to,
            tokenInfo.positionId
        );
    }

    /**
     * @notice Updates `rewardPerShare` and `lastUpdatedBlockNumber`.
     * @param strategyId An ID of an earning strategy.
     */
    function _updateStrategyRewards(uint256 strategyId) private {
        Strategy storage strategy = strategies[strategyId];

        strategy.rewardPerShare = _getUpdatedRewardPerShare(strategyId);
        strategy.lastUpdatedBlockNumber = block.number;
    }

    /**
     * @notice Increases a number of user positions by 1. Also, adds a user to
     *         a strategy and parallax if it was his first position in a
     *         strategy and parallax.
     * @param strategyId An ID of an earning strategy.
     * @param user A user to check his positions count.
     */
    function _addNewUserIfNeeded(uint256 strategyId, address user) private {
        if (positionsCount[strategyId][user] == 1) {
            Strategy storage strategy = strategies[strategyId];

            ++strategy.usersCount;
            ++userAmountStrategies[user];

            strategy.users[strategy.usersCount] = user;
            strategy.usersToId[user] = strategy.usersCount;

            if (userAmountStrategies[user] == 1) {
                ++usersCount;

                users[usersCount] = user;
                usersToId[user] = usersCount;
            }
        }
    }

    /**
     * @notice Decreases a number of user positions by 1. Also, removes a user
     *         from a strategy and parallax if that was his last position in a
     *         strategy and parallax.
     * @param strategyId An ID of an earning strategy.
     * @param user A user to check his positions count.
     */
    function _deleteUserIfNeeded(uint256 strategyId, address user) private {
        if (positionsCount[strategyId][user] == 0) {
            Strategy storage strategy = strategies[strategyId];
            uint256 userId = strategy.usersToId[user];
            address lastUser = strategy.users[strategy.usersCount];

            strategy.users[userId] = lastUser;
            strategy.usersToId[lastUser] = userId;

            delete strategy.users[strategy.usersCount];
            delete strategy.usersToId[user];

            --strategies[strategyId].usersCount;
            --userAmountStrategies[user];

            if (userAmountStrategies[user] == 0) {
                uint256 globalUserId = usersToId[user];
                address globalLastUser = users[usersCount];

                users[globalUserId] = globalLastUser;
                usersToId[globalLastUser] = globalUserId;

                delete users[usersCount];
                delete usersToId[user];

                --usersCount;
            }
        }
    }

    /**
     * @notice Allows to get an updated reward per share.
     * @dev The value of updated reward depends on the difference between the
     *      current `block.number` and the `block.number` in which the call
     *      `_updateStrategyRewards` was made.
     * @param strategyId An ID of an earning strategy.
     * @return Updated (actual) rewardPerShare.
     */
    function _getUpdatedRewardPerShare(
        uint256 strategyId
    ) private view returns (uint256) {
        Strategy storage strategy = strategies[strategyId];

        uint256 _rewardPerShare = strategy.rewardPerShare;
        uint256 _totalStaked = strategy.totalStaked;

        if (_totalStaked != 0) {
            uint256 _blockDelta = block.number -
                strategy.lastUpdatedBlockNumber;
            uint256 _reward = _blockDelta * strategy.rewardPerBlock;

            _rewardPerShare += (_reward * 1 ether) / _totalStaked;
        }

        return _rewardPerShare;
    }

    /**
     * @notice returns an amount of strategy final tokens (LPs) that are staked
     *         under a specified shares amount.
     * @param strategyId An ID of an earning strategy.
     * @param shares An amount of shares for which to calculate a staked
     *               amount of tokens.
     * @return An amount of tokens that are staked under the shares amount.
     */
    function _getStakedBySharesAmount(
        uint256 strategyId,
        uint256 shares
    ) private view returns (uint256) {
        uint256 totalShares = strategies[strategyId].totalShares;

        return
            totalShares == 0
                ? 0
                : (strategies[strategyId].totalStaked * shares) / totalShares;
    }

    /**
     * @notice Returns an amount of strategy final tokens (LPs) earned by the
     *         specified shares amount in a specified earning strategy.
     * @param strategyId An ID of an earning strategy.
     * @param shares An amount of shares for which to calculate an earned
     *               amount of tokens.
     * @return An amount of earned by shares tokens (LPs).
     */
    function _getEarnedBySharesAmount(
        uint256 strategyId,
        uint256 shares
    ) private view returns (uint256) {
        uint256 totalShares = strategies[strategyId].totalShares;

        if (totalShares == 0) {
            revert OnlyNonZeroTotalSharesValue();
        }

        uint256 totalEarnedAmount = strategies[strategyId].totalStaked -
            strategies[strategyId].totalDeposited;
        uint256 earnedByShares = (totalEarnedAmount * shares) / totalShares;

        return earnedByShares;
    }

    /**
     * @notice Checks if a user can make a withdrawal. It depends on
     *         `lastStakedTimestamp` for a user and timelock duration of
     *          strategy. Fails if timelock is not finished.
     * @param owner An owner of a position.
     * @param strategyId An ID of an earning strategy.
     * @param positionId An ID of a position.
     */
    function _onlyAfterLock(
        address owner,
        uint256 strategyId,
        uint256 positionId
    ) private view {
        uint32 timeDifference = uint32(block.timestamp) -
            positions[strategyId][owner][positionId].lastStakedTimestamp;
        uint32 timeLock = strategies[strategyId].timelock;

        if (timeDifference < timeLock) {
            revert OnlyAfterLock(timeLock - timeDifference);
        }
    }

    /**
     * @notice Сhecks if provided address is a contract address. Fails otherwise.
     * @param addressToCheck An address to check.
     */
    function _onlyContract(address addressToCheck) private view {
        if (!AddressUpgradeable.isContract(addressToCheck)) {
            revert OnlyContractAddress();
        }
    }

    /**
     * @notice Сhecks if there is strategy for the given ID. Fails otherwise.
     * @param strategyId An ID of an earning strategy.
     */
    function _onlyExistingStrategy(uint256 strategyId) private view {
        if (strategyId > strategiesCount || strategyId == 0) {
            revert OnlyExistStrategy();
        }
    }

    /**
     * @notice Сhecks if the position is open. Fails otherwise.
     * @param position A position info.
     */
    function _onlyExistingPosition(UserPosition memory position) private pure {
        if (position.shares == 0) {
            revert OnlyExistPosition();
        }
    }

    /**
     * @notice Checks the upper bound of the withdrawal commission. Fee must be
     *         less than or equal to maximum possible fee. Fails otherwise.
     * @param strategy An address of an earning strategy.
     * @param fees A commission info.
     */
    function _onlyValidFees(
        address strategy,
        IFees.Fees calldata fees
    ) private view {
        IFees.Fees memory maxStrategyFees = IParallaxStrategy(strategy)
            .getMaxFees();

        if (fees.withdrawalFee > maxStrategyFees.withdrawalFee) {
            revert OnlyValidFees();
        }
    }

    /**
     * @notice Checks if provided shares amount is less than or equal to user's
     *         shares balance. Fails otherwise.
     * @param strategyId An ID of an earning strategy.
     * @param positionId An ID of a position.
     * @param shares A fraction of the user's contribution.
     */
    function _onlyValidWithdrawalSharesAmount(
        uint256 strategyId,
        uint256 positionId,
        uint256 shares
    ) private view {
        if (shares > positions[strategyId][_msgSender()][positionId].shares) {
            revert OnlyValidWithdrawalSharesAmount();
        }
    }

    /**
     * @notice Checks if cursor is greater than zero. Fails otherwise.
     * @param cursor A first user index from which we start a sample of users.
     */
    function _cursorIsNotLessThanOne(uint256 cursor) private pure {
        if (cursor == 0) {
            revert CursorIsLessThanOne();
        }
    }

    /**
     * @notice Checks if cursor is less than or equal to upper bound. Fails
     *         otherwise.
     * @param cursor A first user index from which we start a sample of users.
     * @param bounds An upper bound.
     */
    function _cursorIsNotOutOfBounds(
        uint256 cursor,
        uint256 bounds
    ) private pure {
        if (cursor > bounds) {
            revert CursorOutOfBounds();
        }
    }

    /**
     * @notice Checks if a strategy is active. Fails otherwise.
     * @param strategyId An ID of an earning strategy to check.
     */
    function _isStrategyActive(uint256 strategyId) private view {
        if (!strategies[strategyId].isActive) {
            revert OnlyActiveStrategy();
        }
    }
}

