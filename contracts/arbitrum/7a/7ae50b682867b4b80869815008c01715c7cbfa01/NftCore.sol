// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "./SafeMath.sol";

import "./SafeToken.sol";

import "./NftCoreAdmin.sol";
import "./IGNft.sol";
import "./INftValidator.sol";

contract NftCore is NftCoreAdmin {
    using SafeMath for uint256;
    using SafeToken for address;

    /* ========== INITIALIZER ========== */

    function initialize(
        address _nftOracle,
        address _borrowMarket,
        address _core,
        address _treasury
    ) external initializer {
        __NftCore_init(_nftOracle, _borrowMarket, _core, _treasury);
    }

    /* ========== MODIFIERS ========== */

    modifier onlyMarket() {
        bool fromMarket = false;
        for (uint256 i = 0; i < markets.length; i++) {
            if (msg.sender == markets[i]) {
                fromMarket = true;
                break;
            }
        }
        require(fromMarket == true, "NftCore: caller should be market");
        _;
    }

    modifier onlyEOA() {
        require(msg.sender == tx.origin, "NftCore: not eoa");
        _;
    }

    /* ========== VIEWS ========== */

    function allMarkets() external view override returns (address[] memory) {
        return markets;
    }

    function marketInfoOf(address gNft) external view override returns (Constant.NftMarketInfo memory) {
        return marketInfos[gNft];
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function withdrawBalance() external onlyOwner {
        uint256 _balance = address(this).balance;
        if (_balance > 0) {
            SafeToken.safeTransferETH(treasury, _balance);
        }
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function borrow(
        address gNft,
        uint256 tokenId,
        uint256 amount
    ) external override onlyListedMarket(gNft) nonReentrant whenNotPaused {
        _borrow(gNft, tokenId, amount);
    }

    function batchBorrow(
        address gNft,
        uint256[] calldata tokenIds,
        uint256[] calldata amounts
    ) external override onlyListedMarket(gNft) nonReentrant whenNotPaused {
        require(tokenIds.length == amounts.length, "NftCore: inconsistent amounts length");
        for (uint256 i = 0; i < tokenIds.length; i++) {
            _borrow(gNft, tokenIds[i], amounts[i]);
        }
    }

    function _borrow(address gNft, uint256 tokenId, uint256 amount) private {
        address nftAsset = IGNft(gNft).underlying();
        uint256 loanId = lendPoolLoan.getCollateralLoanId(nftAsset, tokenId);

        validator.validateBorrow(
            msg.sender,
            amount,
            gNft,
            loanId
        );

        if (loanId == 0) {
            IERC721Upgradeable(nftAsset).safeTransferFrom(msg.sender, address(this), tokenId);

            loanId = lendPoolLoan.createLoan(
                msg.sender,
                nftAsset,
                tokenId,
                gNft,
                amount
            );
        } else {
            lendPoolLoan.updateLoan(
                loanId,
                amount,
                0
            );
        }
        core.nftBorrow(borrowMarket, msg.sender, amount);
        SafeToken.safeTransferETH(msg.sender, amount);
        emit Borrow(
            msg.sender,
            amount,
            nftAsset,
            tokenId,
            loanId,
            0 // referral
        );
    }

    function repay(
        address gNft,
        uint256 tokenId
    ) external payable override onlyListedMarket(gNft) nonReentrant whenNotPaused {
        _repay(gNft, tokenId, msg.value);
    }

    function batchRepay(
        address gNft,
        uint256[] calldata tokenIds,
        uint256[] calldata repayAmounts
    ) external payable override onlyListedMarket(gNft) nonReentrant whenNotPaused {
        require(tokenIds.length == repayAmounts.length, "NftCore: inconsistent amounts length");

        uint256 allRepayAmount = 0;
        for (uint256 i = 0; i < repayAmounts.length; i++) {
            allRepayAmount = allRepayAmount.add(repayAmounts[i]);
        }
        require(msg.value >= allRepayAmount, "NftCore: msg.value less than all repay amount");

        for (uint256 i = 0; i < tokenIds.length; i++) {
            _repay(gNft, tokenIds[i], repayAmounts[i]);
        }

        if (msg.value > allRepayAmount) {
            SafeToken.safeTransferETH(msg.sender, msg.value.sub(allRepayAmount));
        }
    }

    function _repay(
        address gNft,
        uint256 tokenId,
        uint256 amount
    ) private {
        address nftAsset = IGNft(gNft).underlying();
        uint256 loanId = lendPoolLoan.getCollateralLoanId(nftAsset, tokenId);
        require(loanId > 0, "NftCore: collateral loan id not exist");

        Constant.LoanData memory loan = lendPoolLoan.getLoan(loanId);

        uint256 borrowBalance = lendPoolLoan.borrowBalanceOf(loanId);
        uint256 repayAmount = Math.min(borrowBalance, amount);

        validator.validateRepay(loanId, repayAmount, borrowBalance);

        if (repayAmount < borrowBalance) {
            lendPoolLoan.updateLoan(
                loanId,
                0,
                repayAmount
            );
        } else {
            lendPoolLoan.repayLoan(
                loanId,
                gNft,
                repayAmount
            );
            IERC721Upgradeable(nftAsset).safeTransferFrom(address(this), loan.borrower, tokenId);
        }

        core.nftRepayBorrow{value: repayAmount}(borrowMarket, loan.borrower, repayAmount);
        if (amount > repayAmount) {
            SafeToken.safeTransferETH(msg.sender, amount.sub(repayAmount));
        }
        emit Repay(
            msg.sender,
            repayAmount,
            nftAsset,
            tokenId,
            msg.sender,
            loanId
        );
    }

    function auction(
        address gNft,
        uint256 tokenId
    ) external payable override onlyListedMarket(gNft) onlyEOA nonReentrant whenNotPaused {
        address nftAsset = IGNft(gNft).underlying();
        uint256 loanId = lendPoolLoan.getCollateralLoanId(nftAsset, tokenId);
        require(loanId > 0, "NftCore: collateral loan id not exist");

        Constant.LoanData memory loan = lendPoolLoan.getLoan(loanId);
        uint256 borrowBalance = lendPoolLoan.borrowBalanceOf(loanId);

        validator.validateAuction(gNft, loanId, msg.value, borrowBalance);
        lendPoolLoan.auctionLoan(msg.sender, loanId, msg.value, borrowBalance);

        if (loan.bidderAddress != address(0)) {
            SafeToken.safeTransferETH(loan.bidderAddress, loan.bidPrice);
        }

        emit Auction(
            msg.sender,
            msg.value,
            nftAsset,
            tokenId,
            loan.borrower,
            loanId
        );
    }

    function redeem(
        address gNft,
        uint256 tokenId,
        uint256 repayAmount,
        uint256 bidFine
    ) external payable override onlyListedMarket(gNft) nonReentrant whenNotPaused {
        address nftAsset = IGNft(gNft).underlying();
        uint256 loanId = lendPoolLoan.getCollateralLoanId(nftAsset, tokenId);
        require(loanId > 0, "NftCore: collateral loan id not exist");
        require(msg.value >= (repayAmount.add(bidFine)), "NftCore: msg.value less than repayAmount + bidFine");

        Constant.LoanData memory loan = lendPoolLoan.getLoan(loanId);
        uint256 borrowBalance = lendPoolLoan.borrowBalanceOf(loanId);

        uint256 _bidFine = validator.validateRedeem(loanId, repayAmount, bidFine, borrowBalance);
        lendPoolLoan.redeemLoan(loanId, repayAmount);

        core.nftRepayBorrow{value: repayAmount}(borrowMarket, loan.borrower, repayAmount);

        if (loan.bidderAddress != address(0)) {
            SafeToken.safeTransferETH(loan.bidderAddress, loan.bidPrice);
            SafeToken.safeTransferETH(loan.firstBidderAddress, _bidFine);
        }

        uint256 paybackAmount = repayAmount.add(_bidFine);
        if (msg.value > paybackAmount) {
            SafeToken.safeTransferETH(msg.sender, msg.value.sub(paybackAmount));
        }
    }

    function liquidate(
        address gNft,
        uint256 tokenId
    ) external payable override onlyListedMarket(gNft) nonReentrant whenNotPaused {
        address nftAsset = IGNft(gNft).underlying();
        uint256 loanId = lendPoolLoan.getCollateralLoanId(nftAsset, tokenId);
        require(loanId > 0, "NftCore: collateral loan id not exist");

        Constant.LoanData memory loan = lendPoolLoan.getLoan(loanId);

        uint256 borrowBalance = lendPoolLoan.borrowBalanceOf(loanId);
        (uint256 extraDebtAmount, uint256 remainAmount) = validator.validateLiquidate(loanId, borrowBalance, msg.value);

        lendPoolLoan.liquidateLoan(gNft, loanId, borrowBalance);
        core.nftRepayBorrow{value: borrowBalance}(borrowMarket, loan.borrower, borrowBalance);

        if (remainAmount > 0) {
            uint256 auctionFee = remainAmount.mul(lendPoolLoan.auctionFeeRate()).div(1e18);
            remainAmount = remainAmount.sub(auctionFee);
            SafeToken.safeTransferETH(loan.borrower, remainAmount);
            SafeToken.safeTransferETH(treasury, auctionFee);
        }

        IERC721Upgradeable(loan.nftAsset).safeTransferFrom(address(this), loan.bidderAddress, loan.nftTokenId);

        if (msg.value > extraDebtAmount) {
            SafeToken.safeTransferETH(msg.sender, msg.value.sub(extraDebtAmount));
        }

        emit Liquidate(
            msg.sender,
            msg.value,
            remainAmount,
            loan.nftAsset,
            loan.nftTokenId,
            loan.borrower,
            loanId
        );
    }
}

