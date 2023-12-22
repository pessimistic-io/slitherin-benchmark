//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.18;

import {ILockdropPhase1, ILockdropPhase1Helper, IUniswapV2Pair, ILockdropPhase2, LockingToken, IUniswapV2Router02} from "./ILockdropPhase1.sol";
import {ILockdrop, Lockdrop} from "./Lockdrop.sol";
import {IUniswapV2Factory} from "./IUniswapV2Factory.sol";

import {SafeERC20} from "./SafeERC20.sol";
import {IERC20} from "./IERC20.sol";
import {ITokenVesting} from "./ITokenVesting.sol";

/**
 * @title LockdropPhase1
 * @notice The contract allows users to deposit tokens from other dexes in exchange for receiving LP tokens from the newly created dex.
 * In addition, users receive a reward, part of which is vested, and part of which goes directly to the user's wallet, or is sent to lockdrop phase 2.
 */
contract LockdropPhase1 is ILockdropPhase1, Lockdrop {
    using SafeERC20 for IERC20;

    uint256 public constant MAX_LOCKING_TOKENS = 5;
    uint256 public constant MAX_EXPIRATION_TIMESTAMPS = 7;
    uint256 public constant MAX_ALLOCATIAON_TO_WITHDRAW = 7;
    uint256 public constant MIN_PERCENTAGE = 30;
    bytes32 public constant LOCKDROP_PHASE_1_RESOLVER =
        keccak256("LOCKDROP_PHASE_1_RESOLVER");

    // uint256 internal constant VESTING_DURATION = 365 days / 2;
    uint256 internal constant VESTING_DURATION = 1 days / 2;

    uint256 internal removedLiquidityCounter_;
    ITokenVesting public immutable override vesting;

    ILockdropPhase2 public immutable override phase2;
    ILockdropPhase1Helper public helper;
    address public immutable override tokenAAddress;
    address public immutable override tokenBAddress;

    uint256 public immutable override tokenAPrice;
    uint256 public immutable override tokenBPrice;

    uint256[] public lockingExpirationTimestamps_;

    LockingToken[] internal lockingTokens;
    uint256 internal removingLiqudityCounter;
    mapping(uint256 => uint256) public totalPointsInRound;
    mapping(address => uint256) public userAllocationsCount;
    mapping(address => mapping(uint256 => UserAllocation))
        internal userAllocations;
    mapping(uint256 => uint256) public totalRewardInTimeRange;
    mapping(address => uint256) public userRewardWithdrawn;
    mapping(address => uint256) public totalRewardPerWallet;
    mapping(address => uint256) public totalRewardCalculatedToAllocationId;
    mapping(address => mapping(uint256 => uint256)) public totalTokensLocked;

    /**
     * @notice Modifier created to check if the current state of ock(ockdrop is as expected.
     * @dev Contract reverts with WrongLockdropState error when the state is different than expected.
     * @param expected LockdropState.
     */
    modifier onlyOnLockdropState(LockdropState expected) {
        if (state() != expected) {
            revert WrongLockdropState(state(), expected);
        }
        _;
    }

    /**
     * @notice Modifier created to check if the current state of lockdrop is as at least as defined one.
     * @dev Contract reverts with ToEarlyAllocationState error, when the current state is less than expected.
     * @param expected LockdropState we should (at least) currently be in.
     */
    modifier atLeastTheLockdropState(LockdropState expected) {
        LockdropState current = state();
        if (current < expected) {
            revert ToEarlyAllocationState(current, expected);
        }
        _;
    }

    /**
     * @notice Modifier created to check if the msg.sender of the transaction has rights to execute guarded functions in the contract.
     * @dev Contract reverts with OnlyLockdropPhase1ResolverAccess error when a signer does not have the role.
     */
    modifier onlyLockdropPhase1Resolver() {
        if (!acl.hasRole(LOCKDROP_PHASE_1_RESOLVER, msg.sender)) {
            revert OnlyLockdropPhase1ResolverAccess();
        }
        _;
    }

    /**
     * @notice Modifier created to check if the given index of the token exist in the stored lockingTokens array.
     * @dev Contract reverts with LockingTokenNotExists error when the tokenIndex is bigger than length of the tokens array.
     * @param _tokenIndex The index of the token.
     */
    modifier lockingTokenExists(uint256 _tokenIndex) {
        if (_tokenIndex >= lockingTokens.length) {
            revert LockingTokenNotExists();
        }
        _;
    }

    /**
     * @notice Modifier created to check if the given index of the expiration timestamp exists in the stored expiration timestamps array.
     * @dev Contract reverts with NotDefinedExpirationTimestamp error when the _expirationTimestampIndex is bigger than length of the expiration timestamps array.
     * @param _expirationTimestampIndex Index of the expiration timestamp.
     */
    modifier expirationTimestampExists(uint256 _expirationTimestampIndex) {
        if (_expirationTimestampIndex >= lockingExpirationTimestamps_.length) {
            revert NotDefinedExpirationTimestamp();
        }
        _;
    }

    /**
     * @notice Function checks if the wallet took part in the lockdrop.
     * @dev Function reverts with WalletDidNotTakePartInLockdrop, when the wallet did not part in the lockdrop.
     * @param _wallet Address of the wallet to be checked.
     */
    modifier userTookPartInLockdrop(address _wallet) {
        if (userAllocationsCount[_wallet] == 0) {
            revert WalletDidNotTakePartInLockdrop();
        }
        _;
    }

    constructor(
        ContractAddress memory contracts,
        uint256 _lockingStart,
        uint256 _unlockingEnd,
        uint256 _lockingEnd,
        uint256 _migrationEndTimestamp,
        RewardParams memory _rewardParams,
        TokenParams memory _tokenParams,
        LockingToken[] memory _lockingTokens,
        uint32[] memory _lockingExpirationTimestamps
    )
        Lockdrop(
            contracts.acl,
            _rewardParams.rewardToken,
            _lockingStart,
            _lockingEnd,
            _unlockingEnd,
            _migrationEndTimestamp,
            _rewardParams.rewardAmount
        )
        notZeroAmount(_tokenParams.tokenAPrice)
        notZeroAmount(_tokenParams.tokenBPrice)
        notZeroAmount(_rewardParams.rewardAmount)
    {
        tokenAPrice = _tokenParams.tokenAPrice;
        tokenBPrice = _tokenParams.tokenBPrice;
        tokenAAddress = _tokenParams.tokenAToken;
        tokenBAddress = _tokenParams.tokenBToken;
        phase2 = contracts.phase2;
        vesting = contracts.vesting;
        helper = contracts.helper;

        _assignLockingTokens(_lockingTokens);
        _assignExpirationTimestamps(_lockingExpirationTimestamps);
    }

    /**
     * @inheritdoc ILockdropPhase1
     * @dev Function reverts with WrongLockdropState error if the user tries to lock the tokens before or after the locking period.
     * @dev Function reverts with LockingTokensNotExist error if the index of the token is bigger than length of locking tokens.
     * @dev Function reverts with ZeroAmount error if the user wants to lock zero tokens.
     */
    function lock(
        uint256 _tokenIndex,
        uint256 _value,
        uint32 _lockingExpirationTimestampIndex
    )
        external
        override
        onlyOnAllocationState(AllocationState.ALLOCATION_ONGOING)
        lockingTokenExists(_tokenIndex)
        expirationTimestampExists(_lockingExpirationTimestampIndex)
        notZeroAmount(_value)
    {
        uint256 basePoints = getPoints(_tokenIndex, _value);
        uint256 boost = calculateBoost(basePoints);
        uint256 points = boost + basePoints;

        address tokenAddr = lockingTokens[_tokenIndex].token;
        for (
            uint32 stampId = 0;
            stampId <= _lockingExpirationTimestampIndex;

        ) {
            totalPointsInRound[stampId] += points;
            unchecked {
                ++stampId;
            }
        }

        uint256 nextWalletAllocations = ++userAllocationsCount[msg.sender];
        userAllocations[msg.sender][nextWalletAllocations] = UserAllocation({
            taken: false,
            value: _value,
            boost: boost,
            tokenIndex: _tokenIndex,
            token: tokenAddr,
            unlockTimestampIndex: _lockingExpirationTimestampIndex,
            points: points
        });

        totalTokensLocked[msg.sender][_tokenIndex] += _value;

        IERC20(tokenAddr).safeTransferFrom(msg.sender, address(this), _value);

        emit LiquidityProvided(
            msg.sender,
            tokenAddr,
            _lockingExpirationTimestampIndex,
            _value,
            points
        );
    }

    /**
     * @inheritdoc ILockdropPhase1
     * @dev Function reverts with AllocationDoesNotExist if the user does not have allocation with such id.
     * @dev Function reverts with NotEnoughToWithdraw if the wants to unlock more tokens than already locked.
     */
    function unlock(
        uint256 _allocationIndex,
        uint256 _value
    ) external override notZeroAmount(_value) {
        LockdropState state_ = state();
        if (
            !(state_ ==
                LockdropState.TOKENS_ALLOCATION_LOCKING_UNLOCKING_ONGOING ||
                state_ == LockdropState.MIGRATION_END)
        ) {
            revert CannotUnlock();
        }
        if (_allocationIndex > userAllocationsCount[msg.sender]) {
            revert AllocationDoesNotExist();
        }
        UserAllocation storage allocation = userAllocations[msg.sender][
            _allocationIndex
        ];
        address token = allocation.token;
        if (_value > allocation.value) {
            revert NotEnoughToWithdraw();
        }

        uint256 totalPointsToRemove = (_value * allocation.points) /
            allocation.value;
        allocation.boost =
            allocation.boost -
            ((_value * allocation.boost) / allocation.value);
        allocation.points -= totalPointsToRemove;
        allocation.value -= _value;

        for (uint32 stampId = 0; stampId <= allocation.unlockTimestampIndex; ) {
            totalPointsInRound[stampId] -= totalPointsToRemove;
            unchecked {
                ++stampId;
            }
        }

        totalTokensLocked[msg.sender][allocation.tokenIndex] -= _value;

        IERC20(token).safeTransfer(msg.sender, _value);

        emit LiquidityUnlocked(msg.sender, _allocationIndex, _value);
    }

    /**
     * @inheritdoc ILockdropPhase1
     * @dev Function reverts with Phase2NotFinished error when the wallets tries to get the reward before lockdrop phase 2 ends.
     */
    function getRewardAndSendOnVesting()
        external
        override
        userTookPartInLockdrop(msg.sender)
    {
        if (phase2.lockingEnd() > block.timestamp) {
            revert Phase2NotFinished();
        }

        if (!isRewardCalculated(msg.sender)) {
            revert RewardNotCalculated();
        }

        uint256 reward = totalRewardPerWallet[msg.sender];
        uint256 alreadyWithdrawn = userRewardWithdrawn[msg.sender];

        if ((alreadyWithdrawn >= reward)) {
            revert MaxRewardExceeded();
        }
        uint256 toSendOnVesting = reward / 2;
        uint256 remainingReward = toSendOnVesting - alreadyWithdrawn;

        userRewardWithdrawn[msg.sender] = reward;

        IERC20(address(rewardToken)).forceApprove(
            address(vesting),
            toSendOnVesting
        );
        vesting.addVesting(
            msg.sender,
            lockingEnd,
            VESTING_DURATION,
            toSendOnVesting
        );

        if (remainingReward > 0) {
            rewardToken.safeTransfer(msg.sender, remainingReward);
        }

        emit RewardWithdrawn(msg.sender, remainingReward);
        emit RewardSentOnVesting(msg.sender, toSendOnVesting);
    }

    /**
     * @inheritdoc ILockdropPhase1
     * @dev Function reverts with RewardNotCalculated error if the reward was not calculated beforehand
     */
    function allocateRewardOnLockdropPhase2(
        uint256 _amount
    ) external override userTookPartInLockdrop(msg.sender) {
        if (!isRewardCalculated(msg.sender)) {
            revert RewardNotCalculated();
        }

        uint256 walletTotalReward = totalRewardPerWallet[msg.sender];
        uint256 toAllocateOnPhase2Max = walletTotalReward / 2;

        if (_amount + userRewardWithdrawn[msg.sender] > toAllocateOnPhase2Max) {
            revert MaxRewardExceeded();
        }
        rewardToken.forceApprove(address(phase2), _amount);
        phase2.lockSparta(_amount, msg.sender);
        userRewardWithdrawn[msg.sender] += _amount;

        emit RewardLockedOnLockdropPhase2(msg.sender, _amount);
    }

    /**
     * @inheritdoc ILockdropPhase1
     * @dev Function reverts with WrongLockdrop state, if the the function is executed before the locking end.
     * @dev Function reverts with SourceLiquidityAlreadyRemoved state, if the all of liquidity is already exchanged.
     */
    function removeSourceLiquidity(
        uint256 minPercentage0_,
        uint256 minPercentage1_,
        uint256 deadline_
    )
        external
        override
        onlyOnLockdropState(LockdropState.TOKENS_ALLOCATION_FINISHED)
        onlyLockdropPhase1Resolver
    {
        IERC20 token = IERC20(lockingTokens[removedLiquidityCounter_].token);
        uint256 balance = token.balanceOf(address(this));
        if (balance != 0) {
            token.safeTransfer(address(helper), balance);
            (uint256 res0, uint256 res1, ) = IUniswapV2Pair(
                lockingTokens[removedLiquidityCounter_].token
            ).getReserves();
            if (
                minPercentage0_ < MIN_PERCENTAGE ||
                minPercentage1_ < MIN_PERCENTAGE
            ) {
                revert MinPercentage();
            }
            uint256 min0 = (balance * res0 * minPercentage0_) /
                (token.totalSupply() * 10000);
            uint256 min1 = (balance * res1 * minPercentage1_) /
                (token.totalSupply() * 10000);
            helper.removeLiquidity(
                lockingTokens[removedLiquidityCounter_],
                min0,
                min1,
                deadline_
            );
        }
        removedLiquidityCounter_++;
    }

    /**
     * @inheritdoc ILockdrop
     * @dev Function reverts with WrongLockdrop state, if the the function is executed before source liquidity removing.
     * @dev Function reverts with TargetLiquidityAlreadyProvided state, if the liquidity is already provided.
     * @dev Function reverts with PairAlreadyCreated if the pool exists on the dex.
     */
    function addTargetLiquidity(
        IUniswapV2Router02 _router,
        uint256 _deadline
    )
        external
        override
        onlyLockdropPhase1Resolver
        onlyOnLockdropState(LockdropState.SOURCE_LIQUIDITY_EXCHANGED)
    {
        (address _tokenAAddress, address _tokenBAddress) = (
            tokenAAddress,
            tokenBAddress
        );

        if (
            IUniswapV2Factory(_router.factory()).getPair(
                _tokenAAddress,
                _tokenBAddress
            ) != address(0)
        ) {
            revert PairAlreadyCreated();
        }

        spartaDexRouter = _router;

        uint256 tokenABalance = IERC20(_tokenAAddress).balanceOf(address(this));
        uint256 tokenBBalance = IERC20(_tokenBAddress).balanceOf(address(this));
        IERC20(_tokenAAddress).forceApprove(address(_router), tokenABalance);
        IERC20(_tokenBAddress).forceApprove(address(_router), tokenBBalance);

        (, , initialLpTokensBalance) = _router.addLiquidity(
            _tokenAAddress,
            _tokenBAddress,
            tokenABalance,
            tokenBBalance,
            tokenABalance,
            tokenBBalance,
            address(this),
            _deadline
        );
    }

    /**
     * @inheritdoc ILockdropPhase1
     * @dev Function reverts with WrongLockdropPhase, if the the tokens allocation is not finished yet.
     * @dev Function reverts with WalletDidNotTakePartInLockdrop, if an address didn't take part in the lockdrop.
     * @dev Function reverts with CannotCalculateRewardForChunks, if the sender tries to calculate reward from not existing allocations.
     */
    function calculateAndStoreTotalRewardInChunks(
        address _wallet,
        uint256 _chunksAmount
    )
        external
        override
        atLeastTheLockdropState(LockdropState.TOKENS_ALLOCATION_FINISHED)
        userTookPartInLockdrop(_wallet)
        returns (uint256)
    {
        uint256 lastCalcuated = totalRewardCalculatedToAllocationId[_wallet];
        uint256 diff = userAllocationsCount[_wallet] - lastCalcuated;

        if (_chunksAmount > diff) {
            revert CannotCalculateRewardForChunks();
        }

        uint256 reward = 0;
        uint256 stop = lastCalcuated + _chunksAmount;
        uint256 start = lastCalcuated + 1;

        for (uint allocationId = start; allocationId <= stop; ) {
            UserAllocation memory allocation = userAllocations[_wallet][
                allocationId
            ];

            uint32 unlockTimestampIndex = allocation.unlockTimestampIndex;
            for (uint32 timeIndex = 0; timeIndex <= unlockTimestampIndex; ) {
                reward +=
                    (totalRewardInTimeRange[timeIndex] * allocation.points) /
                    totalPointsInRound[timeIndex];

                unchecked {
                    timeIndex++;
                }
            }

            unchecked {
                allocationId++;
            }
        }

        totalRewardCalculatedToAllocationId[_wallet] += _chunksAmount;
        totalRewardPerWallet[_wallet] += reward;

        return reward;
    }

    /**
     * @inheritdoc ILockdropPhase1
     * @dev Function reverts with WrongLockdropState error, if the target liqudity is not provided.
     * @dev Function reverts with MaxLengthExceeded error if the user wants to withdraw tokens from not existing allocation.
     * @dev Function reverts with TokenAllocationAlreadyTaken error if the user wants to withdraw tokens from an already withdrawn allocation.
     * @dev Function reverts with CannotUnlockTokensBeforeUnlockTime, if the user wants to withdraw tokens before the unlock timestamp.
     */
    function withdrawExchangedTokens(
        uint256[] calldata allocationsIds
    )
        external
        override
        onlyOnLockdropState(LockdropState.TARGET_LIQUIDITY_PROVIDED)
    {
        uint256 totalLpToTransfer = 0;
        uint256 allocationsIdsLength = allocationsIds.length;
        if (allocationsIdsLength > MAX_ALLOCATIAON_TO_WITHDRAW) {
            revert MaxLengthExceeded();
        }

        for (
            uint256 allocationIndex = 0;
            allocationIndex < allocationsIdsLength;

        ) {
            UserAllocation memory allocation = userAllocations[msg.sender][
                allocationsIds[allocationIndex]
            ];
            if (allocation.taken) {
                revert TokenAllocationAlreadyTaken();
            }
            uint256 unlockTime = lockingExpirationTimestamps_[
                allocation.unlockTimestampIndex
            ];
            if (unlockTime > block.timestamp) {
                revert CannotUnlockTokensBeforeUnlockTime();
            }
            uint256 reward = calculateRewardFromAllocation(allocation);
            uint256 tokensToWithdraw = (reward * initialLpTokensBalance) /
                totalReward;

            totalLpToTransfer += tokensToWithdraw;
            userAllocations[msg.sender][allocationIndex].taken = true;

            unchecked {
                allocationIndex++;
            }
        }

        IERC20(exchangedPair()).safeTransfer(msg.sender, totalLpToTransfer);
    }

    /**
     * @inheritdoc ILockdropPhase1
     *
     */
    function getLockingExpirationTimestamps()
        external
        view
        override
        returns (uint256[] memory)
    {
        uint256 length = lockingExpirationTimestamps_.length;
        uint256[] memory timestamps = new uint256[](
            lockingExpirationTimestamps_.length
        );
        for (uint i = 0; i < length; ) {
            timestamps[i] = lockingExpirationTimestamps_[i];
            unchecked {
                ++i;
            }
        }

        return timestamps;
    }

    /**
     * @inheritdoc ILockdropPhase1
     */
    function calculateTotalReward(
        address _wallet
    ) external view override returns (uint256) {
        uint256 reward = 0;
        uint256 allocationsLength = userAllocationsCount[_wallet];
        for (uint256 allocationId = 1; allocationId <= allocationsLength; ) {
            reward += calculateRewardFromAllocation(
                userAllocations[_wallet][allocationId]
            );
            unchecked {
                allocationId++;
            }
        }

        return reward;
    }

    /**
     * @inheritdoc ILockdropPhase1
     */
    function getUserAllocations(
        address _wallet
    ) external view returns (UserAllocation[] memory) {
        uint256 count = userAllocationsCount[_wallet];
        UserAllocation[] memory allocations = new UserAllocation[](count);
        for (uint256 i = 0; i < count; ) {
            allocations[i] = userAllocations[_wallet][i + 1];
            unchecked {
                i++;
            }
        }

        return allocations;
    }

    /**
     * @inheritdoc ILockdropPhase1
     */
    function getLockingTokens()
        external
        view
        override
        returns (LockingToken[] memory)
    {
        uint256 length = lockingTokens.length;

        LockingToken[] memory _lockingTokens = new LockingToken[](
            lockingTokens.length
        );

        for (uint256 i = 0; i < length; ) {
            _lockingTokens[i] = lockingTokens[i];
            unchecked {
                ++i;
            }
        }

        return _lockingTokens;
    }

    /**
     * @inheritdoc ILockdropPhase1
     */
    function calculateRewardFromAllocation(
        UserAllocation memory allocation
    ) public view returns (uint256) {
        uint256 reward = 0;
        uint32 unlockTimestampIndex = allocation.unlockTimestampIndex;
        for (uint32 timeIndex = 0; timeIndex <= unlockTimestampIndex; ) {
            reward +=
                (totalRewardInTimeRange[timeIndex] * allocation.points) /
                totalPointsInRound[timeIndex];

            unchecked {
                timeIndex++;
            }
        }

        return reward;
    }

    /**
     * @inheritdoc ILockdropPhase1
     */
    function isRewardCalculated(
        address _wallet
    ) public view override returns (bool) {
        return
            userAllocationsCount[_wallet] != 0
                ? totalRewardCalculatedToAllocationId[_wallet] ==
                    userAllocationsCount[_wallet]
                : false;
    }

    /**
     * @inheritdoc ILockdropPhase1
     * @dev Function reverts with AllocationDoesNotExist, if one of given allocation does not exist.
     */
    function calculateRewardFromAllocations(
        address _wallet,
        uint256[] calldata _allocations
    ) public view returns (uint256) {
        uint256 reward = 0;
        uint256 allocationsLength = _allocations.length;
        uint256 maxId = userAllocationsCount[_wallet];

        for (uint256 allocationId = 0; allocationId < allocationsLength; ) {
            uint256 currentAllocation = _allocations[allocationId];
            if (currentAllocation > maxId) {
                revert AllocationDoesNotExist();
            }

            reward += calculateRewardFromAllocation(
                userAllocations[_wallet][currentAllocation]
            );

            unchecked {
                allocationId++;
            }
        }

        return reward;
    }

    /**
     * @inheritdoc ILockdrop
     * @dev Function reverts with SpartaDexNotInitialized if the dex has not been initialized yet.
     * @return IUniswapV2Pair pair used in the lockdrop.
     */
    function exchangedPair() public view override returns (address) {
        if (address(spartaDexRouter) == address(0)) {
            revert SpartaDexNotInitialized();
        }

        (address token0_, address token1_) = tokenAAddress < tokenBAddress
            ? (tokenAAddress, tokenBAddress)
            : (tokenBAddress, tokenAAddress);

        return
            IUniswapV2Factory(spartaDexRouter.factory()).getPair(
                token0_,
                token1_
            );
    }

    /**
     * @inheritdoc ILockdropPhase1
     * @return LockdropState current active state.
     */
    function state() public view returns (LockdropState) {
        AllocationState allocationState = _allocationState();
        if (allocationState == AllocationState.NOT_STARTED) {
            return LockdropState.NOT_STARTED;
        } else if (allocationState == AllocationState.ALLOCATION_ONGOING) {
            if (block.timestamp > unlockingEnd) {
                return
                    LockdropState
                        .TOKENS_ALLOCATION_LOCKING_ONGOING_UNLOCKING_FINISHED;
            }
            return LockdropState.TOKENS_ALLOCATION_LOCKING_UNLOCKING_ONGOING;
        } else {
            if (address(spartaDexRouter) == address(0)) {
                if (block.timestamp > migrationEndTimestamp) {
                    return LockdropState.MIGRATION_END;
                } else if (lockingTokens.length == removedLiquidityCounter_) {
                    return LockdropState.SOURCE_LIQUIDITY_EXCHANGED;
                }

                return LockdropState.TOKENS_ALLOCATION_FINISHED;
            }
        }

        return LockdropState.TARGET_LIQUIDITY_PROVIDED;
    }

    /**
     * @inheritdoc ILockdropPhase1
     * @param _tokenIndex token index from the lockingTokens array
     * @dev Function reverts with LockingTokenNotExist if the index of the tokens is bigger than locking tokens length.
     * @return uint256 price of the given LP token.
     */
    function getLPTokenPrice(
        uint256 _tokenIndex
    ) public view override lockingTokenExists(_tokenIndex) returns (uint256) {
        return
            helper.getPrice(
                lockingTokens[_tokenIndex].token,
                tokenAAddress,
                tokenAPrice,
                tokenBPrice
            );
    }

    /**
     * @notice function returns amount of points corresponding to the number of tokens from the particular index.
     * @param _tokenIndex index of the token from lockingTokens array.
     * @param _amount number of tokens.
     * @return uint256 points corresponding to the number of tokens form the index.
     */
    function getPoints(
        uint256 _tokenIndex,
        uint256 _amount
    ) public view lockingTokenExists(_tokenIndex) returns (uint256) {
        return (getLPTokenPrice(_tokenIndex) * _amount) / (2 ** 112);
    }

    /**
     * @notice Function calculates the boost from the base calculated points.
     * @param _basePoints base points calculated by _getPoints function.
     * @return uint256 boost calculated from the base points amount.
     */
    function calculateBoost(uint256 _basePoints) public view returns (uint256) {
        AllocationState allocationState = _allocationState();
        if (allocationState == AllocationState.ALLOCATION_ONGOING) {
            uint256 numerator = (_basePoints *
                150 *
                (lockingEnd - block.timestamp));
            uint256 denominator = (lockingEnd - lockingStart) * 1000;
            return numerator / denominator;
        }

        return 0;
    }

    /**
     * @notice function validates and assigns the lockingTokens to the storage.
     * @dev function reverts with MaxLengthExceeded if the length of the given tokens is bigger than max.
     * @dev function reverts with MaxLengthExceeded if the length of the given tokens is bigger than max.
     * @param _lockingTokens the array of locking tokens.
     */
    function _assignLockingTokens(
        LockingToken[] memory _lockingTokens
    ) internal {
        uint256 lokingTokensLength = _lockingTokens.length;
        if (lokingTokensLength > MAX_LOCKING_TOKENS) {
            revert MaxLengthExceeded();
        }
        for (
            uint256 lockingTokenId = 0;
            lockingTokenId < lokingTokensLength;

        ) {
            lockingTokens.push(_lockingTokens[lockingTokenId]);
            {
                unchecked {
                    ++lockingTokenId;
                }
            }
        }
    }

    /**
     * @notice function validates the expiration timestamps before assigning them to the storage.
     * @dev function reverts with MaxLengthExceeded error if the number of timestamps is bigger than the max length.
     * @dev function reverts with WrongExpirationTimestamps error if the array is not sorted, or the first element is smaller than the locking end timestamp.
     * @param _lockingExpirationTimestamps array of timestamps.
     */
    function _assignExpirationTimestamps(
        uint32[] memory _lockingExpirationTimestamps
    ) internal {
        uint256 expirationTimestampsLength = _lockingExpirationTimestamps
            .length;

        if (expirationTimestampsLength > MAX_EXPIRATION_TIMESTAMPS) {
            revert MaxLengthExceeded();
        }
        uint256 prev = lockingEnd;
        uint256 lockdropDuration = (_lockingExpirationTimestamps[
            (expirationTimestampsLength - 1)
        ] - lockingEnd);
        for (uint256 i = 0; i < expirationTimestampsLength; ) {
            uint256 current = _lockingExpirationTimestamps[i];
            if (prev >= current) {
                revert WrongExpirationTimestamps();
            }
            uint256 currentDuration = current - prev;
            totalRewardInTimeRange[i] =
                (totalReward * currentDuration) /
                lockdropDuration;
            prev = current;
            unchecked {
                ++i;
            }
        }
        lockingExpirationTimestamps_ = _lockingExpirationTimestamps;
    }
}

