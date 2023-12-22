// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { PausableUpgradeable } from "./PausableUpgradeable.sol";
import { ControllableUpgradeable } from "./ControllableUpgradeable.sol";
import { ERC20Burnable } from "./ERC20Burnable.sol";
import { IERC20 } from "./IERC20.sol";
import { Constants } from "./Constants.sol";

// @dev contains logic for accepting TAU yield and distributing it to users over time to protect against sandwich attacks.
abstract contract TauDripFeed is PausableUpgradeable, ControllableUpgradeable {
    // Emit event when the tau rewards are distributed
    event TauRewardsDistributed(address indexed fromAddress, uint256 amount);

    // @dev total amount of tau tokens that have ever been rewarded to the contract, divided by the total collateral present at the time of each deposit.
    // This number can only increase.
    uint256 public cumulativeTauRewardPerCollateral;

    /// @dev Tau tokens yet to be doled out to the vault. Tokens yet to be doled out are not counted towards cumulativeTauRewardPerCollateral.
    uint256 public tauWithheld;

    /// @dev timestamp at which tokens were most recently disbursed. Updated only when tauWithheld > 0. Used in conjunction with DRIP_DURATION to
    /// calculate next token disbursal amount.
    uint256 public tokensLastDisbursedTimestamp;

    /// @dev duration of the drip feed. Deposited TAU is steadily distributed to the contract over this amount of time.
    uint256 public constant DRIP_DURATION = 1 days;

    /// @dev address of TAU
    address public tau;

    /// @dev address of token used as collateral by this vault.
    address public collateralToken;
    uint256 public collateralPrecision;

    function __TauDripFeed_init(address _tau, address _collateralToken) internal initializer {
        __Pausable_init();
        tau = _tau;
        collateralToken = _collateralToken;
        collateralPrecision = 10 ** ERC20Burnable(_collateralToken).decimals();
    }

    function pause() external onlyMultisig {
        _pause();
    }

    function unpause() external onlyMultisig {
        _unpause();
    }

    /**
     * @dev function to deposit TAU into the contract while averting sandwich attacks.
     * @param amount is the amount of TAU to be burned and used to cancel out debt.
     * note the main source of TAU is the SwapHandler. This function is just a safeguard in case some other source of TAU arises.
     */
    function distributeTauRewards(uint256 amount) external whenNotPaused {
        // Burn depositor's Tau
        ERC20Burnable(tau).burnFrom(msg.sender, amount);

        // Disburse available tau
        _disburseTau();

        // Set new tau aside to protect against sandwich attacks
        _withholdTau(amount);

        emit TauRewardsDistributed(msg.sender, amount);
    }

    function disburseTau() external whenNotPaused {
        _disburseTau();
    }

    /**
     * @dev disburse TAU to the contract by updating cumulativeTauRewardPerCollateral.
     * Note that since rewards are distributed based on timeElapsed / DRIP_DURATION, this function will technically only distribute 100% of rewards if it is not called
        until the DRIP_DURATION has elapsed. This isn't too much of an issue--at worst, about 2/3 of the rewards will be distributed per DRIP_DURATION, the rest carrying over
        to the next DRIP_DURATION.
     * Note that if collateral == 0, tokens will not be disbursed. This prevents undefined behavior when rewards are deposited before collateral is.
     */
    function _disburseTau() internal {
        if (tauWithheld > 0) {
            uint256 _normalizedCollateralBalance = normaliseCollateralDecimals(
                IERC20(collateralToken).balanceOf(address(this))
            );

            if (_normalizedCollateralBalance > 0) {
                // Get tokens to disburse since last disbursal
                uint256 _timeElapsed = block.timestamp - tokensLastDisbursedTimestamp;

                uint256 _tokensToDisburse;
                if (_timeElapsed >= DRIP_DURATION) {
                    _tokensToDisburse = tauWithheld;
                    tauWithheld = 0;
                } else {
                    _tokensToDisburse = (_timeElapsed * tauWithheld) / DRIP_DURATION;
                    tauWithheld -= _tokensToDisburse;
                }

                // Divide by current collateral to get the additional tokensPerCollateral which we'll be adding to the cumulative sum
                uint256 _extraRewardPerCollateral = (_tokensToDisburse * Constants.PRECISION) /
                    _normalizedCollateralBalance;

                cumulativeTauRewardPerCollateral += _extraRewardPerCollateral;

                tokensLastDisbursedTimestamp = block.timestamp;
            }
        }
    }

    /**
     * @dev internal function to deposit TAU into the contract while averting sandwich attacks.
     * This is primarily meant to be called by the SwapHandler, which is the smart contract's source of TAU.
     * It is also called by the BaseVault when an account earns TAU rewards in excess of their debt.
     * Note that this function should generally only be called after disburseTau has been called.
     */
    function _withholdTau(uint256 amount) internal {
        // Update block.timestamp in case it hasn't been updated yet this transaction.
        tokensLastDisbursedTimestamp = block.timestamp;
        tauWithheld += amount;
    }

    function normaliseCollateralDecimals(uint256 _amount) public view returns (uint256 finalValue) {
        finalValue = (_amount * Constants.PRECISION) / collateralPrecision;
    }

    function renormaliseCollateralDecimals(uint256 _amount) public view returns (uint256 finalValue) {
        finalValue = (_amount * collateralPrecision) / Constants.PRECISION;
    }

    uint256[44] private __gap;
}

