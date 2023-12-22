//SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

import "./SafeERC20Upgradeable.sol";
import "./OwnableUpgradeable.sol";

import "./EnumerableSetUpgradeable.sol";

import "./ReentrancyGuardUpgradeable.sol";

import "./AddressUpgradeable.sol";

import "./IERC721MintableBurnable.sol";
import "./IParallaxStrategy.sol";
import "./IParallaxAndromeda.sol";

import "./TokensRescuer.sol";
import "./Timelock.sol";

error OnlyNonZeroTotalSharesValue();
error OnlyActiveStrategy();
error OnlyValidFee();
error OnlyExistPosition();
error OnlyExistStrategy();
error OnlyContractAddress();
error OnlyAfterLock(uint32 remainTime);
error OnlyValidWithdrawalSharesAmount();
error OnlyERC721();
error CapExceeded();
error CapTooSmall();
error CallerIsNotOwnerOrApproved();
error NoTokensToClaim();
error StrategyAlreadyAdded();
error IncorrectRewards();
error IncorrectEthAmount();
error OnlyCorrectArrayLength();

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
 */
contract ParallaxAndromedaUpgradeable is
    IParallaxAndromeda,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    TokensRescuer,
    Timelock
{
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    IERC721MintableBurnable public ERC721;

    uint256 public usersCount;
    uint256 public strategiesCount;
    uint256 public tokensCount;
    address public feesReceiver;

    mapping(address => mapping(address => bool)) public tokensWhitelist;
    mapping(address => uint256) public strategyToId;
    mapping(address => uint256) public userAmountStrategies;
    mapping(address => mapping(uint256 => bool)) public userIsActiveInStrategy;
    mapping(uint256 => Strategy) public strategies;

    mapping(address => mapping(uint256 => uint256)) public positionsToTokenId;
    mapping(uint256 => mapping(uint256 => UserPosition))
        public tokenIdToPositions;
    mapping(uint256 => uint256) public tokenIdToPositionId;

    mapping(address => uint256) public positionsCount;
    mapping(uint256 => mapping(address => uint256)) public strategyUsersToId;
    mapping(uint256 => mapping(uint256 => address)) public strategyUsers;

    mapping(address => uint256) public usersToId;
    mapping(uint256 => address) public users;
    mapping(address => EnumerableSetUpgradeable.UintSet) private userToNftIds;

    modifier onlyContract(address addressToCheck) {
        _onlyContract(addressToCheck);
        _;
    }

    modifier onlyExistingStrategy(uint256 strategyId) {
        _onlyExistingStrategy(strategyId);
        _;
    }

    modifier onlyValidFee(address strategy, uint256 fee) {
        _onlyValidFee(strategy, fee);
        _;
    }

    modifier onlyValidWithdrawalSharesAmount(
        uint256 strategyId,
        address user,
        uint256 positionId,
        uint256 shares
    ) {
        _onlyValidWithdrawalSharesAmount(strategyId, user, positionId, shares);
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
    function __ParallaxAndromeda_init(
        address initialFeesReceiver,
        IERC721MintableBurnable initialERC721
    ) external initializer {
        __Ownable_init_unchained();
        __ReentrancyGuard_init_unchained();
        __ParallaxAndromeda_init_unchained(initialFeesReceiver, initialERC721);
    }

    /// @inheritdoc IParallax
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

    /// @inheritdoc IParallax
    function removeToken(
        uint256 strategyId,
        address token
    ) external onlyOwner onlyExistingStrategy(strategyId) {
        tokensWhitelist[strategies[strategyId].strategy][token] = false;
    }

    /// @inheritdoc IParallax
    function addStrategy(
        address strategy,
        uint32 timelock,
        uint256 cap,
        uint256 rewardPerBlock,
        uint256 initialFee,
        IERC20Upgradeable rewardToken,
        bool isActive
    )
        external
        onlyOwner
        onlyContract(strategy)
        onlyValidFee(strategy, initialFee)
    {
        if (strategyToId[strategy] != 0) {
            revert StrategyAlreadyAdded();
        }

        if (address(rewardToken) == address(0) && rewardPerBlock != 0) {
            revert IncorrectRewards();
        }

        ++strategiesCount;

        Strategy storage newStrategy = strategies[strategiesCount];

        newStrategy.fee = initialFee;
        newStrategy.timelock = timelock;
        newStrategy.cap = cap;
        newStrategy.rewardPerBlock = rewardPerBlock;
        newStrategy.strategy = strategy;
        newStrategy.lastUpdatedBlockNumber = block.number;
        newStrategy.rewardToken = rewardToken;
        newStrategy.isActive = isActive;

        strategyToId[strategy] = strategiesCount;
    }

    /// @inheritdoc IParallax
    function setFeesReceiver(
        address newFeesReceiver
    ) external onlyOwner onlyNonZeroAddress(newFeesReceiver) {
        feesReceiver = newFeesReceiver;
    }

    /// @inheritdoc IParallax
    function setFee(
        uint256 strategyId,
        uint256 newFee
    )
        external
        onlyExistingStrategy(strategyId)
        onlyValidFee(strategies[strategyId].strategy, newFee)
        onlyOwner
    {
        strategies[strategyId].fee = newFee;
    }

    /// @inheritdoc IParallax
    function setTimelock(
        uint256 strategyId,
        uint32 timelock
    ) external onlyExistingStrategy(strategyId) onlyInternalCall {
        strategies[strategyId].timelock = timelock;
    }

    /// @inheritdoc IParallax
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

    /// @inheritdoc IParallax
    function setCap(
        uint256 strategyId,
        uint256 cap
    ) external onlyOwner onlyExistingStrategy(strategyId) {
        if (cap < strategies[strategyId].totalStaked) {
            revert CapTooSmall();
        }

        strategies[strategyId].cap = cap;
    }

    /// @inheritdoc IParallax
    function setCompoundMinAmount(
        uint256 strategyId,
        uint256 compoundMinAmount
    ) external onlyOwner onlyExistingStrategy(strategyId) {
        IParallaxStrategy(strategies[strategyId].strategy).setCompoundMinAmount(
            compoundMinAmount
        );
    }

    /// @inheritdoc IParallax
    function setRewardPerBlock(
        uint256 strategyId,
        uint256 rewardPerBlock
    ) external onlyOwner onlyExistingStrategy(strategyId) {
        _updateStrategyRewards(strategyId);

        strategies[strategyId].rewardPerBlock = rewardPerBlock;
    }

    /// @inheritdoc IParallax
    function setStrategyStatus(
        uint256 strategyId,
        bool flag
    ) external onlyOwner onlyExistingStrategy(strategyId) {
        strategies[strategyId].isActive = flag;
    }

    /// @inheritdoc IParallaxAndromeda
    function depositLPs(
        address holder,
        uint256 positionId,
        DepositAndCompoundParams[] memory params
    ) external nonReentrant {
        positionId = _createPositionIfNeeded(holder, positionId);

        for (uint256 i = 0; i < params.length; ++i) {
            DepositAndCompoundParams memory currParams = params[i];

            _beforeDeposit(currParams);

            uint256 deposited = IParallaxStrategy(
                strategies[currParams.depositParams.strategyId].strategy
            ).depositLPs(
                    _depositParamsAdapter(
                        _msgSender(),
                        holder,
                        positionId,
                        currParams.depositParams
                    )
                );

            _updatePosition(
                currParams.depositParams,
                _msgSender(),
                holder,
                positionId,
                deposited
            );
        }
    }

    /// @inheritdoc IParallaxAndromeda
    function depositTokens(
        address holder,
        uint256 positionId,
        DepositAndCompoundParams[] memory params
    ) external nonReentrant {
        positionId = _createPositionIfNeeded(holder, positionId);

        for (uint256 i = 0; i < params.length; ++i) {
            DepositAndCompoundParams memory currParams = params[i];

            _beforeDeposit(currParams);

            uint256 deposited = IParallaxStrategy(
                strategies[currParams.depositParams.strategyId].strategy
            ).depositTokens(
                    _depositParamsAdapter(
                        _msgSender(),
                        holder,
                        positionId,
                        currParams.depositParams
                    )
                );

            _updatePosition(
                currParams.depositParams,
                _msgSender(),
                holder,
                positionId,
                deposited
            );
        }
    }

    /// @inheritdoc IParallaxAndromeda
    function depositAndSwapNativeToken(
        address holder,
        uint256 positionId,
        DepositAndCompoundParams[] memory params
    ) external payable nonReentrant {
        uint256 ethSum;
        positionId = _createPositionIfNeeded(holder, positionId);

        for (uint256 i = 0; i < params.length; ++i) {
            DepositAndCompoundParams memory currParams = params[i];

            if (currParams.depositParams.amounts.length == 0) {
                revert OnlyCorrectArrayLength();
            }

            ethSum += currParams.depositParams.amounts[0];

            _beforeDeposit(currParams);

            uint256 deposited = IParallaxStrategy(
                strategies[currParams.depositParams.strategyId].strategy
            ).depositAndSwapNativeToken{
                value: currParams.depositParams.amounts[0]
            }(
                _depositParamsAdapter(
                    _msgSender(),
                    holder,
                    positionId,
                    currParams.depositParams
                )
            );

            _updatePosition(
                currParams.depositParams,
                _msgSender(),
                holder,
                positionId,
                deposited
            );
        }

        if (ethSum > msg.value) {
            revert IncorrectEthAmount();
        } else if (ethSum < msg.value) {
            payable(_msgSender()).transfer(msg.value - ethSum);
        }
    }

    /// @inheritdoc IParallaxAndromeda
    function depositAndSwapERC20Token(
        address holder,
        uint256 positionId,
        DepositAndCompoundParams[] memory params
    ) external nonReentrant {
        positionId = _createPositionIfNeeded(holder, positionId);

        for (uint256 i = 0; i < params.length; ++i) {
            DepositAndCompoundParams memory currParams = params[i];

            if (currParams.depositParams.data.length == 0) {
                revert OnlyCorrectArrayLength();
            }

            _beforeDeposit(currParams);

            address token = address(
                uint160(bytes20(currParams.depositParams.data[0]))
            );
            address strategy = strategies[currParams.depositParams.strategyId]
                .strategy;

            _transferAndApprove(
                strategy,
                token,
                currParams.depositParams.amounts[0]
            );

            uint256 deposited = IParallaxStrategy(strategy)
                .depositAndSwapERC20Token(
                    _depositParamsAdapter(
                        address(this),
                        holder,
                        positionId,
                        currParams.depositParams
                    )
                );

            _updatePosition(
                currParams.depositParams,
                _msgSender(),
                holder,
                positionId,
                deposited
            );
        }
    }

    /// @inheritdoc IParallaxAndromeda
    function withdrawLPs(
        WithdrawAndCompoundParams[] memory params
    ) external nonReentrant {
        for (uint256 i = 0; i < params.length; ++i) {
            WithdrawAndCompoundParams memory currParams = params[i];

            (uint256 amount, uint256 earned) = _withdraw(currParams, true);

            IParallaxStrategy(
                strategies[currParams.withdrawParams.strategyId].strategy
            ).withdrawLPs(
                    _withdrawParamsAdapter(
                        currParams.withdrawParams,
                        _msgSender(),
                        amount,
                        earned
                    )
                );
        }
    }

    /// @inheritdoc IParallaxAndromeda
    function emergencyWithdraw(
        WithdrawAndCompoundParams[] memory params
    ) external nonReentrant {
        for (uint256 i = 0; i < params.length; ++i) {
            WithdrawAndCompoundParams memory currParams = params[i];

            (uint256 amount, uint256 earned) = _withdraw(currParams, false);

            IParallaxStrategy(
                strategies[currParams.withdrawParams.strategyId].strategy
            ).withdrawLPs(
                    _withdrawParamsAdapter(
                        currParams.withdrawParams,
                        _msgSender(),
                        amount,
                        earned
                    )
                );
        }
    }

    /// @inheritdoc IParallaxAndromeda
    function withdrawTokens(
        WithdrawAndCompoundParams[] memory params
    ) external nonReentrant {
        for (uint256 i = 0; i < params.length; ++i) {
            WithdrawAndCompoundParams memory currParams = params[i];

            (uint256 amount, uint256 earned) = _withdraw(currParams, true);

            IParallaxStrategy(
                strategies[currParams.withdrawParams.strategyId].strategy
            ).withdrawTokens(
                    _withdrawParamsAdapter(
                        currParams.withdrawParams,
                        _msgSender(),
                        amount,
                        earned
                    )
                );
        }
    }

    /// @inheritdoc IParallaxAndromeda
    function withdrawAndSwapForNativeToken(
        WithdrawAndCompoundParams[] memory params
    ) external nonReentrant {
        for (uint256 i = 0; i < params.length; ++i) {
            WithdrawAndCompoundParams memory currParams = params[i];

            (uint256 amount, uint256 earned) = _withdraw(currParams, true);

            IParallaxStrategy(
                strategies[currParams.withdrawParams.strategyId].strategy
            ).withdrawAndSwapForNativeToken(
                    _withdrawParamsAdapter(
                        currParams.withdrawParams,
                        _msgSender(),
                        amount,
                        earned
                    )
                );
        }
    }

    /// @inheritdoc IParallaxAndromeda
    function withdrawAndSwapForERC20Token(
        WithdrawAndCompoundParams[] memory params
    ) external nonReentrant {
        for (uint256 i = 0; i < params.length; ++i) {
            WithdrawAndCompoundParams memory currParams = params[i];

            (uint256 amount, uint256 earned) = _withdraw(currParams, true);

            IParallaxStrategy(
                strategies[currParams.withdrawParams.strategyId].strategy
            ).withdrawAndSwapForERC20Token(
                    _withdrawParamsAdapter(
                        currParams.withdrawParams,
                        _msgSender(),
                        amount,
                        earned
                    )
                );
        }
    }

    /// @inheritdoc IParallaxAndromeda
    function compound(
        uint256[] memory strategyIds,
        uint256[][] memory amountsOutMin
    ) external nonReentrant {
        if (strategyIds.length != amountsOutMin.length) {
            revert OnlyCorrectArrayLength();
        }

        for (uint256 i = 0; i < strategyIds.length; ++i) {
            _onlyExistingStrategy(strategyIds[i]);

            _compound(strategyIds[i], amountsOutMin[i], true);
        }
    }

    /// @inheritdoc IParallaxAndromeda
    function claim(
        uint256[] memory strategyIds,
        uint256[] memory positionIds
    ) external nonReentrant {
        if (strategyIds.length != positionIds.length) {
            revert OnlyCorrectArrayLength();
        }

        for (uint256 i = 0; i < strategyIds.length; ++i) {
            _onlyExistingStrategy(strategyIds[i]);

            _claim(positionIds[i], _msgSender(), strategyIds[i]);
        }
    }

    /// @inheritdoc IParallax
    function addTransaction(
        Timelock.Transaction memory transaction
    ) external onlyOwner returns (bytes32) {
        return _addTransaction(transaction);
    }

    /// @inheritdoc IParallax
    function removeTransaction(
        Timelock.Transaction memory transaction
    ) external onlyOwner {
        _removeTransaction(transaction);
    }

    /// @inheritdoc IParallax
    function executeTransaction(
        Timelock.Transaction memory transaction
    ) external onlyOwner returns (bytes memory) {
        return _executeTransaction(transaction);
    }

    /// @inheritdoc IParallax
    function getFee(address strategy) external view returns (uint256) {
        return strategies[strategyToId[strategy]].fee;
    }

    /// @inheritdoc IParallax
    function getPositionInfo(
        uint256 strategyId,
        address user,
        uint256 positionId
    ) external view returns (UserPosition memory) {
        return
            tokenIdToPositions[positionsToTokenId[user][positionId]][
                strategyId
            ];
    }

    /// @inheritdoc IParallax
    function getStakedBySharesAmount(
        uint256 strategyId,
        uint256 shares
    ) external view onlyExistingStrategy(strategyId) returns (uint256) {
        return _getStakedBySharesAmount(strategyId, shares);
    }

    /// @inheritdoc IParallax
    function getEarnedBySharesAmount(
        uint256 strategyId,
        address user,
        uint256 positionId,
        uint256 shares
    )
        external
        view
        onlyExistingStrategy(strategyId)
        onlyValidWithdrawalSharesAmount(strategyId, user, positionId, shares)
        returns (uint256)
    {
        return _getEarnedBySharesAmount(strategyId, user, positionId, shares);
    }

    /// @inheritdoc IParallax
    function getEarnedByUserAmount(
        uint256 strategyId,
        address user,
        uint256 positionId
    ) external view onlyExistingStrategy(strategyId) returns (uint256) {
        return
            _getEarnedBySharesAmount(
                strategyId,
                user,
                positionId,
                tokenIdToPositions[positionsToTokenId[user][positionId]][
                    strategyId
                ].shares
            );
    }

    /// @inheritdoc IParallax
    function getClaimableRewards(
        uint256 strategyId,
        address user,
        uint256 positionId
    ) external view returns (uint256) {
        UserPosition memory position = tokenIdToPositions[
            positionsToTokenId[user][positionId]
        ][strategyId];
        uint256 newRewards = (_getStakedBySharesAmount(
            strategyId,
            position.shares
        ) * _getUpdatedRewardPerShare(strategyId)) - position.former;
        uint256 claimableRewards = position.reward + newRewards;

        return claimableRewards / 1 ether;
    }

    /// @inheritdoc IParallax
    function getNftByUserAndIndex(
        address user,
        uint256 index
    ) external view returns (uint256) {
        return userToNftIds[user].at(index);
    }

    /// @inheritdoc ITokensRescuer
    function rescueNativeToken(
        uint256 amount,
        address receiver
    ) external onlyOwner {
        _rescueNativeToken(amount, receiver);
    }

    /// @inheritdoc IParallax
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

    /// @inheritdoc IParallax
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

    /// @inheritdoc IParallax
    function transferPositionFrom(
        address from,
        address to,
        uint256 tokenId
    ) external nonReentrant {
        if (_msgSender() != address(ERC721)) {
            revert OnlyERC721();
        }

        userToNftIds[from].remove(tokenId);
        userToNftIds[to].add(tokenId);

        --positionsCount[from];
        uint256 positionIdFrom = tokenIdToPositionId[tokenId];
        uint256 positionIdTo = _createAndReturnPositionId(to);

        positionsToTokenId[from][positionIdFrom] = 0;
        positionsToTokenId[to][positionIdTo] = tokenId;

        tokenIdToPositionId[tokenId] = positionIdTo;

        emit PositionTransferred(from, to, tokenId);
    }

    /**
     * @dev Initializes the contract (unchained).
     * @param initialFeesReceiver A recipient of commissions.
     * @param initialERC721 An address of ERC-721 contract for positions.
     */
    function __ParallaxAndromeda_init_unchained(
        address initialFeesReceiver,
        IERC721MintableBurnable initialERC721
    ) internal onlyInitializing onlyNonZeroAddress(initialFeesReceiver) {
        feesReceiver = initialFeesReceiver;
        ERC721 = initialERC721;
    }

    /**
     * @notice Allows to update position information at the time of deposit.
     * @param params Deposit params.
     * @param user An address of a user who makes deposit.
     * @param amount An amount of staked tokens (LPs).
     */
    function _updatePosition(
        DepositParams memory params,
        address user,
        address holder,
        uint256 positionId,
        uint256 amount
    ) private {
        uint256 strategyId = params.strategyId;

        uint256 cap = strategies[strategyId].cap;
        if (cap > 0 && strategies[strategyId].totalStaked + amount > cap) {
            revert CapExceeded();
        }

        uint256 tokenId = positionsToTokenId[holder][positionId];

        _onlyExistingPosition(holder, positionId);
        _addNewUserToStrategyIfNeeded(strategyId, holder);

        uint256 totalShares = strategies[strategyId].totalShares;
        uint256 shares = totalShares == 0
            ? amount
            : (amount * totalShares) / strategies[strategyId].totalStaked;
        uint256 rewardPerShare = strategies[strategyId].rewardPerShare;
        UserPosition storage position = tokenIdToPositions[tokenId][strategyId];

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
        position.deposited += amount;

        strategies[strategyId].totalStaked += amount;
        strategies[strategyId].totalShares += shares;

        emit Staked(strategyId, positionId, user, holder, amount, shares);
    }

    /**
     * @notice Allows to update position information at the time of withdrawal.
     * @param params withdraw and compound params.
     * @param toCompound A flag that indicates whether to compound or not.
     * @return Staked by shares amount, earned by shares amount
     */
    function _withdraw(
        WithdrawAndCompoundParams memory params,
        bool toCompound
    ) private returns (uint256, uint256) {
        uint256 strategyId = params.withdrawParams.strategyId;
        uint256 positionId = params.withdrawParams.positionId;
        uint256 shares = params.withdrawParams.shares;
        address receiver = params.withdrawParams.receiver;

        _onlyAfterLock(_msgSender(), strategyId, positionId);
        _onlyExistingStrategy(strategyId);
        _onlyValidWithdrawalSharesAmount(
            strategyId,
            _msgSender(),
            positionId,
            shares
        );

        if (toCompound) {
            _compound(strategyId, params.compoundAmountsOutMin, false);
        }

        uint256 tokenId = positionsToTokenId[_msgSender()][positionId];
        _onlyExistingPosition(_msgSender(), positionId);

        UserPosition storage position = tokenIdToPositions[tokenId][strategyId];

        uint256 stakedBySharesAmount = _getStakedBySharesAmount(
            strategyId,
            shares
        );
        uint256 earnedBySharesAmount = _getEarnedBySharesAmount(
            strategyId,
            _msgSender(),
            positionId,
            shares
        );
        uint256 rewardPerShare = strategies[strategyId].rewardPerShare;

        position.reward +=
            (_getStakedBySharesAmount(strategyId, position.shares) *
                rewardPerShare) -
            position.former;
        position.shares -= shares;
        position.former =
            _getStakedBySharesAmount(strategyId, position.shares) *
            rewardPerShare;
        position.deposited -= stakedBySharesAmount - earnedBySharesAmount;

        strategies[strategyId].totalStaked -= stakedBySharesAmount;
        strategies[strategyId].totalShares -= shares;

        uint256 actualFee = strategies[strategyId].fee;

        emit Withdrawn(
            strategyId,
            positionId,
            _msgSender(),
            receiver,
            stakedBySharesAmount,
            actualFee,
            shares
        );

        return (stakedBySharesAmount, earnedBySharesAmount);
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
     * @param toRevertIfFail A flag indicating whether the method should be
     *                       reverted if the swap in the harvest yields more
     *                       than the maximum slippage from the oracle.
     */
    function _compound(
        uint256 strategyId,
        uint256[] memory amountsOutMin,
        bool toRevertIfFail
    ) private {
        _updateStrategyRewards(strategyId);

        uint256 compounded = IParallaxStrategy(strategies[strategyId].strategy)
            .compound(amountsOutMin, toRevertIfFail);

        strategies[strategyId].totalStaked += compounded;
        strategies[strategyId].lastCompoundTimestamp = block.timestamp;

        emit Compounded(strategyId, block.number, _msgSender(), compounded);
    }

    /**
     * @notice Сlaims tokens that were distributed on users deposit and earned
     *         by a specific position of a user.
     * @param strategyId An ID of an earning strategy.
     * @param user Holder of position.
     * @param positionId An ID of position.
     */
    function _claim(uint256 strategyId, address user, uint256 positionId) private {
        _updateStrategyRewards(strategyId);

        IParallaxStrategy(strategies[strategyId].strategy).claim(
            strategyId,
            user,
            positionId
        );

        UserPosition storage position = tokenIdToPositions[
            positionsToTokenId[user][positionId]
        ][strategyId];

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
            revert NoTokensToClaim();
        }
    }

    function _transferAndApprove(
        address strategy,
        address token,
        uint256 amount
    ) private {
        IERC20Upgradeable(token).safeTransferFrom(
            _msgSender(),
            address(this),
            amount
        );

        IERC20Upgradeable(token).approve(strategy, amount);
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
     * @notice Adds a user to a strategy if it was his first position in a
     *         strategy .
     * @param strategyId An ID of an earning strategy.
     * @param user A user to check his positions count.
     */
    function _addNewUserToStrategyIfNeeded(
        uint256 strategyId,
        address user
    ) private {
        if (userIsActiveInStrategy[user][strategyId] == false) {
            userIsActiveInStrategy[user][strategyId] = true;

            Strategy storage strategy = strategies[strategyId];

            ++strategy.usersCount;
            ++userAmountStrategies[user];

            strategyUsers[strategyId][strategy.usersCount] = user;
            strategyUsersToId[strategyId][user] = strategy.usersCount;
        }
    }

    /**
     * @notice Creates new position if positionId == 0
     * @param user A user to check his positions count.
     * @param positionId An ID of a position.
     */
    function _createPositionIfNeeded(
        address user,
        uint256 positionId
    ) private returns (uint256) {
        if (positionId == 0) {
            positionId = _createAndReturnPositionId(user);

            ++tokensCount;

            uint256 tokenId = tokensCount;

            positionsToTokenId[user][positionId] = tokenId;
            tokenIdToPositionId[tokenId] = positionId;

            ERC721.mint(user, tokenId);

            userToNftIds[user].add(tokenId);

            emit PositionCreated(positionId, user, block.number);
        }

        return positionId;
    }

    /**
     * @notice Adds a user to a parallax if it was his first position in a
     *         parallax .
     * @param user A user to check his positions count.
     */
    function _createAndReturnPositionId(
        address user
    ) private returns (uint256) {
        uint256 currPositionsCount = ++positionsCount[user];

        if (currPositionsCount == 1 && usersToId[user] == 0) {
            ++usersCount;
            users[usersCount] = user;
            usersToId[user] = usersCount;
        }

        return currPositionsCount;
    }

    /**
     * @notice Performs various checks before depositing and compounding.
     * @param params A struct containing deposit and compound parameters.
     */
    function _beforeDeposit(DepositAndCompoundParams memory params) private {
        _onlyExistingStrategy(params.depositParams.strategyId);
        _isStrategyActive(params.depositParams.strategyId);

        _compound(
            params.depositParams.strategyId,
            params.compoundAmountsOutMin,
            false
        );
    }

    /**
     * @notice Adapts deposit parameters for IParallaxStrategy.
     * @param params A struct containing deposit parameters.
     * @param user Address of the user who makes deposit.
     * @return A struct containing adapted deposit parameters.
     */
    function _depositParamsAdapter(
        address user,
        address holder,
        uint256 positionId,
        DepositParams memory params
    )
        private
        pure
        onlyNonZeroAddress(holder)
        returns (IParallaxStrategy.DepositParams memory)
    {
        return
            IParallaxStrategy.DepositParams({
                amountsOutMin: params.amountsOutMin,
                paths: params.paths,
                user: user,
                holder: holder,
                positionId: positionId,
                amounts: params.amounts,
                data: params.data
            });
    }

    /**
     * @notice Adapts withdrawal parameters for IParallaxStrategy.
     * @param params A struct containing withdrawal parameters.
     * @param amount Amount to be withdrawn.
     * @param earned Earned amount.
     * @return A struct containing adapted withdrawal parameters.
     */
    function _withdrawParamsAdapter(
        WithdrawParams memory params,
        address holder,
        uint256 amount,
        uint256 earned
    )
        private
        pure
        onlyNonZeroAddress(params.receiver)
        returns (IParallaxStrategy.WithdrawParams memory)
    {
        return
            IParallaxStrategy.WithdrawParams({
                amountsOutMin: params.amountsOutMin,
                paths: params.paths,
                positionId: params.positionId,
                earned: earned,
                amount: amount,
                receiver: params.receiver,
                holder: holder,
                data: params.data
            });
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
     * @param user A holder of position.
     * @param shares An amount of shares for which to calculate an earned
     *               amount of tokens.
     * @param positionId An ID of a position.
     * @return An amount of earned by shares tokens (LPs).
     */
    function _getEarnedBySharesAmount(
        uint256 strategyId,
        address user,
        uint256 positionId,
        uint256 shares
    ) private view returns (uint256) {
        UserPosition memory position = tokenIdToPositions[
            positionsToTokenId[user][positionId]
        ][strategyId];

        uint256 stakedBySharesAmount = _getStakedBySharesAmount(
            strategyId,
            position.shares
        );

        uint256 totalEarnedAmount;
        if (position.deposited > stakedBySharesAmount) {
            totalEarnedAmount = 0;
        } else {
            totalEarnedAmount = stakedBySharesAmount - position.deposited;
        }

        uint256 earnedByShares = position.shares == 0
            ? 0
            : (totalEarnedAmount * shares) / position.shares;

        return earnedByShares;
    }

    /**
     * @notice Checks if a user can make a withdrawal. It depends on
     *         `lastStakedTimestamp` for a user and timelock duration of
     *          strategy. Fails if timelock is not finished.
     * @param user An user to check.
     * @param strategyId An ID of an earning strategy.
     * @param positionId An ID of a position.
     */
    function _onlyAfterLock(
        address user,
        uint256 strategyId,
        uint256 positionId
    ) private view {
        uint32 timeDifference = uint32(block.timestamp) -
            tokenIdToPositions[positionsToTokenId[user][positionId]][strategyId]
                .lastStakedTimestamp;
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
     * @param user A holder of position.
     * @param user A position id to check.
     */
    function _onlyExistingPosition(
        address user,
        uint256 positionId
    ) private view {
        if (positionId > positionsCount[user]) {
            revert OnlyExistPosition();
        }
    }

    /**
     * @notice Checks the upper bound of the withdrawal commission. Fee must be
     *         less than or equal to maximum possible fee. Fails otherwise.
     * @param strategy An address of an earning strategy.
     * @param fee A withdrawal commission amount.
     */
    function _onlyValidFee(address strategy, uint256 fee) private view {
        uint256 maxStrategyFee = IParallaxStrategy(strategy).getMaxFee();

        if (fee > maxStrategyFee) {
            revert OnlyValidFee();
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
        address user,
        uint256 positionId,
        uint256 shares
    ) private view {
        if (
            shares >
            tokenIdToPositions[positionsToTokenId[user][positionId]][strategyId]
                .shares
        ) {
            revert OnlyValidWithdrawalSharesAmount();
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

