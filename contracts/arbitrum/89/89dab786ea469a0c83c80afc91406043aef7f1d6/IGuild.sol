// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {IGuildAddressesProvider} from "./IGuildAddressesProvider.sol";
import {IAssetToken} from "./IAssetToken.sol";
import {ILiabilityToken} from "./ILiabilityToken.sol";
import {IGuildAddressesProvider} from "./IGuildAddressesProvider.sol";
import {DataTypes} from "./DataTypes.sol";
import {IERC20} from "./IERC20.sol";

/**
 * @title IGuild
 * @author Amorphous
 * @notice Defines the basic interface for a Guild.
 **/
interface IGuild {
    /**
     * @dev Emitted on deposit()
     * @param collateral The address of the collateral asset
     * @param user The address initiating the deposit
     * @param onBehalfOf The beneficiary of the deposit
     * @param amount The amount supplied
     **/
    event Deposit(address indexed collateral, address user, address indexed onBehalfOf, uint256 amount);

    /**
     * @dev Emitted on withdraw()
     * @param collateral The address of the collateral asset
     * @param user The address initiating the withdrawal
     * @param to The address that will receive the underlying
     * @param amount The amount to be withdrawn
     **/
    event Withdraw(address indexed collateral, address indexed user, address indexed to, uint256 amount);

    /**
     * @notice Returns the GuildAddressesProvider connected to this contract
     * @return The address of the GuildAddressesProvider
     **/
    function ADDRESSES_PROVIDER() external view returns (IGuildAddressesProvider);

    /**
     * @notice Refinances perpetual debt.
     * @dev Makes uniswap DEX call, and calculates TWAP price vs last time refinance was called.
     * Uses TWAP price to calculate interest rate in that period.
     **/
    function refinance() external;

    /**
     * @notice Supplies an `amount` of collateral into the Guild.
     * @param asset The address of the ERC20 asset to supply
     * @param amount The amount to be supplied
     * @param onBehalfOf The address that receives the collateral 'credit', same as msg.sender if the user
     *   wants it to account to their own wallet, or a different address if the beneficiary is someone else
     **/
    function deposit(
        address asset,
        uint256 amount,
        address onBehalfOf
    ) external;

    /**
     * @notice Withdraw an `amount` of underlying asset from the Guild.
     * @param asset The addres of the ERC20 asset to withdraw
     * @param amount The amount to be withdraw (in WADs if that's the collateral's precision)
     * @param to The address that will receive the underlying, same as msg.sender if the user
     *   wants to receive it on his own wallet, or a different address if the beneficiary is a
     *   different wallet
     * @return The final amount withdrawn
     **/
    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external returns (uint256);

    /**
     * @notice Initializes a perpetual debt.
     * @param assetTokenProxyAddress The proxy address of the underlying asset token contract (zToken)
     * @param liabilityTokenProxyAddress The proxy address of the underlying liability token contract (dToken)
     * @param moneyAddress The address of the money token on which the debt is denominated in
     * @param duration The duration, in seconds, of the perpetual debt
     * @param notionalPriceLimitMax Maximum price used for refinance purposes
     * @param notionalPriceLimitMin Minimum price used for refinance purposes
     * @param dexFactory Uniswap v3 Factory address
     * @param dexFee Uniswap v3 pool fee (to identify pool used for refinance oracle purposes)
     **/
    function initPerpetualDebt(
        address assetTokenProxyAddress,
        address liabilityTokenProxyAddress,
        address moneyAddress,
        uint256 duration,
        uint256 notionalPriceLimitMax,
        uint256 notionalPriceLimitMin,
        address dexFactory,
        uint24 dexFee
    ) external;

    /**
     * @notice Initializes a collateral, activating it, and configuring it's parameters
     * @dev Only callable by the GuildConfigurator contract
     * @param asset The address of the ERC20 collateral
     **/
    function initCollateral(address asset) external;

    /**
     * @notice Drop a collateral
     * @dev Only callable by the GuildConfigurator contract
     * @param asset The address of the ERC20 to drop as an acceptable collateral
     **/
    function dropCollateral(address asset) external;

    /**
     * @notice Sets the configuration bitmap of the collateral as a whole
     * @dev Only callable by the PoolConfigurator contract
     * @param asset The address of the ERC20 collateral
     * @param configuration The new configuration bitmap
     **/
    function setConfiguration(address asset, DataTypes.CollateralConfigurationMap calldata configuration) external;

    /**
     * @notice Returns the configuration of the collateral
     * @param asset The address of the ERC20 collateral
     * @return The configuration of the collateral
     **/
    function getCollateralConfiguration(address asset)
        external
        view
        returns (DataTypes.CollateralConfigurationMap memory);

    /**
     * @notice Returns the collateral balance of a user in the Guild
     * @param user The address of the user
     * @param asset The address of the collateral asset
     * @return The collateral amount deposited in the Guild
     **/
    function getCollateralBalanceOf(address user, address asset) external view returns (uint256);

    /**
     * @notice Returns the total collateral balance in the Guild
     * @param asset The address of the collateral asset
     * @return The total collateral amount deposited in the Guild
     **/
    function getCollateralTotalBalance(address asset) external view returns (uint256);

    /**
     * @notice Returns the list of all initialized collaterals
     * @dev It does not include dropped collaterals
     * @return The addresses of the initialized collaterals
     **/
    function getCollateralsList() external view returns (address[] memory);

    /**
     * @notice Returns the address of the underlying collateral by collateral id as stored in the DataTypes.CollateralData struct
     * @param id The id of the collateral as stored in the DataTypes.CollateralData struct
     * @return The address of the collateral associated with id
     **/
    function getCollateralAddressById(uint16 id) external view returns (address);

    /**
     * @notice Returns the maximum number of collaterals supported by this Guild
     * @return The maximum number of collaterals supported
     */
    function MAX_NUMBER_COLLATERALS() external view returns (uint16);

    /**
     * @notice Sets the configuration bitmap of the perpetual debt
     * @dev Only callable by the GuildConfigurator contract
     * @param configuration The new configuration bitmap
     **/
    function setPerpDebtConfiguration(DataTypes.PerpDebtConfigurationMap calldata configuration) external;

    /**
     * @notice Returns the configuration of the perpetual debt
     * @return The configuration of the perpetual debt
     **/
    function getPerpDebtConfiguration() external view returns (DataTypes.PerpDebtConfigurationMap memory);

    /**
     * @dev Emitted on borrow() when debt needs to be opened
     * @param user The address of the user initiating the borrow(), receiving the funds on borrow()
     * @param onBehalfOf The address that will be getting the debt
     * @param amount The zToken amount borrowed out
     * @param amountNotional The notional amount borrowed out (in Notional)
     **/
    event Borrow(address indexed user, address indexed onBehalfOf, uint256 amount, uint256 amountNotional);

    /**
     * @dev Emitted on repay()
     * @param user The address of the account whose zTokens are used to pay back the debt
     * @param onBehalfOf The address that will be getting the debt paid back
     * @param amount The zToken amount repaid
     * @param amountNotional The notional amount borrowed out (in Notional)
     **/
    event Repay(address indexed user, address indexed onBehalfOf, uint256 amount, uint256 amountNotional);

    /**
     * @notice Get money token
     **/
    function getMoney() external view returns (IERC20);

    /**
     * @notice Get asset token
     **/
    function getAsset() external view returns (IAssetToken);

    /**
     * @notice get liability token
     **/
    function getLiability() external view returns (ILiabilityToken);

    /**

     * @notice get current spot APY (not historical), given current spot zToken price on external DEX
     **/
    function getAPY() external view returns (uint256);

    /**

     * @notice get perpetual debt notional price
     **/
    function getDebtNotionalPrice(address oracle) external view returns (uint256);

    /**
     * @notice get perpetual debt data
     **/
    function getPerpetualDebt() external view returns (DataTypes.PerpetualDebtData memory);

    /**
     * @notice Updates notional price limits used during refinancing.
     * @dev Perpetual debt interest rates are proportional to 1/notionalPrice.
     * @param priceMin Minimum notional price to use for refinancing.
     * @param priceMax Maximum notional price to use for refinancing.
     **/
    function setPerpDebtNotionalPriceLimits(uint256 priceMax, uint256 priceMin) external;

    /**
     * @notice Allows users to borrow a specific `amount` of the zTokens, provided that the borrower
     * already supplied enough collateral.
     * @param amount The zToken amount to be borrowed
     * @param onBehalfOf The address of the user who will receive the debt. Should be the address of the borrower itself
     * calling the function if he wants to borrow against his own collateral, or the address of the credit delegator
     * if he has been given credit delegation allowance to msg.sender
     **/
    function borrow(uint256 amount, address onBehalfOf) external;

    /**
     * @notice Payback specific borrowed `amount`, which in turn burns the equivalent amount of dTokens
     * @param onBehalfOf The address of the user who will get his debt reduced/removed. Should be the address of the
     * user calling the function if he wants to reduce/remove his own debt, or the address of any other
     * other borrower whose debt should be removed
     * @param amount The zToken amount to be paid back
     * @return The final notional amount repaid
     **/
    function repay(uint256 amount, address onBehalfOf) external returns (uint256);

    /**
     * @notice Return structure for getUserAccountData function
     * @return totalCollateralInBaseCurrency The total collateral of the user in the base currency used by the price feed
     * @return totalDebtNotionalInBaseCurrency The total debt of the user in the base currency used by the price feed
     * @return availableBorrowsInBaseCurrency The borrowing power left of the user in the base currency used by the price feed
     * @return currentLiquidationThreshold The liquidation threshold of the user
     * @return ltv The loan to value of The user
     * @return healthFactor The current health factor of the user
     * @return totalDebtNotional The total debt of the user in the native dToken decimal unit
     * @return availableBorrowsInZTokens The total zTokens that can be minted given borrowing capacity
     * @return availableNotionalBorrows The total notional that can be minted given borrowing capacity
     * @return zTokensToRepayDebt The total zTokens required to repay the accounts totalDebtNotional (in native zToken decimal unit)
     **/
    struct userAccountDataStruc {
        uint256 totalCollateralInBaseCurrency;
        uint256 totalDebtNotionalInBaseCurrency;
        uint256 availableBorrowsInBaseCurrency;
        uint256 currentLiquidationThreshold;
        uint256 ltv;
        uint256 healthFactor;
        uint256 totalDebtNotional;
        uint256 availableBorrowsInZTokens;
        uint256 availableNotionalBorrows;
        uint256 zTokensToRepayDebt;
    }

    /**
     * @notice Returns the user account data across all the collaterals
     * @param user The address of the user
     * @return userData User variables as per userAccountDataStruc structure
     **/
    function getUserAccountData(address user) external view returns (userAccountDataStruc memory userData);

    /**
     * @notice Function to liquidate a non-healthy position collateral-wise, with Health Factor below 1
     * - The caller (liquidator) covers `debtNotionalToCover` amount of debt of the user getting liquidated, and receives
     *   a proportionally amount of the `collateralAsset` plus a bonus to cover market risk
     * @param collateralAsset The address of the collateral asset, to receive as result of the liquidation
     * @param user The address of the borrower getting liquidated
     * @param debtNotionalToCover The debt Notional amount the liquidator wants to cover
     * @param receiveCollateral True if the liquidators wants to take ownership of the collateral asset and transfer it into their Guild account (as collateral deposited)
     *`false` if they want to receive (transfer) the collateral asset directly into their wallet.
     **/
    function liquidationCall(
        address collateralAsset,
        address user,
        uint256 debtNotionalToCover,
        bool receiveCollateral
    ) external;

    /**
     * @notice Executes validation of deposit() function, and reverts with same validation logic
     * @dev does not update on-chain state
     * @param asset The address of the ERC20 asset to supply
     * @param amount The amount to be supplied
     * @param onBehalfOf The address that receives the collateral 'credit', same as msg.sender if the user
     *   wants it to account to their own wallet, or a different address if the beneficiary is someone else
     **/
    function validateDeposit(
        address asset,
        uint256 amount,
        address onBehalfOf
    ) external view;

    /**
     * @notice Executes validation of withdraw() function, and reverts with same validation logic
     * @dev does not update on-chain state
     * @param asset The address of the ERC20 asset to supply
     * @param amount The amount to be supplied
     * @param onBehalfOf The address that receives the collateral 'withdrawal', same as msg.sender if the user
     *   wants it to account to their own wallet, or a different address if the beneficiary is someone else
     **/
    function validateWithdraw(
        address asset,
        uint256 amount,
        address onBehalfOf
    ) external view;

    /**
     * @notice Executes validation of borrow() function, and reverts with same validation logic
     * @param amount The zToken amount to be borrowed
     * @param onBehalfOf The address of the user who will receive the debt. Should be the address of the borrower itself
     * calling the function if he wants to borrow against his own collateral, or the address of the credit delegator
     * if he has been given credit delegation allowance to msg.sender
     **/
    function validateBorrow(uint256 amount, address onBehalfOf) external view;

    /**
     * @notice Executes validation of repay() function, and reverts with same validation logic
     * @param amount The zToken amount  to be paid back
     * @param onBehalfOf The address of the user who will have debt repaid.
     **/
    function validateRepay(uint256 amount, address onBehalfOf) external view;
}

