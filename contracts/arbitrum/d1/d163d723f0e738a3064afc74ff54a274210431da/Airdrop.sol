// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.18;

import {IAccessControlHolder, IAccessControl} from "./IAccessControlHolder.sol";
import {IAirdrop, ISparta, ILockdropPhase2} from "./IAirdrop.sol";
import {WithFees} from "./WithFees.sol";
import {ZeroAmountGuard} from "./ZeroAmountGuard.sol";
import {ZeroAddressGuard} from "./ZeroAddressGuard.sol";
import {ITokenVesting} from "./ITokenVesting.sol";

import {SafeERC20} from "./SafeERC20.sol";

/**
 * @title Airdrop contract.
 * @notice Handles distribution of airdrop tokens, allowing users to claim their allocated tokens
 */
contract Airdrop is
    IAccessControlHolder,
    IAirdrop,
    WithFees,
    ZeroAmountGuard,
    ZeroAddressGuard
{
    using SafeERC20 for ISparta;

    bytes32 public constant AIRDROP_MANAGER = keccak256("AIRDROP_MANAGER");
    // uint256 public constant VESTING_DURATION = 30 days * 3;
    uint256 public constant VESTING_DURATION = 6 hours;
    uint256 public constant SET_CLAIMABLE_MAX_LENGTH = 15;

    ISparta public immutable sparta;
    ITokenVesting public immutable vesting;
    uint256 public immutable claimStartTimestamp;
    ILockdropPhase2 public immutable lockdrop;
    uint256 public immutable override burningStartTimestamp;
    uint256 public totalLocked;
    mapping(address => uint256) public claimableAmounts;
    mapping(address => uint256) public onLockdrop;

    /**
     * @notice Modifier ensures that the caller has the AIRDROP_MANAGER role.
     * @dev Modifier reverts with OnlyAirdropManagerRole, if the sender does not have a role.
     */
    modifier onlyAirdropManagerRole() {
        if (!acl.hasRole(AIRDROP_MANAGER, msg.sender)) {
            revert OnlyAirdropManagerRole();
        }
        _;
    }

    /**
     * @notice Modifier ensures that the current time is after the burning start timestamp.
     * @dev If the current time is not after the burning start timestamp, the transaction is reverted with the CannotBurnTokens error.
     */
    modifier onlyAfterBurningTimestamp() {
        if (burningStartTimestamp > block.timestamp) {
            revert CannotBurnTokens();
        }
        _;
    }

    constructor(
        ISparta _sparta,
        uint256 _claimStartTimestamp,
        ILockdropPhase2 _lockdrop,
        ITokenVesting _vesting,
        IAccessControl _acl,
        uint256 _burningStartTimestamp,
        address _treasury,
        uint256 _value
    ) WithFees(_acl, _treasury, _value) {
        sparta = _sparta;
        if (block.timestamp > _claimStartTimestamp) {
            revert ClaimStartNotValid();
        }
        if (_claimStartTimestamp > _burningStartTimestamp) {
            revert WrongTimestamps();
        }
        vesting = _vesting;
        claimStartTimestamp = _claimStartTimestamp;
        lockdrop = _lockdrop;
        burningStartTimestamp = _burningStartTimestamp;
    }

    /**
     * @inheritdoc IAirdrop
     * @dev Emits a WalletAdded event for each user.
     * @dev If the arrays length is different, the function reverts with ArraysLengthNotSame error.
     * @dev If the arrays length is bigger than SET_CLAIMABLE_MAX, the function reverts with MaxLengthExceeded error.
     * @dev If any value of the users array is address(0), the function reverts with ZeroAddress.
     * @dev If any value of the amounts array is 0, the function reverts with ZeroAmount.
     */
    function setClaimableAmounts(
        address[] memory users,
        uint256[] memory amounts
    ) external override onlyAirdropManagerRole {
        if (users.length != amounts.length) {
            revert ArraysLengthNotSame();
        }

        uint256 length = users.length;
        if (length > SET_CLAIMABLE_MAX_LENGTH) {
            revert MaxLengthExceeded();
        }
        uint256 sum = 0;

        for (uint256 i = 0; i < length; ) {
            uint256 amount = amounts[i];
            _ensureIsNotZero(amount);
            address wallet = users[i];
            _ensureIsNotZeroAddress(wallet);
            sum += amount;
            claimableAmounts[wallet] += amount;
            unchecked {
                ++i;
            }
            emit WalletAdded(wallet, amount);
        }

        if (totalLocked + sum > sparta.balanceOf(address(this))) {
            revert BalanceTooSmall();
        }

        totalLocked += sum;
    }

    /**
     * @inheritdoc IAirdrop
     * @notice Function allows the user to claim his tokens. The user needs to pay a particular fee
     * @dev Transfers the claimed amount to the user and emits a Claimed event.
     * @dev If the timestamp is lower than claimStartTimestamp, the function reverts with BeforeReleaseTimestamp.
     * @dev If the amount of tokens to claim is zero, the function reverts with ZeroAmount error.
     */
    function claimTokens() external payable override onlyWithFees {
        if (claimStartTimestamp > block.timestamp) {
            revert BeforeReleaseTimestamp();
        }

        uint256 amount = claimableAmounts[msg.sender];
        _ensureIsNotZero(amount);

        uint256 onLockdropPhase2 = onLockdrop[msg.sender];
        uint256 onLockdropPhase2Max = claimableAmounts[msg.sender] / 2;
        uint256 toSend = onLockdropPhase2Max - onLockdropPhase2;
        uint256 onVesting = amount - onLockdropPhase2Max;

        claimableAmounts[msg.sender] = 0;

        sparta.forceApprove(address(vesting), onVesting);
        vesting.addVesting(
            msg.sender,
            claimStartTimestamp,
            VESTING_DURATION,
            onVesting
        );

        if (toSend > 0) {
            sparta.safeTransfer(msg.sender, toSend);
        }

        emit Claimed(msg.sender, amount);
    }

    /**
     * @inheritdoc IAirdrop
     * @notice Allows the user to lock their tokens in the LockdropPhase2 contract.
     * @dev If the amount is equal 0, the function reverts with ZeroAmount.
     */
    function lockOnLockdropPhase2(uint256 _amount) external override {
        _ensureIsNotZero(_amount);
        uint256 onLockdropAlready = onLockdrop[msg.sender];
        uint256 toAllocateMax = claimableAmounts[msg.sender] / 2;
        if (onLockdropAlready + _amount > toAllocateMax) {
            revert LimitExceeded();
        }
        onLockdrop[msg.sender] += _amount;
        sparta.forceApprove(address(lockdrop), _amount);
        lockdrop.lockSparta(_amount, msg.sender);

        emit LockedOnLockdropPhase2(msg.sender, _amount);
    }

    /**
     * @inheritdoc IAirdrop
     * @dev Can only be called by an address with the AIRDROP_MANAGER role and after the burning start timestamp.
     */
    function burnTokens()
        external
        override
        onlyAirdropManagerRole
        onlyAfterBurningTimestamp
    {
        sparta.burn(sparta.balanceOf(address(this)));
    }
}

