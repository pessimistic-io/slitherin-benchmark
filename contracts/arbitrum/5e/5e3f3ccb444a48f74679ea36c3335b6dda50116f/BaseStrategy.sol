// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;
pragma experimental ABIEncoderV2;

import "./console.sol";

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {SafeMath} from "./SafeMath.sol";

import "./IVault.sol";

/**
 * @title Base Strategy
 * @author yearn.finance original author. Code has been modified & simplified
 * @notice
 *  BaseStrategy implements all of the required functionality to interoperate
 *  closely with the Vault contract. This contract should be inherited and the
 *  abstract methods implemented to adapt the Strategy to the particular needs
 *  it has to create a return.
 *
 */

abstract contract BaseStrategy {
    using SafeMath for uint256;
    string public metadataURI;

    /**
     * @notice Base strategy version.
     * @return A string which holds the current version of this contract.
     */
    function version() public pure returns (string memory) {
        return "0.1.0";
    }

    /**
     * @notice This Strategy's name.
     * @return The name.
     */
    function name() external view virtual returns (string memory);

    IVault public vault;
    address public strategist;

    IERC20 public want; // MIM-2CRV

    // So indexers can keep track of this
    event Harvested(uint256 profit);

    event UpdatedStrategist(address newStrategist);

    event UpdatedKeeper(address newKeeper);

    event EmergencyExitEnabled();

    event UpdatedMetadataURI(string metadataURI);

    // See note on `setEmergencyExit()`.
    bool public emergencyExit;

    // modifiers
    function _onlyAuthorized() internal view {
        require(msg.sender == strategist || msg.sender == governance());
    }

    function _onlyStrategist() internal view {
        require(msg.sender == strategist);
    }

    function _onlyGovernance() internal view {
        require(msg.sender == governance());
    }

    modifier onlyAuthorized() {
        _onlyAuthorized();
        _;
    }

    modifier onlyStrategist() {
        _onlyStrategist();
        _;
    }

    modifier onlyGovernance() {
        _onlyGovernance();
        _;
    }

    constructor(address _vault) {
        _initialize(_vault, msg.sender);
    }

    /**
     * @notice
     *  Initializes the Strategy, this is called only once, when the
     *  contract is deployed.
     * @dev `_vault` should implement `IVault`.
     * @param _vault The address of the Vault responsible for this Strategy.
     * @param _strategist The address to assign as `strategist`.
     * The strategist is able to change the reward address
     * can harvest and tend a strategy.
     */
    function _initialize(address _vault, address _strategist) internal {
        require(address(want) == address(0), "Strategy already initialized");
        vault = IVault(_vault);
        want = IERC20(vault.token());
        SafeERC20.safeApprove(want, _vault, type(uint256).max); // Give Vault unlimited access (might save gas)
        strategist = _strategist;
    }

    /**
     * @notice
     *  Used to change `strategist`.
     *
     *  This may only be called by governance or the existing strategist.
     * @param _strategist The new address to assign as `strategist`.
     */
    function setStrategist(address _strategist) external onlyAuthorized {
        require(_strategist != address(0));
        strategist = _strategist;
        emit UpdatedStrategist(_strategist);
    }

    /**
     * @notice
     *  Used to change `metadataURI`. `metadataURI` is used to store the URI
     * of the file describing the strategy.
     *
     *  This may only be called by governance or the strategist.
     * @param _metadataURI The URI that describe the strategy.
     */
    function setMetadataURI(string calldata _metadataURI) external onlyAuthorized {
        metadataURI = _metadataURI;
        emit UpdatedMetadataURI(_metadataURI);
    }

    /**
     * Resolve governance address from Vault contract, used to make assertions
     * on protected functions in the Strategy.
     */
    function governance() internal view returns (address) {
        return vault.governance();
    }

    /**
     * @notice
     *  Provide an accurate conversion from `_amtInWei` (denominated in wei)
     *  to `want` (using the native decimal characteristics of `want`).
     * @dev
     *  Care must be taken when working with decimals to assure that the conversion
     *  is compatible. As an example:
     *
     *      given 1e17 wei (0.1 ETH) as input, and want is USDC (6 decimals),
     *      with USDC/ETH = 1800, this should give back 180000000 (180 USDC)
     *
     * @param _amtInWei The amount (in wei/1e-18 ETH) to convert to `want`
     * @return The amount in `want` of `_amtInEth` converted to `want`
     **/
    function ethToWant(uint256 _amtInWei) public view virtual returns (uint256);

    /**
     * @notice
     *  Provide an accurate estimate for the total amount of assets
     *  (principle + return) that this Strategy is currently managing,
     *  denominated in terms of `want` tokens.
     *
     *  This total should be "realizable" e.g. the total value that could
     *  *actually* be obtained from this Strategy if it were to divest its
     *  entire position based on current on-chain conditions.
     * @dev
     *  Care must be taken in using this function, since it relies on external
     *  systems, which could be manipulated by the attacker to give an inflated
     *  (or reduced) value produced by this function, based on current on-chain
     *  conditions (e.g. this function is possible to influence through
     *  flashloan attacks, oracle manipulations, or other DeFi attack
     *  mechanisms).
     *
     *  It is up to governance to use this function to correctly order this
     *  Strategy relative to its peers in the withdrawal queue to minimize
     *  losses for the Vault based on sudden withdrawals. This value should be
     *  higher than the total debt of the Strategy and higher than its expected
     *  value to be "safe".
     * @return The estimated total assets in this Strategy.
     */
    function estimatedTotalAssets() public view virtual returns (uint256);

    /**
     * @notice
     *  Provide an indication of whether this strategy is currently "active"
     *  in that it is managing an active position, or will manage a position in
     *  the future. This should correlate to `harvest()` activity, so that Harvest
     *  events can be tracked externally by indexing agents.
     * @return True if the strategy is actively managing a position.
     */
    function isActive() public view returns (bool) {
        return estimatedTotalAssets() > 0;
    }

    /**
     * Perform any Strategy unwinding or other calls necessary to capture the
     * "free return" this Strategy has generated since the last time its core
     * position(s) were adjusted. Examples include unwrapping extra rewards.
     * This call is only used during "normal operation" of a Strategy, and
     * should be optimized to minimize losses as much as possible.
     *
     * This method returns any realized profits
     */
    function prepareReturn() internal virtual returns (uint256 _profit);

    /**
     * Perform any adjustments to the core position(s) of this Strategy given
     * what change the Vault made in the "investable capital" available to the
     * Strategy.
     */
    function adjustPosition() public virtual;

    /**
     * Liquidate up to `_amountNeeded` of `want` of this strategy's positions,
     * irregardless of slippage. Any excess will be re-invested with `adjustPosition()`.
     * This function should return the amount of `want` tokens made available by the
     * liquidation.
     *
     * NOTE: We do not consider "loss" as being possible in this function
     */
    function liquidatePosition(uint256 _amountNeeded) internal virtual returns (uint256 _liquidatedAmount);

    /**
     * Liquidate everything and returns the amount that got freed.
     * This function is used during emergency exit instead of `prepareReturn()` to
     * liquidate all of the Strategy's positions back to the Vault.
     */

    function liquidateAllPositions() internal virtual returns (uint256 _amountFreed);

    /**
     * @notice
     *  Harvests the Strategy, recognizing any profits or losses and adjusting
     *  the Strategy's position.
     *
     *  In the rare case the Strategy is in emergency shutdown, this will exit
     *  the Strategy's position.
     *
     *  This may only be called by governance, the strategist, or the keeper.
     */
    function harvest() external onlyAuthorized {
        uint256 profit = 0;
        if (emergencyExit) {
            // Free up as much capital as possible
            profit = liquidateAllPositions();
        } else {
            // Free up returns for Vault to pull
            profit = prepareReturn();
        }
        // Check if free returns are left, and re-invest them
        adjustPosition();
        emit Harvested(profit);
    }

    function deposit() public {
        adjustPosition();
    }

    /**
     * @notice
     *  Withdraws `_amountNeeded` to `vault`.
     *
     *  This may only be called by the Vault.
     * @param _amountNeeded How much `want` to withdraw.
     */
    // NOTE - withdraw can be in the base strategy because it only needs to know about the vault
    // and the want token. Then it can just call on liquidatePosition
    function withdraw(uint256 _amountNeeded) external {
        require(msg.sender == address(vault), "!vault");
        // Liquidate as much as possible to `want`, up to `_amountNeeded`
        uint256 amountFreed = liquidatePosition(_amountNeeded);

        // Send it directly back (NOTE: Using `msg.sender` saves some gas here)
        SafeERC20.safeTransfer(want, msg.sender, amountFreed);
        // NOTE: Reinvest anything leftover on next `tend`/`harvest`
    }

    /**
     * @notice
     *  Activates emergency exit. Once activated, the Strategy will exit its
     *  position upon the next harvest, depositing all funds into the Vault as
     *  quickly as is reasonable given on-chain conditions.
     *
     *  This may only be called by governance or the strategist.
     * @dev
     *  See `vault.setEmergencyShutdown()` and `harvest()` for further details.
     */
    function setEmergencyExit() external onlyAuthorized {
        emergencyExit = true;
        emit EmergencyExitEnabled();
    }

    /**
     * Override this to add all tokens/tokenized positions this contract
     * manages on a *persistent* basis (e.g. not just for swapping back to
     * want ephemerally).
     *
     * NOTE: Do *not* include `want`, already included in `sweep` below.
     */
    function _protectedTokens() internal view virtual returns (address[] memory);

    /**
     * @notice
     *  Removes tokens from this Strategy that are not the type of tokens
     *  managed by this Strategy. This may be used in case of accidentally
     *  sending the wrong kind of token to this Strategy.
     *
     *  Tokens will be sent to `governance()`.
     *
     *  This will fail if an attempt is made to sweep `want`, or any tokens
     *  that are protected by this Strategy.
     *
     *  This may only be called by governance.
     * @dev
     *  Implement `_protectedTokens()` to specify any additional tokens that
     *  should be protected from sweeping in addition to `want`.
     * @param _token The token to transfer out of this vault.
     */
    function sweep(address _token) external onlyGovernance {
        require(_token != address(want), "!want");
        require(_token != address(vault), "!shares");

        address[] memory protectedTokens = _protectedTokens();
        for (uint256 i; i < protectedTokens.length; i++) require(_token != protectedTokens[i], "!protected");

        SafeERC20.safeTransfer(IERC20(_token), governance(), IERC20(_token).balanceOf(address(this)));
    }
}

