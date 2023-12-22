// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./ERC20.sol";
import "./SafeERC20.sol";
import "./Initializable.sol";
import "./OwnableUpgradeable.sol";
import "./IBorrower.sol";
import "./IAddressProvider.sol";
import "./IController.sol";
import "./IWETH.sol";
import "./AccessControl.sol";

/**
 * @title Controller
 * @notice This is the controller contract that binds the vault-strategy mix
 * @dev It contains logic to control flow of funds and actions triggered from the vault to the strategy
 * @dev The Controller acrchitecture is used in order to decouple the vault from the strategy.
 */
contract Controller is AccessControl, IController {
    using SafeERC20 for IERC20;

    ///@notice Mapping from strategies to vaults
    mapping(address => address) public vaults;

    /**
     * @notice Initialize contract
    */
    function initialize(address _provider) public initializer {
        __AccessControl_init(_provider);
    }

    // ===== Modifiers =====
    /**
     * @notice Restrict access to only a vault's strategy or governance or keeper
     * @param _strategy Strategy to check for approval
     */
    function _onlyApprovedForWant(address _strategy) internal view {
        require(
            msg.sender == vaults[_strategy] ||
                msg.sender == provider.keeper() ||
                msg.sender == provider.governance(),
            "Unauthorized"
        );
    }

    // ===== Permissioned Actions: Governance =====

    /**
     * @notice Set the Vault (aka Sett) for a given strategy
     * @param _strategy Strategy address to set
     * @param _vault Vault Address to set
     */
    function setVault(address _strategy, address _vault) public restrictAccess(GOVERNOR) {
        IBorrower(_strategy).getDebts();
        vaults[_strategy] = _vault;
    }

    /**
     * @notice Withdraw all the funds of a strategy to its vault.
     * @dev Permissioned Function
     */
    function withdrawAll(address _strategy) public {
        _onlyApprovedForWant(_strategy);
        IBorrower(_strategy).withdrawAll();
    }

    /**
     * @notice Transfer an amount of the specified token from the controller to the sender.
     * @dev Token balance are never meant to exist in the controller, this is purely a safeguard.
     * @param _token LP Token to transfer when stuck
     * @param _amount amount to transfer
     */
    function inCaseTokensGetStuck(address _token, uint256 _amount) public restrictAccess(GOVERNOR) {
        require(_amount>0, "E21");
        IERC20(_token).safeTransfer(msg.sender, _amount);
    }

    /**
     * @notice Transfer an amount of the specified token from the strategy to the controller.
     * @dev Token balance are never meant to exist in the controller, this is purely a safeguard.
     * @param _strategy Strategy to withdraw from
     * @param _token amount to transfer
     */
    function inCaseStrategyTokenGetStuck(
        address _strategy,
        address _token
    ) public restrictAccess(GOVERNOR) {
        IBorrower(_strategy).withdrawOther(_token);
    }

    /**
     * @notice Withdraw an amount from the strategy and send it to the vault
     * @dev It is an emergency function
     * @param _strategy Strategy to withdraw from
     * @param _amount Amount to withdraw
     */
    function forceWithdraw(address _strategy, uint256 _amount) public restrictAccess(GOVERNOR) {
        IBorrower(_strategy).withdraw(_amount);
    }

    // ==== Permissioned Actions: Only Approved Actors =====

    /**
     * @notice Calls the harvesting function of a strategy to harvest fees
     * @dev Only the associated vault, or permissioned actors can call this function (keeper or governance)
     */
    function harvest(address _strategy) public {
        _onlyApprovedForWant(_strategy);
        IBorrower(_strategy).harvest();
    }

    /**
     * @notice Calls the deposit function of a strategy to deposit its funds in the strategy to generate yield.
     * @dev Only the associated vault, or permissioned actors can call this function (keeper or governance)
     * @dev Permissioned Function
     */
    function earn(address _strategy) public {
        _onlyApprovedForWant(_strategy);
        IBorrower(_strategy).deposit();
    }

    /**
     * @notice Used to copy old contract state to the new one in case strategy contract is replaced
     */
    function resetStrategyPnl(address _strategy) external {
        _onlyApprovedForWant(_strategy);
        IBorrower(_strategy).resetPnlData();
    }

    /**
     * @notice Used to copy old contract state to the new one in case strategy contract is replaced
     */
    function migrateStrategy(address _oldAddress, address _newAddress) external {
        _onlyApprovedForWant(_newAddress);
        IBorrower(_newAddress).migrate(_oldAddress);
    }

    // ===== Permissioned Actions: Only Associated Vault =====

    /**
     * @notice Withdraw an amount from the strategy and send it to the vault
     * @dev Only the associated vault can call this function in response to a user withdrawal request
     * @param _strategy LP Token that is associated with strategy
     * @param _amount Amount to withdraw
     */
    function withdraw(address _strategy, uint256 _amount) public {
        require(msg.sender == vaults[_strategy], "E23");
        IBorrower(_strategy).withdraw(_amount);
    }

    receive() external payable {
        IWETH(payable(provider.networkToken())).deposit{value: address(this).balance}();
    }
}

