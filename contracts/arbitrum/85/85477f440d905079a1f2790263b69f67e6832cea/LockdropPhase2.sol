//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.18;

import {IUniswapV2Factory} from "./IUniswapV2Factory.sol";
import {ILockdropPhase2} from "./ILockdropPhase2.sol";
import {Lockdrop, IUniswapV2Router02, ILockdrop} from "./Lockdrop.sol";
import {IAccessControl} from "./IAccessControl.sol";

import {SafeERC20} from "./SafeERC20.sol";
import {IERC20} from "./IERC20.sol";

/**
 * @title LockdropPhase2
 * @notice The contract was created to raise funds in the form of Stable and SPARTA tokens,
 * which will be used to provide liquidity on Sparta DEX.
 * Users who choose to deposit a portion of their funds will be rewarded with a proportional amount of SPARTA token.
 * In addition, the user will receive a portion of the newly created liquidity tokens (proportionally to the funds deposited),
 * which will be paid out in a linear fashion over 6 months.
 */
contract LockdropPhase2 is ILockdropPhase2, Lockdrop {
    using SafeERC20 for IERC20;

    // uint256 internal constant LP_CLAIMING_DURATION = 26 * 7 days;
    uint256 internal constant LP_CLAIMING_DURATION = 1 days;
    bytes32 public constant LOCKDROP_PHASE_2_RESOLVER =
        keccak256("LOCKDROP_PHASE_2_RESOLVER");

    IERC20 public immutable sparta;
    IERC20 public immutable stable;

    uint256 public spartaTotalLocked;
    uint256 public stableTotalLocked;

    mapping(address => uint256) public override walletSpartaLocked;
    mapping(address => uint256) public override walletStableLocked;
    mapping(address => bool) public rewardTaken;
    mapping(address => uint256) public lpClaimed;

    /**
     * @notice Modifier created to check if the current state of lockdrop is as expected.
     * @dev Contract reverts with WrongLockdropState, when the state is different than expected.
     * @param expected LockdropState we should currently be in.
     */
    modifier onlyOnLockdropState(LockdropState expected) {
        LockdropState current = state();
        if (current != expected) {
            revert WrongLockdropState(current, expected);
        }
        _;
    }

    /**
     * @notice Modifier checks the signer of the message has the LOCKDROP_PHASE_2_RESOLVER role.
     * @dev Modifier reverts with OnlyLockdropPhase2ResolverAccess if the signer does not have the role.
     */
    modifier onlyLockdropPhase2Resolver() {
        if (!acl.hasRole(LOCKDROP_PHASE_2_RESOLVER, msg.sender)) {
            revert OnlyLockdropPhase2ResolverAccess();
        }
        _;
    }

    constructor(
        IAccessControl acl_,
        IERC20 sparta_,
        IERC20 stable_,
        uint256 lockingStart_,
        uint256 lockingEnd_,
        uint256 unlockingEnd_,
        uint256 migrationEndTimestamp_,
        uint256 totalReward_
    )
        Lockdrop(
            acl_,
            sparta_,
            lockingStart_,
            lockingEnd_,
            unlockingEnd_,
            migrationEndTimestamp_,
            totalReward_
        )
    {
        sparta = sparta_;
        stable = stable_;
    }

    /**
     * @inheritdoc ILockdropPhase2
     * @notice User can lock its tokens from the airdrop or reward from LockdropPhase1.
     * @dev Function reverts with WrongAllocationState if a user tries to lock the tokens before or after locking period.
     * @dev Function reverts ZeroAmount if someone tries to lock zero tokens.
     * @dev Function reverts ZeroAddress if someone tries to tokens for zero address.
     */
    function lockSparta(
        uint256 _amount,
        address _wallet
    )
        external
        onlyOnAllocationState(AllocationState.ALLOCATION_ONGOING)
        notZeroAmount(_amount)
        notZeroAddress(_wallet)
    {
        spartaTotalLocked += _amount;
        walletSpartaLocked[_wallet] += _amount;

        sparta.safeTransferFrom(msg.sender, address(this), _amount);

        emit Locked(msg.sender, _wallet, sparta, _amount);
    }

    /**
     * @inheritdoc ILockdropPhase2
     * @notice User can lock tokens directly on the contract.
     * @dev Function reverts with WrongAllocationState if a user tries to lock the tokens before or after the locking period.
     * @dev Function reverts ZeroAmount if someone tries to lock zero tokens.
     */
    function lockStable(
        uint256 _amount
    )
        external
        override
        onlyOnAllocationState(AllocationState.ALLOCATION_ONGOING)
        notZeroAmount(_amount)
    {
        stableTotalLocked += _amount;
        walletStableLocked[msg.sender] += _amount;
        stable.safeTransferFrom(msg.sender, address(this), _amount);

        emit Locked(msg.sender, msg.sender, stable, _amount);
    }

    function unlockSparta(
        uint256 _amount
    )
        external
        override
        notZeroAmount(_amount)
        onlyOnLockdropState(LockdropState.MIGRATION_END)
    {
        uint256 locked = walletSpartaLocked[msg.sender];
        if (_amount > locked) {
            revert CannotUnlock();
        }

        spartaTotalLocked -= _amount;
        walletSpartaLocked[msg.sender] -= _amount;
        sparta.safeTransfer(msg.sender, _amount);

        emit Unlocked(msg.sender, sparta, _amount);
    }

    /**
     * @inheritdoc ILockdropPhase2
     * @dev Function reverts with WrongLockdropState if a user tries to unlock the tokens before or after the unlocking period, or if the liquiidty was provided in the time range.
     * @dev Function reverts with CannotUnlock if a user tries to unlock more tokens than already locked.
     */
    function unlockStable(
        uint256 _amount
    ) external override notZeroAmount(_amount) {
        LockdropState state_ = state();
        if (
            !(state_ ==
                LockdropState.TOKENS_ALLOCATION_LOCKING_UNLOCKING_ONGOING ||
                state_ == LockdropState.MIGRATION_END)
        ) {
            revert CannotUnlock();
        }
        uint256 locked = walletStableLocked[msg.sender];
        if (_amount > locked) {
            revert CannotUnlock();
        }

        stableTotalLocked -= _amount;
        walletStableLocked[msg.sender] -= _amount;
        stable.safeTransfer(msg.sender, _amount);

        emit Unlocked(msg.sender, stable, _amount);
    }

    /**
     * @inheritdoc ILockdrop
     * @dev Function reverts with WrongLockdropState if a wallet tries to the provide liqudity before lockdrop end.
     */
    function addTargetLiquidity(
        IUniswapV2Router02 router_,
        uint256 deadline_
    )
        external
        override
        onlyOnLockdropState(LockdropState.TOKENS_ALLOCATION_FINISHED)
        onlyLockdropPhase2Resolver
    {
        if (
            IUniswapV2Factory(router_.factory()).getPair(
                address(stable),
                address(sparta)
            ) != address(0)
        ) {
            revert PairAlreadyCreated();
        }
        if (spartaTotalLocked == 0 || stableTotalLocked == 0) {
            revert CannotAddLiquidity();
        }
        sparta.forceApprove(address(router_), spartaTotalLocked);
        stable.forceApprove(address(router_), stableTotalLocked);

        spartaDexRouter = router_;

        (, , initialLpTokensBalance) = router_.addLiquidity(
            address(sparta),
            address(stable),
            spartaTotalLocked,
            stableTotalLocked,
            spartaTotalLocked,
            stableTotalLocked,
            address(this),
            deadline_
        );
    }

    /**
     * @inheritdoc ILockdropPhase2
     * @dev Function reverts with WrongLockdropState if a user tries to get tokens before the liqudity providing.
     * @dev Function reverts NothingToClaim if the sender does not have any SPARTA/StableCoin tokens to withdraw.
     */
    function claimTokens()
        external
        override
        onlyOnLockdropState(LockdropState.TOKENS_EXCHANGED)
    {
        uint256 toClaim = availableToClaim(msg.sender);
        if (toClaim == 0) {
            revert NothingToClaim();
        }
        lpClaimed[msg.sender] += toClaim;

        IERC20(exchangedPair()).safeTransfer(msg.sender, toClaim);

        emit TokensClaimed(msg.sender, toClaim);
    }

    /**
     * @inheritdoc ILockdropPhase2
     * @dev Function reverts with WrongLockdropState if a user tries to get the reward before the lockdrop end.
     * @dev Function reverts NothingToClaim if the sender does not have any reward to withdraw.
     */
    function getReward()
        external
        onlyOnLockdropState(LockdropState.TOKENS_EXCHANGED)
    {
        if (rewardTaken[msg.sender]) {
            revert RewardAlreadyTaken();
        }
        uint256 reward = calculateReward(msg.sender);
        if (reward == 0) {
            revert NothingToClaim();
        }
        rewardTaken[msg.sender] = true;
        sparta.safeTransfer(msg.sender, reward);

        emit RewardWitdhrawn(msg.sender, reward);
    }

    /**
     * @inheritdoc ILockdropPhase2
     */
    function calculateRewardForStable(
        uint256 stableAmount
    ) public view returns (uint256) {
        if (stableTotalLocked == 0) {
            return 0;
        }
        uint256 forSpartaReward = totalReward / 2;
        uint256 forStableReward = totalReward - forSpartaReward;
        return (forStableReward * stableAmount) / stableTotalLocked;
    }

    /**
     * @inheritdoc ILockdropPhase2
     */
    function calculateRewardForSparta(
        uint256 spartaAmount
    ) public view returns (uint256) {
        if (spartaTotalLocked == 0) {
            return 0;
        }
        uint256 forSpartaReward = totalReward / 2;
        return (forSpartaReward * spartaAmount) / spartaTotalLocked;
    }

    /**
     * @inheritdoc ILockdropPhase2
     */
    function calculateRewardForTokens(
        uint256 spartaAmount,
        uint256 stableAmount
    ) public view returns (uint256) {
        return
            calculateRewardForSparta(spartaAmount) +
            calculateRewardForStable(stableAmount);
    }

    /**
     * @inheritdoc ILockdropPhase2
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
        } else if (address(spartaDexRouter) == address(0)) {
            if (block.timestamp > migrationEndTimestamp) {
                return LockdropState.MIGRATION_END;
            }
            return LockdropState.TOKENS_ALLOCATION_FINISHED;
        }
        return LockdropState.TOKENS_EXCHANGED;
    }

    /**
     * @inheritdoc ILockdropPhase2
     */
    function calculateReward(
        address wallet_
    ) public view override returns (uint256) {
        return
            calculateRewardForTokens(
                walletSpartaLocked[wallet_],
                walletStableLocked[wallet_]
            );
    }

    /**
     * @inheritdoc ILockdrop
     */
    function exchangedPair()
        public
        view
        override
        onlyOnLockdropState(LockdropState.TOKENS_EXCHANGED)
        returns (address)
    {
        (address token0_, address token1_) = _tokens();

        return
            IUniswapV2Factory(spartaDexRouter.factory()).getPair(
                token0_,
                token1_
            );
    }

    /**
     * @inheritdoc ILockdropPhase2
     */
    function availableToClaim(
        address _wallet
    )
        public
        view
        onlyOnLockdropState(LockdropState.TOKENS_EXCHANGED)
        returns (uint256)
    {
        uint256 reward = calculateReward(_wallet);
        if (reward == 0) {
            return 0;
        }
        uint256 timeElapsedFromLockdropEnd = block.timestamp - lockingEnd;
        uint256 duration = timeElapsedFromLockdropEnd > LP_CLAIMING_DURATION
            ? LP_CLAIMING_DURATION
            : timeElapsedFromLockdropEnd;
        uint256 releasedFromVesting = (reward *
            initialLpTokensBalance *
            duration) / (totalReward * LP_CLAIMING_DURATION);
        return releasedFromVesting - lpClaimed[_wallet];
    }

    /**
     * @notice Function returns the sorted address of the SPARTA and StableCoin tokens.
     * @return (address, address) Sorted addresses of StableCoin and SPARTA tokens.
     */
    function _tokens() internal view returns (address, address) {
        (address spartaAddress, address stableAddress) = (
            address(sparta),
            address(stable)
        );
        return
            spartaAddress < stableAddress
                ? (spartaAddress, stableAddress)
                : (stableAddress, spartaAddress);
    }
}

