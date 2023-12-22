// SPDX-License-Identifier: AGPL
pragma solidity 0.8.13;

import "./VestingWallet.sol";

/**
 * @title   Team Vesting Vault
 * @notice  Vest tokens for a team member, following a lump sum unlock schedule.
 * @notice  Tokens accrue internally on a linear schedule. The team has the ability to revoke unearned tokens.
 * @notice  After vesting midway point, user can opt to sell 20% of total vesting amount to DSQ multisig
 * @author  HessianX
 * @custom:developer    BowTiedPickle
 * @custom:developer    BowTiedOriole
 */
contract TeamVesting is VestingWallet {
    // ----- Events -----

    event OTCSent(uint256 _amount);
    event Revoked(uint256 _amount);

    // ----- State Variables -----

    /// @notice Address of the team multisig
    address public immutable multisig;

    /// @notice Boolean whether or not the the beneficiary's vesting has been terminated
    bool public revoked;

    /// @notice Amount that the user sold to the multisig
    uint256 public otcAmount;

    // ----- Construction -----

    /**
     * @param   _beneficiaryAddress     Vesting beneficiary
     * @param   _startTimestamp         Start timestamp in unix epoch seconds
     * @param   _durationSeconds        Duration of vesting in seconds
     * @param   _multisig               Address of the team multisig
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
     * @notice  Sells 20% of total vesting tokens to DSQ multisig
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

    /**
     * @notice  Terminates further token vesting for user. Sends unaccrued rewards to multisig
     * @param   _token  Address of token to revoke (Should always be DSQ)
     */
    function revoke(address _token) external {
        require(msg.sender == multisig, "!multisig");
        require(!revoked, "revoked");

        revoked = true;
        uint256 amount = IERC20(_token).balanceOf(address(this)) + otcAmount;
        amount -= _vestingSchedule(amount, uint64(block.timestamp));

        SafeERC20.safeTransfer(IERC20(_token), multisig, amount);
        emit Revoked(amount);
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
     * @notice  Override of VestingWallet releaseable()
     * @dev     Will return 0 prior to vesting completion
     * @inheritdoc VestingWallet
     */
    function releasable() public view override returns (uint256) {
        if (block.timestamp < start() + duration()) {
            return 0;
        } else {
            return super.releasable();
        }
    }

    /**
     * @notice  Override of VestingWallet releaseable(address token)
     * @dev     Will return 0 prior to vesting completion
     * @param   token   Address of token to release
     * @inheritdoc VestingWallet
     */
    function releasable(address token) public view override returns (uint256) {
        if (block.timestamp < start() + duration()) {
            return 0;
        } else {
            return super.releasable(token);
        }
    }
}

