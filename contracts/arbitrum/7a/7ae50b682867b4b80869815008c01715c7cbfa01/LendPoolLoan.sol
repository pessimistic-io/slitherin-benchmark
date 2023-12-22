// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "./SafeMath.sol";
import "./OwnableUpgradeable.sol";
import "./CountersUpgradeable.sol";
import "./IERC721Upgradeable.sol";
import "./IERC721ReceiverUpgradeable.sol";

import "./ILendPoolLoan.sol";
import "./ICore.sol";
import "./INftCore.sol";
import "./IGNft.sol";
import "./IRateModel.sol";
import "./IGToken.sol";
import "./IRateModel.sol";
import "./INFTOracle.sol";

import "./Constant.sol";

contract LendPoolLoan is ILendPoolLoan, OwnableUpgradeable, IERC721ReceiverUpgradeable {
    using SafeMath for uint256;
    using CountersUpgradeable for CountersUpgradeable.Counter;

    /* ========== CONSTANT VARIABLES ========== */

    uint256 internal constant DUST = 1000;

    /* ========== STATE VARIABLES ========== */

    INftCore public nftCore;
    ICore public core;
    IGToken public borrowMarket;

    CountersUpgradeable.Counter private _loanIdTracker;
    mapping(uint256 => Constant.LoanData) private _loans;
    mapping(address => Constant.BorrowInfo) private _accountBorrows;
    mapping(address => Constant.BorrowInfo) private _marketBorrows;
    mapping(address => mapping(address => Constant.BorrowInfo)) private _marketAccountBorrows;

    uint256 public _totalBorrow;
    uint256 public lastAccruedTime;
    uint256 public override accInterestIndex;
    uint256 public borrowRateMultiplier;

    uint256 public override auctionDuration;
    uint256 public override minBidFine;
    uint256 public override redeemFineRate;
    uint256 public override redeemThreshold;
    uint256 public override auctionFeeRate;

    // nftAsset + nftTokenId => loanId
    mapping(address => mapping(uint256 => uint256)) private _nftToLoanIds;
    mapping(address => uint256) private _nftTotalCollateral;
    mapping(address => mapping(address => uint256)) private _userNftCollateral;

    /* ========== INITIALIZER ========== */

    function initialize(
        INftCore _nftCore,
        ICore _core,
        IGToken _borrowMarket,
        uint256 _auctionDuration,
        uint256 _minBidFine,
        uint256 _redeemFineRate,
        uint256 _redeemThreshold,
        uint256 _borrowRateMultiplier,
        uint256 _auctionFeeRate
    ) external initializer {
        __Ownable_init();

        nftCore = _nftCore;
        core = _core;
        borrowMarket = _borrowMarket;

        auctionDuration = _auctionDuration;
        minBidFine = _minBidFine;
        redeemFineRate = _redeemFineRate;
        redeemThreshold = _redeemThreshold;
        borrowRateMultiplier = _borrowRateMultiplier;

        auctionFeeRate = _auctionFeeRate;

        // Avoid having loanId = 0
        _loanIdTracker.increment();

        lastAccruedTime = block.timestamp;
        accInterestIndex = 1e18;
    }

    /* ========== MODIFIERS ========== */

    modifier accrue() {
        if (block.timestamp > lastAccruedTime && borrowMarket.getRateModel() != address(0)) {
            uint256 borrowRate = getBorrowRate();
            uint256 interestFactor = borrowRate.mul(block.timestamp.sub(lastAccruedTime));
            uint256 pendingInterest = _totalBorrow.mul(interestFactor).div(1e18);

            _totalBorrow = _totalBorrow.add(pendingInterest);
            accInterestIndex = accInterestIndex.add(interestFactor.mul(accInterestIndex).div(1e18));
            lastAccruedTime = block.timestamp;
        }
        _;
    }

    modifier onlyNftCore() {
        require(msg.sender == address(nftCore), "LendPoolLoan: caller should be nft core");
        _;
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function initNft(address nftAsset, address gNft) external override onlyNftCore {
        IERC721Upgradeable(nftAsset).setApprovalForAll(gNft, true);
    }

    function setAuctionDuration(uint256 _auctionDuration) external onlyOwner {
        require(_auctionDuration <= Constant.AUCTION_DURATION_MAX, "LendPoolLoan: invalid auction duration");
        auctionDuration = _auctionDuration;
        emit AuctionDurationUpdated(_auctionDuration);
    }

    function setMinBidFine(uint256 _minBidFine) external onlyOwner {
        require(_minBidFine <= Constant.MIN_BID_FINE_MAX, "LendPoolLoan: invalid min bid fine");
        minBidFine = _minBidFine;
        emit MinBidFineUpdated(_minBidFine);
    }

    function setRedeemFineRate(uint256 _redeemFineRate) external onlyOwner {
        require(_redeemFineRate <= Constant.REDEEM_FINE_RATE_MAX, "LendPoolLoan: invalid redeem fine ratio");
        redeemFineRate = _redeemFineRate;
        emit RedeemFineRateUpdated(_redeemFineRate);
    }

    function setRedeemThreshold(uint256 _redeemThreshold) external onlyOwner {
        require(_redeemThreshold <= Constant.REDEEM_THRESHOLD_MAX, "LendPoolLoan: invalid redeem threshold");
        redeemThreshold = _redeemThreshold;
        emit RedeemThresholdUpdated(_redeemThreshold);
    }

    function setBorrowRateMultiplier(uint256 _borrowRateMultiplier) external onlyOwner {
        require(_borrowRateMultiplier <= Constant.BORROW_RATE_MULTIPLIER_MAX, "LendPoolLoan: invalid borrow rate multiplier");
        borrowRateMultiplier = _borrowRateMultiplier;
        emit BorrowRateMultiplierUpdated(_borrowRateMultiplier);
    }

    function setAuctionFeeRate(uint256 _auctionFeeRate) external onlyOwner {
        require(_auctionFeeRate <= Constant.AUCTION_FEE_RATE_MAX, "LendPoolLoan: invalid auction fee rate");
        auctionFeeRate = _auctionFeeRate;
        emit AuctionFeeRateUpdated(_auctionFeeRate);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function createLoan(
        address to,
        address nftAsset,
        uint256 nftTokenId,
        address gNft,
        uint256 amount
    ) external override onlyNftCore accrue returns (uint256) {
        require(_nftToLoanIds[nftAsset][nftTokenId] == 0, "LendPoolLoan: nft already used as collateral");

        uint256 loanId = _loanIdTracker.current();
        _loanIdTracker.increment();
        _nftToLoanIds[nftAsset][nftTokenId] = loanId;

        IERC721Upgradeable(nftAsset).safeTransferFrom(msg.sender, address(this), nftTokenId);

        IGNft(gNft).mint(to, nftTokenId);

        Constant.LoanData storage loanData = _loans[loanId];
        loanData.loanId = loanId;
        loanData.state = Constant.LoanState.Active;
        loanData.borrower = to;
        loanData.gNft = gNft;
        loanData.nftAsset = nftAsset;
        loanData.nftTokenId = nftTokenId;
        loanData.borrowAmount = amount;
        loanData.interestIndex = accInterestIndex;

        Constant.BorrowInfo storage info = _accountBorrows[to];
        if (info.borrow == 0) {
            info.borrow = amount;
            info.interestIndex = accInterestIndex;
        } else {
            info.borrow = info.borrow.mul(accInterestIndex).div(info.interestIndex).add(amount);
            info.interestIndex = accInterestIndex;
        }

        Constant.BorrowInfo storage marketBorrowInfo = _marketBorrows[gNft];
        if (marketBorrowInfo.borrow == 0) {
            marketBorrowInfo.borrow = amount;
            marketBorrowInfo.interestIndex = accInterestIndex;
        } else {
            marketBorrowInfo.borrow = marketBorrowInfo.borrow.mul(accInterestIndex).div(marketBorrowInfo.interestIndex).add(amount);
            marketBorrowInfo.interestIndex = accInterestIndex;
        }

        Constant.BorrowInfo storage marketAccountBorrowInfo = _marketAccountBorrows[gNft][to];
        if (marketAccountBorrowInfo.borrow == 0) {
            marketAccountBorrowInfo.borrow = amount;
            marketAccountBorrowInfo.interestIndex = accInterestIndex;
        } else {
            marketAccountBorrowInfo.borrow = marketAccountBorrowInfo.borrow.mul(accInterestIndex).div(marketAccountBorrowInfo.interestIndex).add(amount);
            marketAccountBorrowInfo.interestIndex = accInterestIndex;
        }

        _totalBorrow = _totalBorrow.add(amount);

        _userNftCollateral[to][nftAsset] = _userNftCollateral[to][nftAsset].add(1);
        _nftTotalCollateral[nftAsset] = _nftTotalCollateral[nftAsset].add(1);

        emit LoanCreated(to, loanId, nftAsset, nftTokenId, gNft, amount);
        return (loanId);
    }

    function updateLoan(
        uint256 loanId,
        uint256 amountAdded,
        uint256 amountTaken
    ) external override onlyNftCore accrue {
        Constant.LoanData storage loan = _loans[loanId];
        require(loan.state == Constant.LoanState.Active, "LendPoolLoan: invalid loan state");

        if (loan.interestIndex == 0) {
            loan.interestIndex = accInterestIndex;
        }

        loan.borrowAmount = loan.borrowAmount.mul(accInterestIndex).div(loan.interestIndex).add(amountAdded).sub(amountTaken);
        loan.interestIndex = accInterestIndex;

        Constant.BorrowInfo storage info = _accountBorrows[loan.borrower];
        info.borrow = info.borrow.mul(accInterestIndex).div(info.interestIndex).add(amountAdded).sub(amountTaken);
        info.interestIndex = accInterestIndex;

        Constant.BorrowInfo storage marketBorrowInfo = _marketBorrows[loan.gNft];
        marketBorrowInfo.borrow = marketBorrowInfo.borrow.mul(accInterestIndex).div(marketBorrowInfo.interestIndex).add(amountAdded).sub(amountTaken);
        marketBorrowInfo.interestIndex = accInterestIndex;

        Constant.BorrowInfo storage marketAccountBorrowInfo = _marketAccountBorrows[loan.gNft][loan.borrower];
        marketAccountBorrowInfo.borrow = marketAccountBorrowInfo.borrow.mul(accInterestIndex).div(marketAccountBorrowInfo.interestIndex).add(amountAdded).sub(amountTaken);
        marketAccountBorrowInfo.interestIndex = accInterestIndex;

        _totalBorrow = _totalBorrow.add(amountAdded).sub(amountTaken);

        loan.borrowAmount = (loan.borrowAmount < DUST) ? 0 : loan.borrowAmount;
        info.borrow = (info.borrow < DUST) ? 0 : info.borrow;
        marketBorrowInfo.borrow = (marketBorrowInfo.borrow < DUST) ? 0 : marketBorrowInfo.borrow;
        marketAccountBorrowInfo.borrow = (marketAccountBorrowInfo.borrow < DUST) ? 0 : marketAccountBorrowInfo.borrow;
        _totalBorrow = (_totalBorrow < DUST) ? 0 : _totalBorrow;

        emit LoanUpdated(loan.borrower, loanId, loan.nftAsset, loan.nftTokenId, amountAdded, amountTaken);
    }

    function repayLoan(
        uint256 loanId,
        address gNft,
        uint256 amount
    ) external override onlyNftCore accrue {
        Constant.LoanData storage loan = _loans[loanId];
        require(loan.state == Constant.LoanState.Active, "LendPoolLoan: invalid loan state");

        loan.state = Constant.LoanState.Repaid;
        loan.borrowAmount = 0;

        Constant.BorrowInfo storage info = _accountBorrows[loan.borrower];
        if (info.borrow.mul(accInterestIndex).div(info.interestIndex) < amount) {
            info.borrow = 0;
        } else {
            info.borrow = info.borrow.mul(accInterestIndex).div(info.interestIndex).sub(amount);
        }
        info.interestIndex = accInterestIndex;

        Constant.BorrowInfo storage marketAccountBorrowInfo = _marketAccountBorrows[loan.gNft][loan.borrower];
        if (marketAccountBorrowInfo.borrow.mul(accInterestIndex).div(marketAccountBorrowInfo.interestIndex) < amount) {
            marketAccountBorrowInfo.borrow = 0;
        } else {
            marketAccountBorrowInfo.borrow = marketAccountBorrowInfo.borrow.mul(accInterestIndex).div(marketAccountBorrowInfo.interestIndex).sub(amount);
        }
        marketAccountBorrowInfo.interestIndex = accInterestIndex;

        Constant.BorrowInfo storage marketBorrowInfo = _marketBorrows[loan.gNft];
        if (marketBorrowInfo.borrow.mul(accInterestIndex).div(marketBorrowInfo.interestIndex) < amount) {
            marketBorrowInfo.borrow = 0;
        } else {
            marketBorrowInfo.borrow = marketBorrowInfo.borrow.mul(accInterestIndex).div(marketBorrowInfo.interestIndex).sub(amount);
        }
        marketBorrowInfo.interestIndex = accInterestIndex;

        if (_totalBorrow < amount) {
            _totalBorrow = 0;
        } else {
            _totalBorrow = _totalBorrow.sub(amount);
        }

        loan.borrowAmount = (loan.borrowAmount < DUST) ? 0 : loan.borrowAmount;
        info.borrow = (info.borrow < DUST) ? 0 : info.borrow;
        marketBorrowInfo.borrow = (marketBorrowInfo.borrow < DUST) ? 0 : marketBorrowInfo.borrow;
        marketAccountBorrowInfo.borrow = (marketAccountBorrowInfo.borrow < DUST) ? 0 : marketAccountBorrowInfo.borrow;
        _totalBorrow = (_totalBorrow < DUST) ? 0 : _totalBorrow;

        _nftToLoanIds[loan.nftAsset][loan.nftTokenId] = 0;

        require(_userNftCollateral[loan.borrower][loan.nftAsset] >= 1, "LendPoolLoan: invalid user nft amount");
        _userNftCollateral[loan.borrower][loan.nftAsset] = _userNftCollateral[loan.borrower][loan.nftAsset].sub(1);

        require(_nftTotalCollateral[loan.nftAsset] >= 1, "LendPoolLoan: invalid nft amount");
        _nftTotalCollateral[loan.nftAsset] = _nftTotalCollateral[loan.nftAsset].sub(1);

        IGNft(gNft).burn(loan.nftTokenId);
        IERC721Upgradeable(loan.nftAsset).safeTransferFrom(address(this), msg.sender, loan.nftTokenId);

        emit LoanRepaid(loan.borrower, loanId, loan.nftAsset, loan.nftTokenId, amount);
    }

    function auctionLoan(
        address bidder,
        uint256 loanId,
        uint256 bidPrice,
        uint256 borrowAmount
    ) external override onlyNftCore accrue {
        Constant.LoanData storage loan = _loans[loanId];
        address previousBidder = loan.bidderAddress;
        uint256 previousPrice = loan.bidPrice;

        if (loan.bidStartTimestamp == 0) {
            require(loan.state == Constant.LoanState.Active, "LendPoolLoan: invalid loan state");
            loan.state = Constant.LoanState.Auction;
            loan.bidStartTimestamp = block.timestamp;
            loan.firstBidderAddress = bidder;
            loan.floorPrice = INFTOracle(nftCore.getNftOracle()).getUnderlyingPrice(loan.gNft);
        } else {
            require(loan.state == Constant.LoanState.Auction, "LendPoolLoan: invalid loan state");
            require(bidPrice > loan.bidPrice, "LendPoolLoan: bid price less than highest price");
        }

        loan.bidBorrowAmount = borrowAmount;
        loan.bidderAddress = bidder;
        loan.bidPrice = bidPrice;
        loan.bidCount = loan.bidCount.add(1);

        emit LoanAuctioned(
            bidder,
            loanId,
            loan.nftAsset,
            loan.nftTokenId,
            loan.bidBorrowAmount,
            bidder,
            bidPrice,
            previousBidder,
            previousPrice,
            loan.floorPrice
        );
    }

    function redeemLoan(
        uint256 loanId,
        uint256 amountTaken
    ) external override onlyNftCore accrue {
        Constant.LoanData storage loan = _loans[loanId];
        require(loan.state == Constant.LoanState.Auction, "LendPoolLoan: invalid loan state");
        require(amountTaken > 0, "LendPoolLoan: invalid taken amount");

        loan.borrowAmount = loan.borrowAmount.mul(accInterestIndex).div(loan.interestIndex);
        require(loan.borrowAmount >= amountTaken, "LendPoolLoan: amount underflow");
        loan.borrowAmount = loan.borrowAmount.sub(amountTaken);
        loan.interestIndex = accInterestIndex;

        Constant.BorrowInfo storage info = _accountBorrows[loan.borrower];
        info.borrow = info.borrow.mul(accInterestIndex).div(info.interestIndex);
        require(info.borrow >= amountTaken, "LendPoolLoan: amount underflow");
        info.borrow = info.borrow.sub(amountTaken);
        info.interestIndex = accInterestIndex;

        Constant.BorrowInfo storage marketBorrowInfo = _marketBorrows[loan.gNft];
        marketBorrowInfo.borrow = marketBorrowInfo.borrow.mul(accInterestIndex).div(marketBorrowInfo.interestIndex);
        require(marketBorrowInfo.borrow >= amountTaken, "LendPoolLoan: amount underflow");
        marketBorrowInfo.borrow = marketBorrowInfo.borrow.sub(amountTaken);
        marketBorrowInfo.interestIndex = accInterestIndex;

        Constant.BorrowInfo storage marketAccountBorrowInfo = _marketAccountBorrows[loan.gNft][loan.borrower];
        marketAccountBorrowInfo.borrow = marketAccountBorrowInfo.borrow.mul(accInterestIndex).div(marketAccountBorrowInfo.interestIndex);
        require(marketAccountBorrowInfo.borrow >= amountTaken, "LendPoolLoan: amount underflow");
        marketAccountBorrowInfo.borrow = marketAccountBorrowInfo.borrow.sub(amountTaken);
        marketAccountBorrowInfo.interestIndex = accInterestIndex;

        _totalBorrow = _totalBorrow.sub(amountTaken);

        loan.borrowAmount = (loan.borrowAmount < DUST) ? 0 : loan.borrowAmount;
        info.borrow = (info.borrow < DUST) ? 0 : info.borrow;
        marketBorrowInfo.borrow = (marketBorrowInfo.borrow < DUST) ? 0 : marketBorrowInfo.borrow;
        marketAccountBorrowInfo.borrow = (marketAccountBorrowInfo.borrow < DUST) ? 0 : marketAccountBorrowInfo.borrow;
        _totalBorrow = (_totalBorrow < DUST) ? 0 : _totalBorrow;

        loan.state = Constant.LoanState.Active;
        loan.bidStartTimestamp = 0;
        loan.bidBorrowAmount = 0;
        loan.bidderAddress = address(0);
        loan.bidPrice = 0;
        loan.firstBidderAddress = address(0);
        loan.floorPrice = 0;
        loan.bidCount = 0;

        emit LoanRedeemed(
            loan.borrower,
            loanId,
            loan.nftAsset,
            loan.nftTokenId,
            amountTaken
        );
    }

    function liquidateLoan(
        address gNft,
        uint256 loanId,
        uint256 borrowAmount
    ) external override onlyNftCore accrue {
        Constant.LoanData storage loan = _loans[loanId];
        require(loan.state == Constant.LoanState.Auction, "LendPoolLoan: invalid loan state");

        loan.state = Constant.LoanState.Defaulted;
        loan.borrowAmount = 0;
        loan.bidBorrowAmount = borrowAmount;

        Constant.BorrowInfo storage info = _accountBorrows[loan.borrower];
        if (info.borrow.mul(accInterestIndex).div(info.interestIndex) < borrowAmount) {
            info.borrow = 0;
        } else {
            info.borrow = info.borrow.mul(accInterestIndex).div(info.interestIndex).sub(borrowAmount);
        }
        info.interestIndex = accInterestIndex;

        Constant.BorrowInfo storage marketBorrowInfo = _marketBorrows[loan.gNft];
        if (marketBorrowInfo.borrow.mul(accInterestIndex).div(marketBorrowInfo.interestIndex) < borrowAmount) {
            marketBorrowInfo.borrow = 0;
        } else {
            marketBorrowInfo.borrow = marketBorrowInfo.borrow.mul(accInterestIndex).div(marketBorrowInfo.interestIndex).sub(borrowAmount);
        }
        marketBorrowInfo.interestIndex = accInterestIndex;

        Constant.BorrowInfo storage marketAccountBorrowInfo = _marketAccountBorrows[loan.gNft][loan.borrower];
        if (marketAccountBorrowInfo.borrow.mul(accInterestIndex).div(marketAccountBorrowInfo.interestIndex) < borrowAmount) {
            marketAccountBorrowInfo.borrow = 0;
        } else {
            marketAccountBorrowInfo.borrow = marketAccountBorrowInfo.borrow.mul(accInterestIndex).div(marketAccountBorrowInfo.interestIndex).sub(borrowAmount);
        }
        marketAccountBorrowInfo.interestIndex = accInterestIndex;

        if (_totalBorrow < borrowAmount) {
            _totalBorrow = 0;
        } else {
            _totalBorrow = _totalBorrow.sub(borrowAmount);
        }

        info.borrow = (info.borrow < DUST) ? 0 : info.borrow;
        marketBorrowInfo.borrow = (marketBorrowInfo.borrow < DUST) ? 0 : marketBorrowInfo.borrow;
        marketAccountBorrowInfo.borrow = (marketAccountBorrowInfo.borrow < DUST) ? 0 : marketAccountBorrowInfo.borrow;
        _totalBorrow = (_totalBorrow < DUST) ? 0 : _totalBorrow;

        _nftToLoanIds[loan.nftAsset][loan.nftTokenId] = 0;

        require(_userNftCollateral[loan.borrower][loan.nftAsset] >= 1, "LendPoolLoan: invalid user nft amount");
        _userNftCollateral[loan.borrower][loan.nftAsset] = _userNftCollateral[loan.borrower][loan.nftAsset].sub(1);

        require(_nftTotalCollateral[loan.nftAsset] >= 1, "LendPoolLoan: invalid nft amount");
        _nftTotalCollateral[loan.nftAsset] = _nftTotalCollateral[loan.nftAsset].sub(1);

        IGNft(gNft).burn(loan.nftTokenId);
        IERC721Upgradeable(loan.nftAsset).safeTransferFrom(address(this), msg.sender, loan.nftTokenId);

        emit LoanLiquidated(
            loan.borrower,
            loanId,
            loan.nftAsset,
            loan.nftTokenId,
            borrowAmount
        );
    }

    function accrueInterest() external override accrue {}

    /* ========== VIEWS ========== */

    function getCollateralLoanId(address nftAsset, uint256 nftTokenId) external view override returns (uint256) {
        return _nftToLoanIds[nftAsset][nftTokenId];
    }

    function getNftCollateralAmount(address nftAsset) external view override returns (uint256) {
        return _nftTotalCollateral[nftAsset];
    }

    function getUserNftCollateralAmount(address user, address nftAsset) external view override returns (uint256) {
        return _userNftCollateral[user][nftAsset];
    }

    function borrowBalanceOf(uint256 loanId) public view override returns (uint256) {
        Constant.AccrueLoanSnapshot memory snapshot = pendingAccrueSnapshot();
        Constant.LoanData storage loan = _loans[loanId];

        if (loan.borrowAmount == 0) return 0;
        return loan.borrowAmount.mul(snapshot.accInterestIndex).div(loan.interestIndex);
    }

    function totalBorrow() public view override returns (uint256) {
        Constant.AccrueLoanSnapshot memory snapshot = pendingAccrueSnapshot();
        return snapshot.totalBorrow;
    }

    function userBorrowBalance(address user) external view override returns (uint256) {
        Constant.AccrueLoanSnapshot memory snapshot = pendingAccrueSnapshot();
        Constant.BorrowInfo memory info = _accountBorrows[user];

        if (info.borrow == 0) return 0;
        return info.borrow.mul(snapshot.accInterestIndex).div(info.interestIndex);
    }

    function marketBorrowBalance(address gNft) external view override returns (uint256) {
        Constant.AccrueLoanSnapshot memory snapshot = pendingAccrueSnapshot();
        Constant.BorrowInfo memory marketBorrowInfo = _marketBorrows[gNft];

        if (marketBorrowInfo.borrow == 0) return 0;
        return marketBorrowInfo.borrow.mul(snapshot.accInterestIndex).div(marketBorrowInfo.interestIndex);
    }

    function marketAccountBorrowBalance(address gNft, address user) external view override returns (uint256) {
        Constant.AccrueLoanSnapshot memory snapshot = pendingAccrueSnapshot();
        Constant.BorrowInfo memory marketAccountBorrowInfo = _marketAccountBorrows[gNft][user];

        if (marketAccountBorrowInfo.borrow == 0) return 0;
        return marketAccountBorrowInfo.borrow.mul(snapshot.accInterestIndex).div(marketAccountBorrowInfo.interestIndex);
    }

    function getLoan(uint256 loanId) external view override returns (Constant.LoanData memory loanData) {
        return _loans[loanId];
    }

    function pendingAccrueSnapshot() internal view returns (Constant.AccrueLoanSnapshot memory) {
        Constant.AccrueLoanSnapshot memory snapshot;
        snapshot.totalBorrow = _totalBorrow;
        snapshot.accInterestIndex = accInterestIndex;

        if (block.timestamp > lastAccruedTime && _totalBorrow > 0) {
            uint256 borrowRate = getBorrowRate();
            uint256 interestFactor = borrowRate.mul(block.timestamp.sub(lastAccruedTime));
            uint256 pendingInterest = _totalBorrow.mul(interestFactor).div(1e18);

            snapshot.totalBorrow = _totalBorrow.add(pendingInterest);
            snapshot.accInterestIndex = accInterestIndex.add(interestFactor.mul(accInterestIndex).div(1e18));
        }
        return snapshot;
    }

    function getBorrowRate() internal view returns (uint256) {
        uint256 _borrowRate = IRateModel(borrowMarket.getRateModel()).getBorrowRate(
            borrowMarket.getCash(), borrowMarket._totalBorrow(), borrowMarket.totalReserve()
        );
        return _borrowRate.mul(borrowRateMultiplier).div(1e18);
    }

    function currentLoanId() external view override returns (uint256) {
        uint256 _loanId = _loanIdTracker.current();
        return _loanId;
    }

    function getAccInterestIndex() public view override returns (uint256) {
        Constant.AccrueLoanSnapshot memory snapshot = pendingAccrueSnapshot();
        return snapshot.accInterestIndex;
    }

    /* ========== RECEIVER FUNCTIONS ========== */

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external override returns (bytes4) {
        operator;
        from;
        tokenId;
        data;
        return IERC721ReceiverUpgradeable.onERC721Received.selector;
    }
}

