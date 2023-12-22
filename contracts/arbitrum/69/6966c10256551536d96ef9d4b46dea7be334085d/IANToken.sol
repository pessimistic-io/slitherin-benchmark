// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./IERC20Metadata.sol";

interface IANToken is IERC20Metadata {
    error MaximumSupplyNotMinted();
    error EmptySetOfLiquidityPools();
    error EmptySetOfWhitelistedAccounts();
    error TradingAlreadyEnabled();
    error ZeroAddressEntry();
    error ForbiddenToMintTokens();
    error MaximumSupplyExceeded();
    error ForbiddenToBurnTokens();
    error MaximumBurnPercentageExceeded();
    error AlreadyInLiquidityPoolsSet(address account);
    error NotFoundInLiquidityPoolsSet(address account);
    error AlreadyInWhitelistedAccountsSet(address account);
    error NotFoundInWhitelistedAccountsSet(address account);
    error AlreadyInBlocklistedAccountsSet(address account);
    error NotFoundInBlocklistedAccountsSet(address account);
    error AlreadyInCommissionExemptAccountsSet(address account);
    error NotFoundInCommissionExemptAccountsSet(address account);
    error AlreadyInSourceAddressesSet(address sourceAddress);
    error NotFoundInSourceAddressesSet(address sourceAddress);
    error InvalidGasLimit();
    error ForbiddenToUpdatePurchaseProtectionPeriod();
    error ForbiddenToUpdateSaleProtectionPeriod();
    error InvalidCommissionRecipient();
    error ForbiddenToUpdateMaximumPurchaseAmountDuringProtectionPeriod();
    error MaximumPercentageOfSalesCommissionExceeded();
    error InvalidMsgValue();
    error InvalidCallee();
    error NotUniqueHash();
    error InvalidSourceAddress();
    error AlreadyInBurnProtectedAccountsSet();
    error NotFoundInBurnProtectedAccountsSet();
    error Blocklisted();
    error ForbiddenToTransferTokens(address from, address to, uint256 amount);
    error ForbiddenToSaleTokens();

    event TradingEnabled(uint256 indexed tradingEnabledTimestamp);
    event AccumulatedCommissionWithdrawn(uint256 indexed commissionAmount);
    event BlocklistedAccountNullified(address indexed account, uint256 indexed amount);
    event LiquidityPoolsAdded(address[] indexed liquidityPools);
    event LiquidityPoolsRemoved(address[] indexed liquidityPools);
    event WhitelistedAccountsAdded(address[] indexed accounts);
    event WhitelistedAccountsRemoved(address[] indexed accounts);
    event BlocklistedAccountsAdded(address[] indexed accounts);
    event BlocklistedAccountsRemoved(address[] indexed accounts);
    event CommissionExemptAccountsAdded(address[] indexed accounts);
    event CommissionExemptAccountsRemoved(address[] indexed accounts);
    event SourceAddressesAdded(address[] indexed sourceAddresses);
    event SourceAddressesRemoved(address[] indexed sourceAddresses);
    event GasLimitUpdated(uint256 indexed newGasLimit);
    event PurchaseProtectionPeriodUpdated(uint256 indexed newPurchaseProtectionPeriod);
    event SaleProtectionPeriodUpdated(uint256 indexed newSaleProtectionPeriod);
    event CommissionRecipientUpdated(address indexed newCommissionRecipient);
    event MaximumPurchaseAmountDuringProtectionPeriodUpdated(uint256 indexed newMaximumPurchaseAmountDuringProtectionPeriod);
    event PercentageOfSalesCommissionUpdated(uint256 indexed newPercentageOfSalesCommission);
    event TokensReceived(address indexed from, address indexed to, uint256 indexed amount, uint16 sourceChain);
    event BurnProtectedAccountAdded(address indexed account);
    event BurnProtectedAccountRemoved(address indexed account);

    /// @notice Enables trading.
    /// @dev Could be called only by the DEFAULT_ADMIN_ROLE.
    function enableTrading() external;

    /// @notice Transfers the accumulated commission on the contract to the commission recipient.
    /// @dev Could be called only by the DEFAULT_ADMIN_ROLE.
    function withdrawAccumulatedCommission() external;

    /// @notice Nullifies the blocklisted account.
    /// @dev Could be called only by the DEFAULT_ADMIN_ROLE.
    /// @param account_ Account address.
    function nullifyBlocklistedAccount(address account_) external;

    /// @notice Transfers tokens via wormhole relayer.
    /// @param targetChain_ Wormhole representation of target chain id.
    /// @param targetAddress_ ANToken contract address on target chain.
    /// @param to_ Token receiver on target chain.
    /// @param amount_ Amount of tokens to transfer.
    function transferMultichain(
        uint16 targetChain_, 
        address targetAddress_, 
        address to_, 
        uint256 amount_
    ) 
        external 
        payable
        returns (bool);

    /// @notice Transfers tokens via wormhole relayer.
    /// @param targetChain_ Wormhole representation of target chain id.
    /// @param targetAddress_ ANToken contract address on target chain.
    /// @param from_ Token sender on source chain.
    /// @param to_ Token receiver on target chain.
    /// @param amount_ Amount of tokens to transfer.
    function transferFromMultichain(
        uint16 targetChain_, 
        address targetAddress_, 
        address from_,
        address to_, 
        uint256 amount_
    ) 
        external 
        payable
        returns (bool);

    /// @notice Creates `amount_` tokens and assigns them to `account_`, increasing the total supply.
    /// @dev Could be called only by the DEFAULT_ADMIN_ROLE.
    /// @param account_ Token receiver.
    /// @param amount_ Amount ot tokens to mint.
    function mint(address account_, uint256 amount_) external;

    /// @notice Destroys `percentage_` of total supply.
    /// @dev Could be called only by the DEFAULT_ADMIN_ROLE.
    /// @param percentage_ Percentage of total supply to destroy.
    function burn(uint256 percentage_) external;

    /// @notice Adds `accounts_` to the liquidity pools set.
    /// @dev Could be called only by the DEFAULT_ADMIN_ROLE.
    /// @param accounts_ Account addresses.
    function addLiquidityPools(address[] calldata accounts_) external;

    /// @notice Removes `accounts_` from the liquidity pools set.
    /// @dev Could be called only by the DEFAULT_ADMIN_ROLE.
    /// @param accounts_ Account addresses.
    function removeLiquidityPools(address[] calldata accounts_) external;

    /// @notice Adds `accounts_` to the whitelisted accounts set.
    /// @dev Could be called only by the DEFAULT_ADMIN_ROLE.
    /// @param accounts_ Account addresses.
    function addWhitelistedAccounts(address[] calldata accounts_) external;

    /// @notice Removes `accounts_` from the whitelisted accounts set.
    /// @dev Could be called only by the DEFAULT_ADMIN_ROLE.
    /// @param accounts_ Account addresses.
    function removeWhitelistedAccounts(address[] calldata accounts_) external;

    /// @notice Adds `accounts_` to the blocklisted accounts set.
    /// @dev Could be called only by the DEFAULT_ADMIN_ROLE.
    /// @param accounts_ Account addresses.
    function addBlocklistedAccounts(address[] calldata accounts_) external;

    /// @notice Removes `accounts_` from the blocklisted accounts set.
    /// @dev Could be called only by the DEFAULT_ADMIN_ROLE.
    /// @param accounts_ Account addresses.
    function removeBlocklistedAccounts(address[] calldata accounts_) external;

    /// @notice Adds `accounts_` to the commission exempt accounts set.
    /// @dev Could be called only by the DEFAULT_ADMIN_ROLE.
    /// @param accounts_ Account addresses.
    function addCommissionExemptAccounts(address[] calldata accounts_) external;

    /// @notice Removes `accounts_` from the commission exempt accounts set.
    /// @dev Could be called only by the DEFAULT_ADMIN_ROLE.
    /// @param accounts_ Account addresses.
    function removeCommissionExemptAccounts(address[] calldata accounts_) external;

    /// @notice Adds `sourceAddresses_` to the source addresses set.
    /// @dev Could be called only by the DEFAULT_ADMIN_ROLE.
    /// @param sourceAddresses_ Source chain contract addresses.
    function addSourceAddresses(address[] calldata sourceAddresses_) external;

    /// @notice Removes `sourceAddresses_` from the source addresses set.
    /// @dev Could be called only by the DEFAULT_ADMIN_ROLE.
    /// @param sourceAddresses_ Source chain contract addresses.
    function removeSourceAddresses(address[] calldata sourceAddresses_) external;

    /// @notice Updates the gas limit on multichain transfers.
    /// @dev Could be called only by the DEFAULT_ADMIN_ROLE.
    /// @param gasLimit_ New gas limit value.
    function updateGasLimit(uint256 gasLimit_) external;

    /// @notice Updates the purchase protection period.
    /// @dev Could be called only by the DEFAULT_ADMIN_ROLE.
    /// @param purchaseProtectionPeriod_ New purchase protection period value in seconds.
    function updatePurchaseProtectionPeriod(uint256 purchaseProtectionPeriod_) external;

    /// @notice Updates the sale protection period.
    /// @dev Could be called only by the DEFAULT_ADMIN_ROLE.
    /// @param saleProtectionPeriod_ New sale protection period value in seconds.
    function updateSaleProtectionPeriod(uint256 saleProtectionPeriod_) external;

    /// @notice Updates the commission recipient.
    /// @dev Could be called only by the DEFAULT_ADMIN_ROLE.
    /// @param commissionRecipient_ New commission recipient address.
    function updateCommissionRecipient(address commissionRecipient_) external;

    /// @notice Updates the maximum purchase amount during protection period.
    /// @dev Could be called only by the DEFAULT_ADMIN_ROLE.
    /// @param maximumPurchaseAmountDuringProtectionPeriod_ New maximum purchase amount during protection period value.
    function updateMaximumPurchaseAmountDuringProtectionPeriod(
        uint256 maximumPurchaseAmountDuringProtectionPeriod_
    ) 
        external;

    /// @notice Updates the percentage of sales commission.
    /// @dev Could be called only by the DEFAULT_ADMIN_ROLE.
    /// @param percentageOfSalesCommission_ New percentage of sales commission value.
    function updatePercentageOfSalesCommission(uint256 percentageOfSalesCommission_) external;

    /// @notice Adds `account_` to the burn-protected accounts set.
    /// @dev Could be called only by the DEFAULT_ADMIN_ROLE.
    /// @param account_ Account address.
    function addBurnProtectedAccount(address account_) external;

    /// @notice Removes `account_` from the burn-protected accounts set.
    /// @dev Could be called only by the DEFAULT_ADMIN_ROLE.
    /// @param account_ Account address.
    function removeBurnProtectedAccount(address account_) external;

    /// @notice Checks if `account_` is in the liquidity pools set.
    /// @param account_ Account address.
    /// @return Boolean value indicating whether the `account_` is in the liquidity pools set.
    function isLiquidityPool(address account_) external view returns (bool);

    /// @notice Checks if `account_` is in the whitelisted accounts set.
    /// @param account_ Account address.
    /// @return Boolean value indicating whether `account_` is in the whitelisted accounts set.
    function isWhitelistedAccount(address account_) external view returns (bool);

    /// @notice Checks if `account_` is in the blocklisted accounts set.
    /// @param account_ Account address.
    /// @return Boolean value indicating whether `account_` is in the blocklisted accounts set.
    function isBlocklistedAccount(address account_) external view returns (bool);

    /// @notice Checks if `account_` is in the commission exempt accounts set.
    /// @param account_ Account address.
    /// @return Boolean value indicating whether `account_` is in the commission exempt accounts set.
    function isCommissionExemptAccount(address account_) external view returns (bool);

    /// @notice Checks if `account_` is in the burn-protected accounts set.
    /// @param account_ Account address.
    /// @return Boolean value indicating whether `account_` is in the burn-protected accounts set.
    function isBurnProtectedAccount(address account_) external view returns (bool);

    /// @notice Retrieves the price for transaction via wormhole relayer.
    /// @param targetChain_ Wormhole representation of target chain id.
    function quoteEVMDeliveryPrice(uint16 targetChain_) external view returns (uint256 cost_);
}
