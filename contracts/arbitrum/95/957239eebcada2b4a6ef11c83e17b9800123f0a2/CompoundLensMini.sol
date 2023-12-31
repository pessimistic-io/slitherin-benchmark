pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;

import "./CompoundLensMiniInterface.sol";

contract CompoundLensMini is ExponentialNoError, CompoundLensMiniInterface {
    function cTokenMetadata(CToken cToken) public view returns (CTokenMetadata memory) {
        address underlyingAssetAddress;
        uint underlyingDecimals;
        string memory underlyingSymbol;

        if (compareStrings(cToken.symbol(), "bETH")) {
            underlyingAssetAddress = address(0);
            underlyingDecimals = 18;
            underlyingSymbol = "ETH";
        } else {
            CErc20 cErc20 = CErc20(address(cToken));
            underlyingAssetAddress = cErc20.underlying();
            underlyingDecimals = EIP20Interface(cErc20.underlying()).decimals();
            underlyingSymbol = EIP20Interface(cErc20.underlying()).symbol();
        }

        return CTokenMetadata({
            ctoken: address(cToken),
            underlying: underlyingAssetAddress,
            comptroller: address(cToken.comptroller()),
            ctokenDecimals: cToken.decimals(),
            underlyingDecimals: underlyingDecimals,
            ctokenSymbol: cToken.symbol(),
            underlyingSymbol: underlyingSymbol
        });
    }

    function cTokenMetadataAll(CToken[] calldata cTokens) external view returns (CTokenMetadata[] memory) {
        uint cTokenCount = cTokens.length;
        CTokenMetadata[] memory res = new CTokenMetadata[](cTokenCount);
        for (uint i = 0; i < cTokenCount; i++) {
            res[i] = cTokenMetadata(cTokens[i]);
        }
        return res;
    }

    function compareStrings(string memory a, string memory b) internal pure returns (bool) {
        return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
    }

    function isLiquidationAllowed(
        address[] memory pricesCTokens,
        uint[] memory prices,

        CToken[] memory distinctMarkets,
        Account[] memory accounts,
        uint maxLiquidateable
    ) public returns (uint resultCount, Liquidateable[] memory result) {
        resultCount = 0;
        result = new Liquidateable[](maxLiquidateable);

        for (uint i=0; i < distinctMarkets.length; i++) {
            distinctMarkets[i].accrueInterest();
        }

        for (uint i=0; i < accounts.length; i++) {
            if (accounts[i].markets.length == 0) {
                continue;
            }

            Account memory account = accounts[i];
            ComptrollerInterfaceFull comptroller = ComptrollerInterfaceFull(address(account.markets[0].comptroller()));
            for (uint j=0; j < account.markets.length; j++) {
                for (uint k=0; k < account.markets.length; k++) {
                    if (liquidateBorrowAllowed(comptroller, pricesCTokens, prices,  address(account.markets[j]), address(account.markets[k]), account.account, 1) == 0) {
                        result[resultCount++] = Liquidateable(
                            account.account,
                            comptroller,
                            //
                            account.markets[j],
                            cTokenMetadata(account.markets[j]),
                            account.markets[j].borrowBalanceStored(account.account),
                            //
                            account.markets[k],
                            cTokenMetadata(account.markets[k])
                        );
                    }
                }
            }
        }
    }

    function isLiquidationAllowedForAmount(
        address[] memory pricesCTokens,
        uint[] memory prices,

        address account,
        CToken borrowed, CToken collateral, uint amount
    ) public returns (bool) {
        borrowed.accrueInterest();
        collateral.accrueInterest();

        return liquidateBorrowAllowed(
            ComptrollerInterfaceFull(address(borrowed.comptroller())),
            pricesCTokens,
            prices,

            address(borrowed),
            address(collateral),
            account,
            amount
        ) == 0;
    }

    /////////// from compound to set prices

    function liquidateBorrowAllowed(
        ComptrollerInterfaceFull comptroller,
        address[] memory pricesCTokens,
        uint[] memory prices,

        address cTokenBorrowed,
        address cTokenCollateral,
        address borrower,
        uint repayAmount
    ) public view returns (uint) {
        (bool cTokenBorrowedListed,,) = comptroller.markets(cTokenBorrowed);
        (bool cTokenCollateralListed,,) = comptroller.markets(cTokenCollateral);
        if (!cTokenBorrowedListed || !cTokenCollateralListed) {
            return 1;
        }

        // uint borrowBalance = CToken(cTokenBorrowed).borrowBalanceStored(borrower);

        /* allow accounts to be liquidated if the market is deprecated */
        if (comptroller.isDeprecated(CToken(cTokenBorrowed))) {
            require(CToken(cTokenBorrowed).borrowBalanceStored(borrower) >= repayAmount, "Can not repay more than the total borrow");
        } else {
            /* The borrower must have shortfall in order to be liquidatable */
            (uint err, , uint shortfall) = getAccountLiquidityInternal(comptroller, pricesCTokens, prices, borrower);
            if (err != 0) {
                return uint(err);
            }

            if (shortfall == 0) {
                return 2;
            }

            /* The liquidator may not repay more than what is allowed by the closeFactor */
            uint maxClose = mul_ScalarTruncate(Exp({mantissa: comptroller.closeFactorMantissa()}), CToken(cTokenBorrowed).borrowBalanceStored(borrower));
            if (repayAmount > maxClose) {
                return 3;
            }
        }
        return 0;
    }

    function getAccountLiquidityInternal(
        ComptrollerInterfaceFull comptroller,
        address[] memory pricesCTokens,
        uint[] memory prices,

        address account
    ) internal view returns (uint, uint, uint) {
        return getHypotheticalAccountLiquidityInternal(comptroller, pricesCTokens, prices, account);
    }


    struct AccountLiquidityLocalVars {
        uint sumCollateral;
        uint sumBorrowPlusEffects;
        uint cTokenBalance;
        uint borrowBalance;
        uint exchangeRateMantissa;
        uint oraclePriceMantissa;
        Exp collateralFactor;
        Exp exchangeRate;
        Exp oraclePrice;
        Exp tokensToDenom;
    }

    function getHypotheticalAccountLiquidityInternal(
        ComptrollerInterfaceFull comptroller,
        address[] memory pricesCTokens,
        uint[] memory prices,

        address account
//        CToken cTokenModify,
//        uint redeemTokens,
//        uint borrowAmount
    ) internal view returns (uint, uint, uint) {

        AccountLiquidityLocalVars memory vars; // Holds all our calculation results
        uint oErr;

        // For each asset the account is in
        CToken[] memory assets = comptroller.getAssetsIn(account);
        for (uint i = 0; i < assets.length; i++) {
            CToken asset = assets[i];

            // Read the balances and exchange rate from the cToken
            (oErr, vars.cTokenBalance, vars.borrowBalance, vars.exchangeRateMantissa) = asset.getAccountSnapshot(account);
            if (oErr != 0) { // semi-opaque error code, we assume NO_ERROR == 0 is invariant between upgrades
                return (10, 0, 0);
            }
            (,uint collateralFactorMantissa,) = comptroller.markets(address(asset));
            vars.collateralFactor = Exp({mantissa: collateralFactorMantissa});
            vars.exchangeRate = Exp({mantissa: vars.exchangeRateMantissa});

            // Get the normalized price of the asset
            uint mainOraclePrice = comptroller.oracle().getUnderlyingPrice(asset);
            vars.oraclePriceMantissa = mainOraclePrice > 0 ? mainOraclePrice : getUnderlyingPrice(pricesCTokens, prices, asset);
            if (vars.oraclePriceMantissa == 0) {
                return (11, 0, 0);
            }
            vars.oraclePrice = Exp({mantissa: vars.oraclePriceMantissa});

            // Pre-compute a conversion factor from tokens -> ether (normalized price value)
            vars.tokensToDenom = mul_(mul_(vars.collateralFactor, vars.exchangeRate), vars.oraclePrice);

            // sumCollateral += tokensToDenom * cTokenBalance
            vars.sumCollateral = mul_ScalarTruncateAddUInt(vars.tokensToDenom, vars.cTokenBalance, vars.sumCollateral);

            // sumBorrowPlusEffects += oraclePrice * borrowBalance
            vars.sumBorrowPlusEffects = mul_ScalarTruncateAddUInt(vars.oraclePrice, vars.borrowBalance, vars.sumBorrowPlusEffects);

//            // Calculate effects of interacting with cTokenModify
//            if (asset == cTokenModify) {
//                // redeem effect
//                // sumBorrowPlusEffects += tokensToDenom * redeemTokens
//                vars.sumBorrowPlusEffects = mul_ScalarTruncateAddUInt(vars.tokensToDenom, redeemTokens, vars.sumBorrowPlusEffects);
//
//                // borrow effect
//                // sumBorrowPlusEffects += oraclePrice * borrowAmount
//                vars.sumBorrowPlusEffects = mul_ScalarTruncateAddUInt(vars.oraclePrice, borrowAmount, vars.sumBorrowPlusEffects);
//            }
        }

        // These are safe, as the underflow condition is checked first
        if (vars.sumCollateral > vars.sumBorrowPlusEffects) {
            return (0, vars.sumCollateral - vars.sumBorrowPlusEffects, 0);
        } else {
            return (0, 0, vars.sumBorrowPlusEffects - vars.sumCollateral);
        }
    }

    function getUnderlyingPrice(
        address[] memory pricesCTokens,
        uint[] memory prices,
        CToken cToken
    ) public pure returns (uint) {
        for (uint i=0; i<pricesCTokens.length; i++) {
            if (pricesCTokens[i] == address(cToken)) {
                return prices[i];
            }
        }

        return 0;
    }
}

