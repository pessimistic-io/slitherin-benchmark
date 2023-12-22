//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.18;

import {IUniswapV2Pair} from "./IUniswapV2Pair.sol";
import {IUniswapV2Router02} from "./IUniswapV2Router02.sol";
import {ITokenVesting} from "./ITokenVesting.sol";
import {ILockdropPhase2} from "./ILockdropPhase2.sol";
import {ILockdropPhase1Helper} from "./ILockdropPhase1Helper.sol";
import {IAccessControl} from "./IAccessControl.sol";

import {IERC20} from "./IERC20.sol";

struct LockingToken {
    bool isChronos;
    bool isStable;
    address token;
    address router;
}

/**
 * @title ILockdropPhase1.
 * @notice The contract was created to collect liquidity from other decentralized uniswap v2 exchanges on the network, which will be delivered to the newly created dex.
 * Users who locate their funds for a certain period of time will receive new liquidity tokens on the new exchange in return, and receive a reward.
 */
interface ILockdropPhase1 {
    error WrongLockdropState(LockdropState current, LockdropState expected);
    error ToEarlyAllocationState(LockdropState current, LockdropState atLeast);
    error SourceLiquidityAlreadyRemoved();
    error RewardRatesAlreadyCalculated();
    error TokenAllocationAlreadyTaken();
    error CannotUnlockTokensBeforeUnlockTime();
    error MaxRewardExceeded();
    error SpartaDexNotInitialized();
    error AllocationDoesNotExist();
    error AllocationCanceled();
    error NotEnoughToWithdraw();
    error OnlyLockdropPhase1ResolverAccess();
    error Phase2NotFinished();
    error NotDefinedExpirationTimestamp();
    error WrongExpirationTimestamps();
    error RewardNotCalculated();
    error CannotCalculateRewardForChunks();
    error AlreadyCalculated();
    error MaxLengthExceeded();
    error LockingTokenNotExists();
    error WalletDidNotTakePartInLockdrop();
    error CannotUnlock();
    error MinPercentage();

    event LiquidityProvided(
        address indexed by,
        address pair,
        uint32 durationIndex,
        uint256 value,
        uint256 points
    );

    struct RemoveData {
        uint256 minPercentage0_;
        uint256 minPercentage1_;
        uint256 deadline_;
    }

    event RewardLockedOnLockdropPhase2(address indexed by, uint256 value);

    event RewardWithdrawn(address indexed by, uint256 amount);

    event RewardSentOnVesting(address indexed by, uint256 amount);

    event LiquidityUnlocked(
        address indexed by,
        uint256 indexed allocationIndex,
        uint256 value
    );

    enum LockdropState {
        NOT_STARTED,
        TOKENS_ALLOCATION_LOCKING_UNLOCKING_ONGOING,
        TOKENS_ALLOCATION_LOCKING_ONGOING_UNLOCKING_FINISHED,
        TOKENS_ALLOCATION_FINISHED,
        SOURCE_LIQUIDITY_EXCHANGED,
        TARGET_LIQUIDITY_PROVIDED,
        MIGRATION_END
    }

    struct UserAllocation {
        bool taken;
        address token;
        uint256 tokenIndex;
        uint32 unlockTimestampIndex;
        uint256 value;
        uint256 boost;
        uint256 points;
    }

    struct TokenParams {
        address tokenAToken;
        address tokenBToken;
        uint256 tokenAPrice;
        uint256 tokenBPrice;
    }

    struct ContractAddress {
        ILockdropPhase2 phase2;
        ITokenVesting vesting;
        IAccessControl acl;
        ILockdropPhase1Helper helper;
    }

    struct RewardParams {
        IERC20 rewardToken;
        uint256 rewardAmount;
    }

    /**
     * @notice Function allows users lock their LP tokens on the contract.
     * @param _tokenIndex Index of the tokens from the locking tokens array.
     * @param _value Amount of tokens the user wants to lock.
     * @param _lockingExpirationTimestampIndex Index of the duration of the locking.
     */
    function lock(
        uint256 _tokenIndex,
        uint256 _value,
        uint32 _lockingExpirationTimestampIndex
    ) external;

    /**
     * @notice Function allows the user to unlock his LP tokens right away.
     * @param _allocationIndex Index of the created Allocations.
     * @param _value Amount of the tokens a user wants to unlock.
     */
    function unlock(uint256 _allocationIndex, uint256 _value) external;

    /**
     * @notice Function allows the user to take the reward and send part of it to the vesting contract.
     */
    function getRewardAndSendOnVesting() external;

    /**
     * @notice Function allows the user to allocate part of his earned reward on the lockdrop phase 2.
     * @param _amount The amount of reward to be allocated.
     */
    function allocateRewardOnLockdropPhase2(uint256 _amount) external;

    /**
     * @notice Function calculates and stores total reward in chunks. Chunks are a number of allocations that will be used to calculate the reward.
     * @param _wallet The address of the wallet. .
     * @param _chunks The number of chunks .
     * @return uint256 Reward earned by wallet from the the given amount of chunks.
     */
    function calculateAndStoreTotalRewardInChunks(
        address _wallet,
        uint256 _chunks
    ) external returns (uint256);

    /**
     * @notice Function allows authorized user to remove liquidity on one of the locked tokens.
     * @param deadline_ Deadline of the transaction execution.
     */
    function removeSourceLiquidity(
        uint256 minPercentage0_,
        uint256 minPercentage1_,
        uint256 deadline_
    ) external;

    /**
     * @notice Function allows the user to withdraw exchanged tokens of the newly provided liquidity.
     * @param allocationsIds Ids of locking token allocations of a user.
     */
    function withdrawExchangedTokens(
        uint256[] calldata allocationsIds
    ) external;

    /**
     * @notice Function returns the current state of the Lockdrop.
     * @return LockdropState current state of the lockdrop.
     */
    function state() external view returns (LockdropState);

    /**
     * @notice Function calculates the total reward earned by the wallet.
     * @param _wallet Address of the wallet for which the total reward will be calculated.
     * @return uint256 Total reward earned by the wallet.
     */
    function calculateTotalReward(
        address _wallet
    ) external view returns (uint256);

    /**
     * @notice Function returns address of the vesting contract.
     * @return ITokenVesting Reference to the vesting implementation.
     */
    function vesting() external view returns (ITokenVesting);

    /**
     * @notice Function returns address if phase2 contract
     * @return ILockdropPhase2 Reference to the phase2 implementation.
     */
    function phase2() external view returns (ILockdropPhase2);

    /**
     * @notice Function returns the address of token A.
     * @return address The address of token A.
     */
    function tokenAAddress() external view returns (address);

    /**
     * @notice Function returns the address of token B.
     * @return address The address of token B.
     */
    function tokenBAddress() external view returns (address);

    /**
     * @notice Function returns token A price
     * @return Price of the token.
     */
    function tokenAPrice() external view returns (uint256);

    /**
     * @notice Function returns token B price
     * @return Price of the token.
     */
    function tokenBPrice() external view returns (uint256);

    /**
     * @notice Function returns addresses of the pairs users can lock on the contract and the pairs' routers.
     * @return LockingToken[] Array of pair addresses with their routers.
     */
    function getLockingTokens() external view returns (LockingToken[] memory);

    /**
     * @notice Function returns locking expiration timestamps supported by the contract.
     * @return uint256[] Locking expiration timestamps supported by the contract.
     */
    function getLockingExpirationTimestamps()
        external
        view
        returns (uint256[] memory);

    /**
     * @notice Function returns total reward from the given allocation.
     * @param allocation Allocation from which the reward should be calculated.
     * @return uint256 Reward from allocations .
     */
    function calculateRewardFromAllocation(
        UserAllocation memory allocation
    ) external view returns (uint256);

    /**
     * @notice Function returns all allocations locked by the wallet.
     * @param _wallet Address of the wallet the allocation will be returned.
     * @return UserAllocation[] Allocations of user.
     */
    function getUserAllocations(
        address _wallet
    ) external view returns (UserAllocation[] memory);

    /**
     * @notice Function checks if the user has already calculated the reward.
     * @param _wallet address the wallet.
     * @return bool Indicates the reward calculation.
     */
    function isRewardCalculated(address _wallet) external view returns (bool);

    /**
     * @notice function calculates the reward from the allocations of the particular wallet.
     * @dev if the index is bigger than max count, the function reverts with AllocationDoesNotExist.
     * @param _wallet the address of the wallet.
     * @param _allocations array of the ids of allocations.
     * @return uint256 totalReward earned by wallet.
     */
    function calculateRewardFromAllocations(
        address _wallet,
        uint256[] calldata _allocations
    ) external view returns (uint256);

    /**
     * @notice Function used to calculate the price of one of the locking tokens.
     * @param _tokenIndex index of the token from the locking tokens array.
     * @return uint256 the price defined as the amount of ETH * 2**112.
     */
    function getLPTokenPrice(
        uint256 _tokenIndex
    ) external view returns (uint256);
}

