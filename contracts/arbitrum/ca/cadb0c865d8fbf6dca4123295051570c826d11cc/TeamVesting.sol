// SPDX-License-Identifier: AGPL
pragma solidity 0.8.13;

import "./VestingWallet.sol";

/**
 * @title   DSquared Team Vesting Vault
 * @notice  Vest tokens for a team member, following a linear vesting schedule
 * @notice  After OTC unlock time, user can opt to sell 20% of total vesting amount to DSquared multisig
 * @author  HessianX
 * @custom:developer    BowTiedPickle
 * @custom:developer    BowTiedOriole
 */
contract TeamVesting is VestingWallet {
    // ----- Events -----

    event OTCSent(uint256 _amount);

    // ----- State Variables -----

    /// @notice Address of the team multisig
    address public immutable multisig;

    /// @notice Time that OTC unlocks
    uint64 public immutable otcUnlockTime;

    /// @notice Amount that the user sold to the multisig
    uint256 public otcAmount;

    // ----- Construction -----

    /**
     * @param   _beneficiaryAddress     Vesting beneficiary
     * @param   _otcUnlockTime          Unlock timestamp for OTC sale
     * @param   _startTimestamp         Vesting start timestamp in unix epoch seconds
     * @param   _durationSeconds        Duration of vesting in seconds
     * @param   _multisig               Address of DSquared team multisig
     */

    constructor(
        address _beneficiaryAddress,
        uint64 _otcUnlockTime,
        uint64 _startTimestamp,
        uint64 _durationSeconds,
        address _multisig
    ) VestingWallet(_beneficiaryAddress, _startTimestamp, _durationSeconds) {
        require(_otcUnlockTime < _startTimestamp, "params");
        otcUnlockTime = _otcUnlockTime;
        multisig = _multisig;
    }

    // ----- State Changing -----

    /**
     * @notice  Sends 20% of total tokens to DSquared multisig
     * @dev     May only be called once
     * @param   _token  Address of token to OTC (Should always be DSQ)
     */
    function OTC(address _token) external {
        require(msg.sender == beneficiary(), "!beneficiary");
        require(block.timestamp > otcUnlockTime, "!ready");
        require(otcAmount == 0, "executed");

        uint256 amount = IERC20(_token).balanceOf(address(this)) / 5;
        otcAmount = amount;
        SafeERC20.safeTransfer(IERC20(_token), multisig, amount);
        emit OTCSent(amount);
    }
}

