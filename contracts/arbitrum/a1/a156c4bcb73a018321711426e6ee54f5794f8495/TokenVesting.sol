//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.18;

import {ITokenVesting} from "./ITokenVesting.sol";
import {WithFees} from "./WithFees.sol";
import {ZeroAddressGuard} from "./ZeroAddressGuard.sol";
import {ZeroAmountGuard} from "./ZeroAmountGuard.sol";
import {IAccessControlHolder, IAccessControl} from "./IAccessControlHolder.sol";

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";

/**
 * @title TokenVesting
 * @notice This contract is used for creating vesting schedules for token allocations and allowing beneficiaries to claim their vested tokens.
 */
contract TokenVesting is
    ITokenVesting,
    WithFees,
    ZeroAddressGuard,
    ZeroAmountGuard
{
    using SafeERC20 for IERC20;

    bytes32 public constant VESTING_MANAGER = keccak256("VESTING_MANAGER");
    uint256 public constant MAX_SCHEDULES = 5;

    IERC20 public immutable token;

    mapping(address => Vesting[]) public vestingSchedules;
    mapping(address => uint256) public vestingCounts;

    /**
     * @notice Modifier that allows only the vesting manager to call a function.
     * @dev Modifier reverts with OnlyVestingManagerAccess.
     */
    modifier onlyVestingManagerAccess() {
        if (!acl.hasRole(VESTING_MANAGER, msg.sender)) {
            revert OnlyVestingManagerAccess();
        }
        _;
    }

    constructor(
        IERC20 _token,
        IAccessControl _acl,
        address _treasury,
        uint256 _value
    ) WithFees(_acl, _treasury, _value) {
        token = _token;
    }

    /**
     * @inheritdoc ITokenVesting
     * @dev The tokens for the vesting schedule are transferred from the sender to this contract.
     * @dev Function reverts with ZeroAddress, if the address of the beneficiary is zer.
     */
    function addVesting(
        address beneficiary,
        uint256 startTime,
        uint256 duration,
        uint256 amount
    )
        external
        onlyVestingManagerAccess
        notZeroAddress(beneficiary)
        notZeroAmount(duration)
        notZeroAmount(amount)
    {
        uint256 endTime = startTime + duration;
        vestingSchedules[beneficiary].push(
            Vesting({
                startTime: startTime,
                endTime: endTime,
                totalAmount: amount,
                claimedAmount: 0
            })
        );

        ++vestingCounts[beneficiary];

        token.safeTransferFrom(msg.sender, address(this), amount);

        emit VestingAdded(
            beneficiary,
            vestingSchedules[beneficiary].length - 1,
            startTime,
            endTime,
            amount
        );
    }

    /**
     * @inheritdoc ITokenVesting
     * @dev if the timestamp is lower than vesting start, the function reverts with VestingNotStarted.
     * @dev if a user has already withdrawn all tokens, the funciton reverts with AllTokensClaimed.
     * @dev if a scheduleId is bigger than last index of the schedules, the function reverts with InvalidScheduleID.
     */
    function claim(
        uint256[] calldata scheduleIds
    ) external payable onlyWithFees {
        uint256 claimableAmount = 0;
        Vesting[] storage schedules = vestingSchedules[msg.sender];
        uint256 scheduleIdsLength = scheduleIds.length;

        if (scheduleIdsLength > MAX_SCHEDULES) {
            revert MaxSchedules();
        }

        for (uint256 i = 0; i < scheduleIdsLength; ) {
            uint256 id = scheduleIds[i];

            if (id >= schedules.length) {
                revert InvalidScheduleID();
            }

            Vesting storage vestingSchedule = schedules[id];

            if (block.timestamp < vestingSchedule.startTime) {
                revert VestingNotStarted();
            }

            if (vestingSchedule.totalAmount <= vestingSchedule.claimedAmount) {
                revert AllTokensClaimed();
            }

            uint256 vestingDuration = vestingSchedule.endTime -
                vestingSchedule.startTime;
            uint256 elapsedTime = block.timestamp > vestingSchedule.endTime
                ? vestingDuration
                : block.timestamp - vestingSchedule.startTime;

            uint256 vestedAmount = (vestingSchedule.totalAmount * elapsedTime) /
                vestingDuration;
            uint256 unclaimedAmount = vestedAmount -
                vestingSchedule.claimedAmount;

            vestingSchedule.claimedAmount = vestedAmount;
            claimableAmount += unclaimedAmount;

            emit TokenWithdrawn(msg.sender, id, unclaimedAmount);

            unchecked {
                ++i;
            }
        }

        token.safeTransfer(msg.sender, claimableAmount);
    }
}

