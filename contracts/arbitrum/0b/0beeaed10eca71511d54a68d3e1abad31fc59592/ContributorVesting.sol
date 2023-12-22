// SPDX-License-Identifier: AGPL
pragma solidity 0.8.13;

import "./VestingWallet.sol";

/**
 * @title   Contributor Vesting Vault
 * @notice  Vest tokens for a beneficiary, following a lump sum vesting schedule
 * @notice  After vesting midway point, user can opt to sell 20% of total vesting amount to DSQ multisig
 * @author  HessianX
 * @custom:developer    BowTiedPickle
 * @custom:developer    BowTiedOriole
 */
contract ContributorVesting is VestingWallet {
    // ----- Events -----

    event OTCSent(uint256 _amount);

    // ----- State Variables -----

    /// @notice Address of the team multisig
    address public immutable multisig;

    /// @notice Amount that the user sold to the multisig
    uint256 public otcAmount;

    // ----- Construction -----

    /**
     * @param   _beneficiaryAddress     Vesting beneficiary
     * @param   _startTimestamp         Start timestamp in unix epoch seconds
     * @param   _durationSeconds        Duration of vesting in seconds
     * @param   _multisig               Address of DSQ team multisig
     */

    constructor(
        address _beneficiaryAddress,
        uint64 _startTimestamp,
        uint64 _durationSeconds,
        address _multisig
    ) VestingWallet(_beneficiaryAddress, _startTimestamp, _durationSeconds) {
        multisig = _multisig;
    }

    // ----- State Changing -----

    /**
     * @notice  Sends 20% of lump sum amount to DSQ multisig
     * @dev     May only be called once
     * @param   _token  Address of token to OTC (Should always be DSQ)
     */
    function OTC(address _token) external {
        require(msg.sender == beneficiary(), "!beneficiary");
        require(block.timestamp > otcUnlockTime(), "!ready");
        require(otcAmount == 0, "executed");

        uint256 amount = IERC20(_token).balanceOf(address(this)) / 5;
        otcAmount = amount;
        SafeERC20.safeTransfer(IERC20(_token), multisig, amount);
        emit OTCSent(amount);
    }

    // ----- Views -----

    /**
     * @notice  Returns the vesting midpoint timestamp
     * @return  uint256 Timestamp of midpoint
     */
    function otcUnlockTime() public view returns (uint256) {
        return start() + (duration() / 2);
    }

    // ----- Overrides -----

    /**
     * @notice  Override of vestingSchedule from VestingWallet
     * @dev     Lump sum vesting schedule
     * @inheritdoc VestingWallet
     */
    function _vestingSchedule(uint256 totalAllocation, uint64 timestamp) internal view override returns (uint256) {
        if (timestamp < start() + duration()) {
            return 0;
        } else {
            return totalAllocation;
        }
    }
}

