//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

interface IStrategy {
    // ============================= View functions ================================

    /**
     * @return strategy name
     */
    function name() external view returns (bytes32);

    /**
     * Returns the base erc20 asset for the strategy.
     * Assumption: For now, strategies only accept one base asset at the time (i.e the same strat cannot invest ETH and DPX ony one or the other).
     * @return the address for the asset
     */
    function asset() external view returns (address);

    /**
     * Returns the total deposited assets in the strategy.
     * @return the total amount of deposited assets.
     */
    function totalDeposited() external view returns (uint256);

    /**
     * Returns the current unused assets in the strategy.
     * @return unused amount of assets
     */
    function getUnused() external view returns (uint256);

    /**
     * Returns the vault attached to strategy.
     * Should revert with error if vault is not attached.
     */
    function getVault() external view returns (address);

    // ============================= Mutative functions ================================

    /**
     * Borrow base assets from the vault.
     * This will borrow the required `_amount` in base assets from the vault.
     * @dev SHOULD only be called by the strategists
     * @dev SHOULD call a very specific method on the vault and not do "transferTo"
     * @dev SHOULD emit event Borrow(vault, asset, amount)
     * @param _amount the amount of assets to borrow
     */
    function borrow(uint256 _amount) external;

    /**
     * Returns the funds back to the vault.
     * @dev SHOULD only be called by the strategists
     * @dev SHOULD call a very specific method on the vault "depositProfits"
     * @dev SHOULD emit event Repay(vault, asset, amount)
     */
    function repay() external;

    /**
     * Migrates funds to specified address `_to`.
     * @dev SHOULD only be called by the GOVERNOR.
     *
     * Emits {FundsMigrated}
     */
    function migrateFunds(
        address _to,
        address[] memory _tokens,
        bool _shouldTransferEth,
        bool _shouldTransferERC721
    ) external;

    /**
     * Detaches the strategy.
     * For some reason we might want to detach the strat from the vault,
     * this function should close all open positions, repay the vault and remove itself from the vault whitelist.
     *
     * Reverts if pending settlements or unable to withdraw every deposit after calling `repay`.
     * This is to ensure that the Strategy only detaches if everything is settled and
     * deposited assets are repaid to vault.
     *
     * Make sure to invoke `removeStrategyFromWhitelist` on previously detached vault after detaching.
     *
     * @dev SHOULD only be called by the `GOVERNOR`. Governor should also have `KEEPER` role in order to detach successfully.
     * @dev This function should raise an error in the case it can't withdrawal all the funds invested from the used contracts
     */
    function detach() external;

    /**
     * @dev Attaches `_vault` to this strategy.
     *
     * Only a strategist can attach vault and can only happen once.
     * This method is used over the constructor to prevent circular dependency.
     * Should revert with error if vault is already attached.
     *
     * Invoke `whitelistStrategy` on vault after calling this to whitelist this
     * strategy for the vault to be able to pull assets and perform other restricted actions.
     *
     * Emits {VaultSet}.
     */
    function setVault(address _vault) external;

    // ============================= Events ================================
    /**
     * Emitted when borrowing assets from the underlying vault.
     */
    event Borrow(
        address indexed strategist,
        uint256 amount,
        address indexed vault,
        address indexed asset
    );

    /**
     * Emitted when closing the strategy.
     */
    event Repay(
        address indexed strategist,
        uint256 amount,
        address indexed vault,
        address indexed asset
    );

    /**
     * Emitted when attaching the vault.
     */
    event VaultSet(address indexed governor, address indexed vault);

    /**
     * Emitted when migrating funds (ex in case of an emergency).
     */
    event FundsMigrated(address indexed governor);

    /**
     * Emitted when detaching the vault.
     */
    event VaultDetached(address indexed governor, address indexed vault);

    // ============================= Errors ================================
    error ADDRESS_CANNOT_BE_ZERO_ADDRESS();
    error VAULT_NOT_ATTACHED();
    error VAULT_ALREADY_ATTACHED();
    error MANAGEMENT_WINDOW_NOT_OPEN();
    error NOT_ENOUGH_AVAILABLE_ASSETS();
    error STRATEGY_STILL_HAS_ASSET_BALANCE();
    error BORROW_AMOUNT_ZERO();
    error MSG_SENDER_DOES_NOT_HAVE_PERMISSION_TO_EMERGENCY_WITHDRAW();
}

