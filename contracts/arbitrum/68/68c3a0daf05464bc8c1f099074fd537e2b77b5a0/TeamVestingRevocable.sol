// SPDX-License-Identifier: AGPL
pragma solidity 0.8.13;

import "./TeamVesting.sol";

/**
 * @title   DSquared Team Vesting Vault
 * @notice  Vest tokens for a team member, following a linear unlock schedule.
 * @notice  Prior to unlock beginning, tokens accumulate internally on a linear schedule.
            The team has the ability to revoke unaccumulated tokens.
            Any unaccumulated tokens vest on linear unlock schedule after the unlock start time.
 * @notice  After OTC unlock time, user can opt to sell 20% of total vesting amount to DSQ multisig
 * @author  HessianX
 * @custom:developer    BowTiedPickle
 * @custom:developer    BowTiedOriole
 */
contract TeamVestingRevocable is TeamVesting {
    // ----- Events -----

    event Revoked(uint256 _amount);

    // ----- State Variables -----

    /// @notice Boolean whether or not the the beneficiary's vesting has been terminated
    bool public revoked;

    /// @notice Time that token accumulation begins/began
    uint64 public immutable accumulationStart;

    // ----- Construction -----

    /**
     * @param   _beneficiaryAddress     Vesting beneficiary address
     * @param   _accumulationStart      Timestamp for to token accumulation to begin in unix epoch seconds
     * @param   _otcUnlockTime          Unlock timestamp for OTC sale in unix epoch seconds
     * @param   _startTimestamp         Vesting start timestamp in unix epoch seconds
     * @param   _durationSeconds        Duration of vesting in seconds
     * @param   _multisig               Address of DSquared team multisig
     */

    constructor(
        address _beneficiaryAddress,
        uint64 _accumulationStart,
        uint64 _otcUnlockTime,
        uint64 _startTimestamp,
        uint64 _durationSeconds,
        address _multisig
    ) TeamVesting(_beneficiaryAddress, _otcUnlockTime, _startTimestamp, _durationSeconds, _multisig) {
        require(_accumulationStart < _otcUnlockTime, "params");
        accumulationStart = _accumulationStart;
    }

    // ----- State Changing -----

    /**
     * @notice  Terminates further token vesting for user. Sends unaccrued rewards to DSquared multisig
     * @dev     May only be called once
     * @param   _token  Address of token to revoke (Should always be DSQ)
     */
    function revoke(address _token) external {
        require(msg.sender == multisig, "!multisig");
        require(!revoked, "revoked");

        revoked = true;
        uint256 amount = IERC20(_token).balanceOf(address(this)) + otcAmount;
        amount -= _internalAccumulationSchedule(amount, uint64(block.timestamp));

        SafeERC20.safeTransfer(IERC20(_token), multisig, amount);
        emit Revoked(amount);
    }

    // ----- Internal -----

    /**
     * @notice  Internal view to return the amount of accumulated tokens
     * @dev     Linear accumulation schedule from accumulationStart to _start
     * @param   totalAllocation Total token allocation
     * @param   timestamp       Timestamp to calculate amount accumlated
     * @return  Token amount accumulated
     */
    function _internalAccumulationSchedule(uint256 totalAllocation, uint64 timestamp) internal view returns (uint256) {
        if (timestamp < accumulationStart) return 0;
        if (timestamp < start()) {
            return (totalAllocation * (timestamp - accumulationStart)) / ((start() - accumulationStart));
        } else {
            return totalAllocation;
        }
    }
}

