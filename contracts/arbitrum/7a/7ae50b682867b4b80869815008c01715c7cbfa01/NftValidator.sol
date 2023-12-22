// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "./SafeMath.sol";
import "./OwnableUpgradeable.sol";
import "./IERC721EnumerableUpgradeable.sol";

import "./Constant.sol";

import "./INftValidator.sol";
import "./INFTOracle.sol";
import "./INftCore.sol";
import "./ILendPoolLoan.sol";
import "./IGNft.sol";

contract NftValidator is INftValidator, OwnableUpgradeable {
    using SafeMath for uint256;

    /* ========== CONSTANT VARIABLES ========== */

    uint256 public constant HEALTH_FACTOR_LIQUIDATION_THRESHOLD = 1e18;

    /* ========== STATE VARIABLES ========== */

    INFTOracle public nftOracle;
    INftCore public nftCore;
    ILendPoolLoan public lendPoolLoan;

    /* ========== INITIALIZER ========== */

    function initialize(address _nftOracle, address _nftCore, address _lendPoolLoan) external initializer {
        __Ownable_init();

        nftOracle = INFTOracle(_nftOracle);
        nftCore = INftCore(_nftCore);
        lendPoolLoan = ILendPoolLoan(_lendPoolLoan);
    }

    /* ========== VIEWS ========== */

    function validateBorrow(
        address user,
        uint256 amount,
        address gNft,
        uint256 loanId
    ) external view override {
        require(gNft != address(0), "NftValidator: invalid gNft address");
        require(amount > 0, "NftValidator: invalid amount");

        Constant.NftMarketInfo memory marketInfo = nftCore.marketInfoOf(gNft);

        uint256 collateralAmount = lendPoolLoan.getNftCollateralAmount(IGNft(gNft).underlying());
        require(marketInfo.supplyCap == 0 || collateralAmount < marketInfo.supplyCap, "NftValidator: supply cap reached");

        if (marketInfo.borrowCap != 0) {
            uint256 marketBorrows = lendPoolLoan.marketBorrowBalance(gNft);
            uint256 nextMarketBorrows = marketBorrows.add(amount);
            require(nextMarketBorrows < marketInfo.borrowCap, "NftValidator: borrow cap reached");
        }

        if (loanId != 0) {
            Constant.LoanData memory loanData = lendPoolLoan.getLoan(loanId);
            require(loanData.state == Constant.LoanState.Active, "NftValidator: invalid loan state");
            require(user == loanData.borrower, "NftValidator: invalid borrower");
        }

        (uint256 userCollateralBalance, uint256 userBorrowBalance, uint256 healthFactor) = _calculateLoanData(
            gNft,
            loanId,
            marketInfo.liquidationThreshold
        );

        require(userCollateralBalance > 0, "NftValidator: collateral balance is zero");
        require(healthFactor > HEALTH_FACTOR_LIQUIDATION_THRESHOLD, "NftValidator: health factor lower than liquidation threshold");

        uint256 amountOfCollateralNeeded = userBorrowBalance.add(amount);
        userCollateralBalance = userCollateralBalance.mul(marketInfo.collateralFactor).div(1e18);

        require(amountOfCollateralNeeded <= userCollateralBalance, "NftValidator: Collateral cannot cover new borrow");
    }

    function validateRepay(
        uint256 loanId,
        uint256 repayAmount,
        uint256 borrowAmount
    ) external view override {
        require(repayAmount > 0, "NftValidator: invalid repay amount");
        require(borrowAmount > 0, "NftValidator: invalid borrow amount");

        Constant.LoanData memory loanData = lendPoolLoan.getLoan(loanId);
        require(loanData.state == Constant.LoanState.Active, "NftValidator: invalid loan state");
    }

    function validateAuction(
        address gNft,
        uint256 loanId,
        uint256 bidPrice,
        uint256 borrowAmount
    ) external view override {
        Constant.LoanData memory loanData = lendPoolLoan.getLoan(loanId);
        require(loanData.state == Constant.LoanState.Active || loanData.state == Constant.LoanState.Auction,
                "NftValidator: invalid loan state");

        require(bidPrice > 0, "NftValidator: invalid bid price");
        require(borrowAmount > 0, "NftValidator: invalid borrow amount");

        (uint256 thresholdPrice, uint256 liquidatePrice) = _calculateLoanLiquidatePrice(
            gNft,
            borrowAmount
        );

        if (loanData.state == Constant.LoanState.Active) {
            // Loan accumulated debt must exceed threshold (health factor below 1.0)
            require(borrowAmount > thresholdPrice, "NftValidator: borrow not exceed liquidation threshold");

            // bid price must greater than borrow debt
            require(bidPrice >= borrowAmount, "NftValidator: bid price less than borrow debt");

            // bid price must greater than liquidate price
            require(bidPrice >= liquidatePrice, "NftValidator: bid price less than liquidate price");
        } else {
            // bid price must greater than borrow debt
            require(bidPrice >= borrowAmount, "NftValidator: bid price less than borrow debt");

            uint256 auctionEndTimestamp = loanData.bidStartTimestamp.add(lendPoolLoan.auctionDuration());
            require(block.timestamp <= auctionEndTimestamp, "NftValidator: bid auction duration has ended");

            // bid price must greater than highest bid + delta
            uint256 bidDelta = borrowAmount.mul(1e16).div(1e18); // 1%
            require(bidPrice >= loanData.bidPrice.add(bidDelta), "NftValidator: bid price less than highest price");
        }
    }

    function validateRedeem(
        uint256 loanId,
        uint256 repayAmount,
        uint256 bidFine,
        uint256 borrowAmount
    ) external view override returns (uint256) {
        Constant.LoanData memory loanData = lendPoolLoan.getLoan(loanId);
        require(loanData.state == Constant.LoanState.Auction, "NftValidator: invalid loan state");
        require(loanData.bidderAddress != address(0), "NftValidator: invalid bidder address");

        require(repayAmount > 0, "NftValidator: invalid repay amount");

        uint256 redeemEndTimestamp = loanData.bidStartTimestamp.add(lendPoolLoan.auctionDuration());
        require(block.timestamp <= redeemEndTimestamp, "NftValidator: redeem duration has ended");

        uint256 _bidFine = _calculateLoanBidFine(loanData, borrowAmount);
        require(bidFine >= _bidFine, "NftValidator: invalid bid fine");

        uint256 _minRepayAmount = borrowAmount.mul(lendPoolLoan.redeemThreshold()).div(1e18);
        require(repayAmount >= _minRepayAmount, "NftValidator: repay amount less than redeem threshold");

        uint256 _maxRepayAmount = borrowAmount.mul(9e17).div(1e18);
        require(repayAmount <= _maxRepayAmount, "NftValidator: repay amount greater than max repay");

        return _bidFine;
    }

    function validateLiquidate(
        uint256 loanId,
        uint256 borrowAmount,
        uint256 amount
    ) external view override returns (uint256, uint256) {
        Constant.LoanData memory loanData = lendPoolLoan.getLoan(loanId);
        require(loanData.state == Constant.LoanState.Auction, "NftValidator: invalid loan state");
        require(loanData.bidderAddress != address(0), "NftValidator: invalid bidder address");

        uint256 auctionEndTimestamp = loanData.bidStartTimestamp.add(lendPoolLoan.auctionDuration());
        require(block.timestamp > auctionEndTimestamp, "NftValidator: auction duration not end");

        // Last bid price can not cover borrow amount
        uint256 extraDebtAmount = 0;
        if (loanData.bidPrice < borrowAmount) {
            extraDebtAmount = borrowAmount.sub(loanData.bidPrice);
            require(amount >= extraDebtAmount, "NftValidator: amount less than extra debt amount");
        }

        uint256 remainAmount = 0;
        if (loanData.bidPrice > borrowAmount) {
            remainAmount = loanData.bidPrice.sub(borrowAmount);
        }

        return (extraDebtAmount, remainAmount);
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    function _calculateLoanBidFine(
        Constant.LoanData memory loanData,
        uint256 borrowAmount
    ) internal view returns (uint256) {
        if (loanData.bidPrice == 0) {
            return 0;
        }

        uint256 minBidFine = lendPoolLoan.minBidFine();
        uint256 bidFineAmount = borrowAmount.mul(lendPoolLoan.redeemFineRate()).div(1e18);

        if (bidFineAmount < minBidFine) {
            bidFineAmount = minBidFine;
        }

        return bidFineAmount;
    }

    function _calculateLoanData(
        address gNft,
        uint256 loanId,
        uint256 liquidationThreshold
    ) internal view returns (uint256, uint256, uint256) {
        uint256 totalDebtInETH = 0;

        if (loanId != 0) {
            totalDebtInETH = lendPoolLoan.borrowBalanceOf(loanId);
        }

        uint256 totalCollateralInETH = nftOracle.getUnderlyingPrice(gNft);
        uint256 healthFactor = _calculateHealthFactorFromBalances(totalCollateralInETH, totalDebtInETH, liquidationThreshold);

        return (totalCollateralInETH, totalDebtInETH, healthFactor);
    }

    /*
     * 0                   CR                  LH                  100
     * |___________________|___________________|___________________|
     *  <       Borrowing with Interest        <
     * CR: Callteral Ratio;
     * LH: Liquidate Threshold;
     * Liquidate Trigger: Borrowing with Interest > thresholdPrice;
     * Liquidate Price: (100% - BonusRatio) * NFT Price;
     */
    function _calculateLoanLiquidatePrice(
        address gNft,
        uint256 borrowAmount
    ) internal view returns (uint256, uint256) {
        uint256 liquidationThreshold = nftCore.marketInfoOf(gNft).liquidationThreshold;
        uint256 liquidationBonus = nftCore.marketInfoOf(gNft).liquidationBonus;

        uint256 nftPriceInETH = nftOracle.getUnderlyingPrice(gNft);
        uint256 thresholdPrice = nftPriceInETH.mul(liquidationThreshold).div(1e18);

        uint256 bonusAmount = nftPriceInETH.mul(liquidationBonus).div(1e18);
        uint256 liquidatePrice = nftPriceInETH.sub(bonusAmount);

        if (liquidatePrice < borrowAmount) {
            uint256 bidDelta = borrowAmount.mul(1e16).div(1e18); // 1%
            liquidatePrice = borrowAmount.add(bidDelta);
        }

        return (thresholdPrice, liquidatePrice);
    }

    function _calculateHealthFactorFromBalances(
        uint256 totalCollateral,
        uint256 totalDebt,
        uint256 liquidationThreshold
    ) public pure returns (uint256) {
        if (totalDebt == 0) {
            return uint256(-1);
        }
        return (totalCollateral.mul(liquidationThreshold).mul(1e18).div(totalDebt).div(1e18));
    }
}

