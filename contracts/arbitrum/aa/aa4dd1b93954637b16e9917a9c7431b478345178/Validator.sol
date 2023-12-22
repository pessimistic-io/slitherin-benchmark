// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "./SafeMath.sol";
import "./OwnableUpgradeable.sol";

import "./IPriceCalculator.sol";
import "./IValidator.sol";
import "./IGToken.sol";
import "./ICore.sol";
import "./IEcoScore.sol";
import "./IBEP20.sol";
import "./Constant.sol";

contract Validator is IValidator, OwnableUpgradeable {
    using SafeMath for uint256;

    /* ========== CONSTANT VARIABLES ========== */

    IPriceCalculator public oracle;
    IEcoScore public ecoScore;
    uint256 private constant grvPriceCollateralCap = 75e15;

    /* ========== STATE VARIABLES ========== */

    ICore public core;
    address private GRV;

    /* ========== INITIALIZER ========== */

    function initialize(address _grv) external initializer {
        __Ownable_init();
        GRV = _grv;
    }

    /// @notice priceCalculator address 를 설정
    /// @dev ZERO ADDRESS 로 설정할 수 없음
    /// @param _priceCalculator priceCalculator contract address
    function setPriceCalculator(address _priceCalculator) public onlyOwner {
        require(_priceCalculator != address(0), "Validator: invalid priceCalculator address");
        oracle = IPriceCalculator(_priceCalculator);
    }

    function setEcoScore(address _ecoScore) public onlyOwner {
        require(_ecoScore != address(0), "Validator: invalid ecoScore address");
        ecoScore = IEcoScore(_ecoScore);
    }

    /* ========== VIEWS ========== */

    /// @notice View collateral, supply, borrow value in USD of account
    /// @param account account address
    /// @return collateralInUSD Total collateral value in USD
    /// @return supplyInUSD Total supply value in USD
    /// @return borrowInUSD Total borrow value in USD
    function getAccountLiquidity(
        address account
    ) external view override returns (uint256 collateralInUSD, uint256 supplyInUSD, uint256 borrowInUSD) {
        collateralInUSD = 0;
        supplyInUSD = 0;
        borrowInUSD = 0;

        address[] memory assets = core.marketListOf(account);
        uint256[] memory prices = oracle.getUnderlyingPrices(assets);
        for (uint256 i = 0; i < assets.length; i++) {
            require(prices[i] != 0, "Validator: price error");
            uint256 decimals = _getDecimals(assets[i]);
            Constant.AccountSnapshot memory snapshot = IGToken(payable(assets[i])).accountSnapshot(account);

            uint256 priceCollateral;
            if (assets[i] == GRV && prices[i] > grvPriceCollateralCap) {
                priceCollateral = grvPriceCollateralCap;
            } else {
                priceCollateral = prices[i];
            }

            uint256 collateralFactor = core.marketInfoOf(payable(assets[i])).collateralFactor;
            uint256 collateralValuePerShareInUSD = snapshot.exchangeRate.mul(priceCollateral).mul(collateralFactor).div(
                1e36
            );

            collateralInUSD = collateralInUSD.add(
                snapshot.gTokenBalance.mul(10 ** (18 - decimals)).mul(collateralValuePerShareInUSD).div(1e18)
            );
            supplyInUSD = supplyInUSD.add(
                snapshot.gTokenBalance.mul(snapshot.exchangeRate).mul(10 ** (18 - decimals)).mul(prices[i]).div(1e36)
            );
            borrowInUSD = borrowInUSD.add(snapshot.borrowBalance.mul(10 ** (18 - decimals)).mul(prices[i]).div(1e18));
        }
    }

    function getAccountRedeemFeeRate(address account) external view override returns (uint256 redeemFee) {
        Constant.EcoScoreInfo memory scoreInfo = ecoScore.accountEcoScoreInfoOf(account);
        Constant.EcoPolicyInfo memory scorePolicy = ecoScore.ecoPolicyInfoOf(scoreInfo.ecoZone);
        redeemFee = scorePolicy.redeemFee;
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    /// @notice core address 를 설정
    /// @dev ZERO ADDRESS 로 설정할 수 없음
    ///      설정 이후에는 다른 주소로 변경할 수 없음
    /// @param _core core contract address
    function setCore(address _core) external onlyOwner {
        require(_core != address(0), "Validator: invalid core address");
        require(address(core) == address(0), "Validator: core already set");
        core = ICore(_core);
    }

    /* ========== ALLOWED FUNCTIONS ========== */

    /// @notice View if redeem is allowed
    /// @param gToken gToken address
    /// @param redeemer Redeemer account
    /// @param redeemAmount Redeem amount of underlying token
    function redeemAllowed(address gToken, address redeemer, uint256 redeemAmount) external override returns (bool) {
        (, uint256 shortfall) = _getAccountLiquidityInternal(redeemer, gToken, redeemAmount, 0);
        return shortfall == 0;
    }

    /// @notice View if borrow is allowed
    /// @param gToken gToken address
    /// @param borrower Borrower address
    /// @param borrowAmount Borrow amount of underlying token
    function borrowAllowed(address gToken, address borrower, uint256 borrowAmount) external override returns (bool) {
        require(core.checkMembership(borrower, address(gToken)), "Validator: enterMarket required");
        require(oracle.getUnderlyingPrice(address(gToken)) > 0, "Validator: Underlying price error");

        // Borrow cap of 0 corresponds to unlimited borrowing
        uint256 borrowCap = core.marketInfoOf(gToken).borrowCap;
        if (borrowCap != 0) {
            uint256 totalBorrows = IGToken(payable(gToken)).accruedTotalBorrow();
            uint256 nextTotalBorrows = totalBorrows.add(borrowAmount);
            require(nextTotalBorrows < borrowCap, "Validator: market borrow cap reached");
        }

        (, uint256 shortfall) = _getAccountLiquidityInternal(borrower, gToken, 0, borrowAmount);
        return shortfall == 0;
    }

    /// @notice View if liquidate is allowed
    /// @param gToken gToken address
    /// @param borrower Borrower address
    /// @param liquidateAmount Underlying token amount to liquidate
    /// @param closeFactor Close factor
    function liquidateAllowed(
        address gToken,
        address borrower,
        uint256 liquidateAmount,
        uint256 closeFactor
    ) external override returns (bool) {
        // The borrower must have shortfall in order to be liquidate
        (, uint256 shortfall) = _getAccountLiquidityInternal(borrower, address(0), 0, 0);
        require(shortfall != 0, "Validator: Insufficient shortfall");

        // The liquidator may not repay more than what is allowed by the closeFactor
        uint256 borrowBalance = IGToken(payable(gToken)).accruedBorrowBalanceOf(borrower);
        uint256 maxClose = closeFactor.mul(borrowBalance).div(1e18);
        return liquidateAmount <= maxClose;
    }

    function gTokenAmountToSeize(
        address gTokenBorrowed,
        address gTokenCollateral,
        uint256 amount
    ) external override returns (uint256 seizeGAmount, uint256 rebateGAmount, uint256 liquidatorGAmount) {
        require(
            oracle.getUnderlyingPrice(gTokenBorrowed) != 0 && oracle.getUnderlyingPrice(gTokenCollateral) != 0,
            "Validator: price error"
        );

        uint256 exchangeRate = IGToken(payable(gTokenCollateral)).accruedExchangeRate();
        require(exchangeRate != 0, "Validator: exchangeRate of gTokenCollateral is zero");

        uint256 borrowedDecimals = _getDecimals(gTokenBorrowed);
        uint256 collateralDecimals = _getDecimals(gTokenCollateral);

        // seizeGTokenAmountBase18 =  ( repayAmount * (liquidationIncentive * priceBorrowed) / (priceCollateral * exchangeRate) )
        // seizeGTokenAmount = seizeGTokenAmountBase18 / (10 ** (18 - decimals))
        uint256 seizeGTokenAmountBase = amount
            .mul(10 ** (18 - borrowedDecimals))
            .mul(core.liquidationIncentive())
            .mul(oracle.getUnderlyingPrice(gTokenBorrowed))
            .div(oracle.getUnderlyingPrice(gTokenCollateral).mul(exchangeRate));

        seizeGAmount = seizeGTokenAmountBase.div(10 ** (18 - collateralDecimals));
        liquidatorGAmount = seizeGAmount;
        rebateGAmount = 0;
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    function _getAccountLiquidityInternal(
        address account,
        address gToken,
        uint256 redeemAmount,
        uint256 borrowAmount
    ) private returns (uint256 liquidity, uint256 shortfall) {
        uint256 accCollateralValueInUSD;
        uint256 accBorrowValueInUSD;

        address[] memory assets = core.marketListOf(account);
        uint256[] memory prices = oracle.getUnderlyingPrices(assets);
        for (uint256 i = 0; i < assets.length; i++) {
            uint256 decimals = _getDecimals(assets[i]);
            require(prices[i] != 0, "Validator: price error");
            Constant.AccountSnapshot memory snapshot = IGToken(payable(assets[i])).accruedAccountSnapshot(account);

            uint256 collateralValuePerShareInUSD;
            if (assets[i] == GRV && prices[i] > grvPriceCollateralCap) {
                collateralValuePerShareInUSD = snapshot
                    .exchangeRate
                    .mul(grvPriceCollateralCap)
                    .mul(core.marketInfoOf(payable(assets[i])).collateralFactor)
                    .div(1e36);
            } else {
                collateralValuePerShareInUSD = snapshot
                    .exchangeRate
                    .mul(prices[i])
                    .mul(core.marketInfoOf(payable(assets[i])).collateralFactor)
                    .div(1e36);
            }

            accCollateralValueInUSD = accCollateralValueInUSD.add(
                snapshot.gTokenBalance.mul(10 ** (18 - decimals)).mul(collateralValuePerShareInUSD).div(1e18)
            );
            accBorrowValueInUSD = accBorrowValueInUSD.add(
                snapshot.borrowBalance.mul(10 ** (18 - decimals)).mul(prices[i]).div(1e18)
            );

            if (assets[i] == gToken) {
                accBorrowValueInUSD = accBorrowValueInUSD.add(
                    _getAmountForAdditionalBorrowValue(
                        redeemAmount,
                        borrowAmount,
                        collateralValuePerShareInUSD,
                        prices[i],
                        decimals
                    )
                );
            }
        }

        liquidity = accCollateralValueInUSD > accBorrowValueInUSD
            ? accCollateralValueInUSD.sub(accBorrowValueInUSD)
            : 0;
        shortfall = accCollateralValueInUSD > accBorrowValueInUSD
            ? 0
            : accBorrowValueInUSD.sub(accCollateralValueInUSD);
    }

    function _getAmountForAdditionalBorrowValue(
        uint256 redeemAmount,
        uint256 borrowAmount,
        uint256 collateralValuePerShareInUSD,
        uint256 price,
        uint256 decimals
    ) internal pure returns (uint256 additionalBorrowValueInUSD) {
        additionalBorrowValueInUSD = redeemAmount.mul(10 ** (18 - decimals)).mul(collateralValuePerShareInUSD).div(
            1e18
        );
        additionalBorrowValueInUSD = additionalBorrowValueInUSD.add(
            borrowAmount.mul(10 ** (18 - decimals)).mul(price).div(1e18)
        );
    }

    /// @notice View underlying token decimals by gToken address
    /// @param gToken gToken address
    function _getDecimals(address gToken) internal view returns (uint256 decimals) {
        address underlying = IGToken(gToken).underlying();
        if (underlying == address(0)) {
            decimals = 18; // ETH
        } else {
            decimals = IBEP20(underlying).decimals();
        }
    }
}

