/*
Licensed under the Voltz v2 License (the "License"); you 
may not use this file except in compliance with the License.
You may obtain a copy of the License at

https://github.com/Voltz-Protocol/v2-core/blob/main/core/LICENSE
*/
pragma solidity >=0.8.19;

import "./MarketRiskConfiguration.sol";
import "./ProtocolRiskConfiguration.sol";
import "./AccountRBAC.sol";
import "./SafeCast.sol";
import "./SetUtil.sol";
import "./Collateral.sol";
import "./Product.sol";

import "./sd59x18_Math.sol";
import "./SignedMath.sol";

import {mulUDxUint, mulSDxInt} from "./PrbMathHelper.sol";

/**
 * @title Object for tracking accounts with access control and collateral tracking.
 */
library Account {
    using MarketRiskConfiguration for MarketRiskConfiguration.Data;
    using ProtocolRiskConfiguration for ProtocolRiskConfiguration.Data;
    using Account for Account.Data;
    using AccountRBAC for AccountRBAC.Data;
    using Product for Product.Data;
    using SetUtil for SetUtil.UintSet;
    using SafeCastU128 for uint128;
    using SafeCastU256 for uint256;
    using SafeCastI256 for int256;

    /**
     * @dev Thrown when the given target address does not own the given account.
     */
    error PermissionDenied(uint128 accountId, address target);

    /**
     * @dev Thrown when a given account's total value is below the initial margin requirement
     */
    error AccountBelowIM(uint128 accountId);

    /**
     * @dev Thrown when an account cannot be found.
     */
    error AccountNotFound(uint128 accountId);

    struct Data {
        /**
         * @dev Numeric identifier for the account. Must be unique.
         * @dev There cannot be an account with id zero (See ERC721._mint()).
         */
        uint128 id;
        /**
         * @dev Role based access control data for the account.
         */
        AccountRBAC.Data rbac;
        /**
         * @dev Address set of collaterals that are being used in the protocols by this account.
         */
        mapping(address => Collateral.Data) collaterals;
        /**
         * @dev Ids of all the products in which the account has active positions
         */
        SetUtil.UintSet activeProducts;
    }

    struct Exposure {
        // productId (IRS) -> marketID (aUSDC lend) -> maturity (30th December)
        // productId (Dated Future) -> marketID (BTC) -> maturity (30th December)
        // productId (Perp) -> marketID (ETH)
        // note, we don't need to keep track of the maturity for the purposes of IM, LM calc
        // because the risk parameter is shared across maturities for a given productId marketId pair
        // uint128 productId; -> since already have it in the exposures mapping
        uint128 marketId;
        int256 filled;
        uint256 unfilledLong;
        uint256 unfilledShort;
    }

    /**
     * @dev Returns the account stored at the specified account id.
     */
    function load(uint128 id) internal pure returns (Data storage account) {
        require(id != 0);
        bytes32 s = keccak256(abi.encode("xyz.voltz.Account", id));
        assembly {
            account.slot := s
        }
    }

    /**
     * @dev Creates an account for the given id, and associates it to the given owner.
     *
     * Note: Will not fail if the account already exists, and if so, will overwrite the existing owner.
     *  Whatever calls this internal function must first check that the account doesn't exist before re-creating it.
     */
    function create(uint128 id, address owner) internal returns (Data storage account) {
        // Disallowing account ID 0 means we can use a non-zero accountId as an existence flag in structs like Position
        require(id != 0);
        account = load(id);

        account.id = id;
        account.rbac.owner = owner;
    }

    /**
     * @dev Closes all account filled (i.e. attempts to fully unwind) and unfilled orders in all the products in which the account
     * is active
     */
    function closeAccount(Data storage self, address collateralType) internal {
        SetUtil.UintSet storage _activeProducts = self.activeProducts;
        for (uint256 i = 1; i <= _activeProducts.length(); i++) {
            uint128 productIndex = _activeProducts.valueAt(i).to128();
            Product.Data storage _product = Product.load(productIndex);
            _product.closeAccount(self.id, collateralType);
        }
    }

    /**
     * @dev Reverts if the account does not exist with appropriate error. Otherwise, returns the account.
     */
    function exists(uint128 id) internal view returns (Data storage account) {
        Data storage a = load(id);
        if (a.rbac.owner == address(0)) {
            revert AccountNotFound(id);
        }

        return a;
    }

    /**
     * @dev Given a collateral type, returns information about the total balance of the account
     */
    function getCollateralBalance(Data storage self, address collateralType)
        internal
        view
        returns (uint256 collateralBalance)
    {
        collateralBalance = self.collaterals[collateralType].balance;
    }

    /**
     * @dev Given a collateral type, returns information about the total balance of the account that's available to withdraw
     */
    function getCollateralBalanceAvailable(Data storage self, address collateralType)
        internal
        returns (uint256 collateralBalanceAvailable)
    {
        (uint256 im,) = self.getMarginRequirements(collateralType);
        int256 totalAccountValue = self.getTotalAccountValue(collateralType);
        if (totalAccountValue > im.toInt()) {
            collateralBalanceAvailable = totalAccountValue.toUint() - im;
        }
    }

    /**
     * @dev Given a collateral type, returns information about the total liquidation booster balance of the account
     */
    function getLiquidationBoosterBalance(Data storage self, address collateralType)
        internal
        view
        returns (uint256 liquidationBoosterBalance)
    {
        liquidationBoosterBalance = self.collaterals[collateralType].liquidationBoosterBalance;
    }

    /**
     * @dev Loads the Account object for the specified accountId,
     * and validates that sender has the specified permission. It also resets
     * the interaction timeout. These are different actions but they are merged
     * in a single function because loading an account and checking for a
     * permission is a very common use case in other parts of the code.
     */
    function loadAccountAndValidateOwnership(uint128 accountId, address senderAddress)
        internal
        view
        returns (Data storage account)
    {
        account = Account.load(accountId);
        if (account.rbac.owner != senderAddress) {
            revert PermissionDenied(accountId, senderAddress);
        }
    }

    /**
     * @dev Loads the Account object for the specified accountId,
     * and validates that sender has the specified permission. It also resets
     * the interaction timeout. These are different actions but they are merged
     * in a single function because loading an account and checking for a
     * permission is a very common use case in other parts of the code.
     */
    function loadAccountAndValidatePermission(uint128 accountId, bytes32 permission, address senderAddress)
        internal
        view
        returns (Data storage account)
    {
        account = Account.load(accountId);
        if (!account.rbac.authorized(permission, senderAddress)) {
            revert PermissionDenied(accountId, senderAddress);
        }
    }

    /**
     * @dev Returns the aggregate annualized exposures of the account in all products in which the account is active (annualized
     * exposures are per product)
     * note, the annualized exposures are expected to be in notional terms and in terms of the settlement token of this account
     * what if we do margin calculations per product for now, that'd help with bringing down the gas costs (since atm we're doing no
     * correlations)
     */
    function getAnnualizedProductExposures(Data storage self, uint128 productId, address collateralType)
        internal
        returns (Exposure[] memory productExposures)
    {
        Product.Data storage _product = Product.load(productId);
        productExposures = _product.getAccountAnnualizedExposures(self.id, collateralType);
    }

    /**
     * @dev Returns the aggregate unrealized pnl of the account in all products in which the account has positions with unrealized
     * pnl
     * note, the unrealized pnl is expected to be in terms of the settlement token of this account
     */
    function getUnrealizedPnL(Data storage self, address collateralType) internal view returns (int256 unrealizedPnL) {
        SetUtil.UintSet storage _activeProducts = self.activeProducts;
        for (uint256 i = 1; i <= _activeProducts.length(); i++) {
            uint128 productIndex = _activeProducts.valueAt(i).to128();
            Product.Data storage _product = Product.load(productIndex);
            unrealizedPnL += _product.getAccountUnrealizedPnL(self.id, collateralType);
        }
    }

    /**
     * @dev Returns the total account value in terms of the quote token of the (single token) account
     */

    function getTotalAccountValue(Data storage self, address collateralType)
        internal
        view
        returns (int256 totalAccountValue)
    {
        int256 unrealizedPnL = self.getUnrealizedPnL(collateralType);
        int256 collateralBalance = self.getCollateralBalance(collateralType).toInt();
        totalAccountValue = unrealizedPnL + collateralBalance;
    }

    function getRiskParameter(uint128 productId, uint128 marketId) internal view returns (SD59x18 riskParameter) {
        return MarketRiskConfiguration.load(productId, marketId).riskParameter;
    }

    /**
     * @dev Note, im multiplier is assumed to be the same across all products, markets and maturities
     */
    function getIMMultiplier() internal view returns (UD60x18 imMultiplier) {
        return ProtocolRiskConfiguration.load().imMultiplier;
    }

    function imCheck(Data storage self, address collateralType) internal returns (uint256) {
        (bool isSatisfied, uint256 im) = self.isIMSatisfied(collateralType);
        if (!isSatisfied) {
            revert AccountBelowIM(self.id);
        }
        return im;
    }

    /**
     * @dev Comes out as true if a given account initial margin requirement is satisfied
     * i.e. account value (collateral + unrealized pnl) >= initial margin requirement
     */
    function isIMSatisfied(Data storage self, address collateralType) internal returns (bool imSatisfied, uint256 im) {
        (im,) = self.getMarginRequirements(collateralType);
        imSatisfied = self.getTotalAccountValue(collateralType) >= im.toInt();
    }

    /**
     * @dev Comes out as true if a given account is liquidatable, i.e. account value (collateral + unrealized pnl) < lm
     */

    function isLiquidatable(Data storage self, address collateralType)
        internal
        returns (bool liquidatable, uint256 im, uint256 lm)
    {
        (im, lm) = self.getMarginRequirements(collateralType);
        liquidatable = self.getTotalAccountValue(collateralType) < lm.toInt();
    }
    /**
     * @dev Returns the initial (im) and liqudiation (lm) margin requirements of the account
     */

    function getMarginRequirements(Data storage self, address collateralType)
        internal
        returns (uint256 im, uint256 lm)
    {
        SetUtil.UintSet storage _activeProducts = self.activeProducts;

        int256 worstCashflowUp;
        int256 worstCashflowDown;
        for (uint256 i = 1; i <= _activeProducts.length(); i++) {
            uint128 productId = _activeProducts.valueAt(i).to128();
            Exposure[] memory annualizedProductMarketExposures =
                self.getAnnualizedProductExposures(productId, collateralType);

            for (uint256 j = 0; j < annualizedProductMarketExposures.length; j++) {
                Exposure memory exposure = annualizedProductMarketExposures[j];
                uint128 marketId = exposure.marketId;
                SD59x18 riskParameter = getRiskParameter(productId, marketId);
                int256 maxLong = exposure.filled + int256(exposure.unfilledLong);
                int256 maxShort = exposure.filled - int256(exposure.unfilledShort);
                // note: this conditional logic is redundunt if no correlations, should just be maxLong
                // hence, why we need to use int256 for risk parameter + minimises need for casting
                int256 worstFilledUp = SD59x18.unwrap(riskParameter) > 0 ? maxLong : maxShort;
                int256 worstFilledDown = SD59x18.unwrap(riskParameter) > 0 ? maxShort : maxLong;

                worstCashflowUp += mulSDxInt(riskParameter, worstFilledUp);
                worstCashflowDown += mulSDxInt(riskParameter, worstFilledDown);
            }
        }

        (uint256 worstCashflowUpAbs, uint256 worstCashflowDownAbs) =
            (SignedMath.abs(worstCashflowUp), SignedMath.abs(worstCashflowDown));

        lm = Math.max(worstCashflowUpAbs, worstCashflowDownAbs);
        im = mulUDxUint(getIMMultiplier(), lm);
    }
}

