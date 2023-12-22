// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./LibDiamond.sol";
import "./ReentrancyGuard.sol";
import {WithOwnership} from "./WithOwnership.sol";
import {Strings} from "./Strings.sol";
import "./SafeERC20.sol";
import {IHamachi} from "./IHamachi.sol";
import "./IERC20.sol";

contract VestingFacet is WithOwnership, WithStorage, ReentrancyGuard {
    using Strings for uint256;
    using SafeERC20 for IERC20;

    // ==================== Errors ==================== //

    error VestingNotExists();
    error VestingExists();
    error Unauthorized();
    error InvalidReleaseAmount();
    error InvalidDuration();
    error InvalidAmount();
    error InvalidSlicePeriod();

    // ==================== Management ==================== //

    function createVestingSchedules(
        LibDiamond.CreateVesting[] calldata vestingschedules
    ) external {
        uint256 n = vestingschedules.length;
        for (uint256 i = 0; i < n; ++i) {
            createVestingSchedule(
                vestingschedules[i]._beneficiary,
                vestingschedules[i]._start,
                vestingschedules[i]._cliff,
                vestingschedules[i]._duration,
                vestingschedules[i]._slicePeriodSeconds,
                vestingschedules[i]._amount
            );
        }
    }

    /**
     * @notice Creates a new vesting schedule for a beneficiary.
     * @param _beneficiary address of the beneficiary to whom vested tokens are transferred
     * @param _start start time of the vesting period
     * @param _cliff duration in seconds of the cliff in which tokens will begin to vest
     * @param _duration duration in seconds of the period in which the tokens will vest
     * @param _slicePeriodSeconds duration of a slice period for the vesting in seconds
     * @param _amount total amount of tokens to be released at the end of the vesting
     */
    function createVestingSchedule(
        address _beneficiary,
        uint256 _start,
        uint256 _cliff,
        uint256 _duration,
        uint256 _slicePeriodSeconds,
        uint256 _amount
    ) public {
        LibDiamond.enforceIsContractOwner();

        if (_vs().vestingSchedules[_beneficiary].initialized == true)
            revert VestingExists();

        if (_duration <= 0) revert InvalidDuration();
        if (_amount <= 0) revert InvalidAmount();
        if (_slicePeriodSeconds < 1) revert InvalidSlicePeriod();
        _vs().vestingSchedules[_beneficiary] = LibDiamond.VestingSchedule(
            true,
            _beneficiary,
            _cliff,
            _start,
            _duration,
            _slicePeriodSeconds,
            _amount,
            0
        );
        _vs().totalAmountInVesting += _amount;

        require(
            IERC20(_vs().token).transferFrom(msg.sender, address(this), _amount)
        );

        IHamachi(_vs().token).updateRewardBalance(
            _beneficiary,
            int256(_amount)
        );
    }

    /**
     * @notice Release vested amount of tokens.
     * @param _beneficiary the vesting _beneficiary
     * @param _amount the amount to release
     */
    function release(address _beneficiary, uint256 _amount)
        external
        nonReentrant
    {
        if (_vs().vestingSchedules[_beneficiary].initialized != true)
            revert VestingNotExists();

        LibDiamond.VestingSchedule storage vestingSchedule = _vs()
            .vestingSchedules[_beneficiary];

        if (
            msg.sender != LibDiamond.contractOwner() &&
            msg.sender != vestingSchedule.beneficiary
        ) revert Unauthorized();

        if (_computeReleasableAmount(vestingSchedule) < _amount)
            revert InvalidReleaseAmount();

        vestingSchedule.released += _amount;
        _vs().totalAmountInVesting -= _amount;

        IERC20(_vs().token).safeTransfer(vestingSchedule.beneficiary, _amount);
    }

    // ==================== Views ==================== //

    // Returns the total amount of $HAM in vesting.
    function getTotalAmountInVesting() public view returns (uint256) {
        return _vs().totalAmountInVesting;
    }

    // Computes the vested amount of tokens for the given vesting schedule identifier.
    function computeReleasableAmount(address _beneficiary)
        external
        view
        returns (uint256)
    {
        LibDiamond.VestingSchedule storage vestingSchedule = _vs()
            .vestingSchedules[_beneficiary];

        return
            _vs().vestingSchedules[_beneficiary].initialized
                ? _computeReleasableAmount(vestingSchedule)
                : 0;
    }

    // Returns the vesting schedule information for a given identifier.
    function getVestingSchedule(address _beneficiary)
        external
        view
        returns (
            bool initialized,
            address beneficiary,
            uint256 cliff,
            uint256 start,
            uint256 duration,
            uint256 slicePeriodSeconds,
            uint256 amountTotal,
            uint256 released
        )
    {
        LibDiamond.VestingSchedule memory vs = _vs().vestingSchedules[
            _beneficiary
        ];
        return (
            vs.initialized,
            vs.beneficiary,
            vs.cliff,
            vs.start,
            vs.duration,
            vs.slicePeriodSeconds,
            vs.amountTotal,
            vs.released
        );
    }

    // ==================== Internal ==================== //

    // Computes the releasable amount of tokens for a vesting schedule.
    function _computeReleasableAmount(
        LibDiamond.VestingSchedule memory vestingSchedule
    ) internal view returns (uint256) {
        uint256 currentTime = block.timestamp;
        uint256 startWithCliff = vestingSchedule.start + vestingSchedule.cliff;
        if (currentTime < startWithCliff) {
            return 0;
        } else if (currentTime >= startWithCliff + vestingSchedule.duration) {
            return vestingSchedule.amountTotal - vestingSchedule.released;
        } else {
            uint256 timeFromEndCliff = currentTime - startWithCliff;
            uint256 secondsPerSlice = vestingSchedule.slicePeriodSeconds;
            uint256 vestedSlicePeriods = timeFromEndCliff / secondsPerSlice;
            uint256 vestedSeconds = vestedSlicePeriods * secondsPerSlice;
            uint256 vestedAmount = (vestingSchedule.amountTotal *
                vestedSeconds) / vestingSchedule.duration;
            vestedAmount = vestedAmount - vestingSchedule.released;
            return vestedAmount;
        }
    }
}

