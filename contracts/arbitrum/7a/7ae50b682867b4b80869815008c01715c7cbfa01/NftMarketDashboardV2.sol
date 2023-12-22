// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "./SafeMath.sol";
import "./IERC721EnumerableUpgradeable.sol";
import "./IERC721Metadata.sol";

import "./INftMarketDashboardV2.sol";
import "./ILendPoolLoan.sol";
import "./IGToken.sol";
import "./IGNft.sol";
import "./INFTOracle.sol";
import "./INftCore.sol";
import "./INFT.sol";

contract NftMarketDashboardV2 is INftMarketDashboardV2 {
    using SafeMath for uint256;

    /* ========== CONSTANTS ============= */
    address private constant SMOLBRAIN = 0x6325439389E0797Ab35752B4F43a14C004f22A9c;
    address private constant LILPUDGYS = 0x611747CC4576aAb44f602a65dF3557150C214493;

    /* ========== STATE VARIABLES ========== */

    ILendPoolLoan public lendPoolLoan;
    IGToken public borrowMarket;
    INFTOracle public nftOracle;
    INftCore public nftCore;

    /* ========== INITIALIZER ========== */

    constructor(
        address _lendPoolLoan,
        address _borrowMarket,
        address _nftOracle,
        address _nftCore
    ) public {
        lendPoolLoan = ILendPoolLoan(_lendPoolLoan);
        borrowMarket = IGToken(_borrowMarket);
        nftOracle = INFTOracle(_nftOracle);
        nftCore = INftCore(_nftCore);
    }

    /* ========== VIEWS ========== */

    // NFT Market Overview - NFT Market Info
    function nftMarketStats() external view override returns (NftMarketStats memory) {
        NftMarketStats memory _nftMarketStats;

        uint256 _totalBorrowInETH = lendPoolLoan.totalBorrow();

        uint256 _totalSupply = borrowMarket.totalSupply().mul(borrowMarket.exchangeRate()).div(1e18);
        uint256 _collateralLoanRatio = 0;

        if (_totalSupply > 0) {
            _collateralLoanRatio = _totalBorrowInETH.mul(1e18).div(_totalSupply);
        }

        uint256 _totalNftValueInETH = 0;
        address[] memory _markets = nftCore.allMarkets();
        for (uint256 i = 0; i < _markets.length; i++) {
            address _underlying = IGNft(_markets[i]).underlying();
            uint256 _nftCollateralAmount = lendPoolLoan.getNftCollateralAmount(_underlying);
            uint256 _nftPriceInETH = nftOracle.getUnderlyingPrice(_markets[i]);
            uint256 _nftCollateralValue = _nftPriceInETH.mul(_nftCollateralAmount);
            _totalNftValueInETH = _totalNftValueInETH.add(_nftCollateralValue);
        }

        _nftMarketStats.collateralLoanRatio = _collateralLoanRatio;
        _nftMarketStats.totalNftValueInETH = _totalNftValueInETH;
        _nftMarketStats.totalBorrowInETH = _totalBorrowInETH;
        return _nftMarketStats;
    }

    // NFT Market Overview - NFT Market List
    function nftMarketInfos() external view override returns (NftMarketInfo[] memory) {
        address[] memory _markets = nftCore.allMarkets();
        NftMarketInfo[] memory _nftMarketInfos = new NftMarketInfo[](_markets.length);

        for (uint256 i = 0; i < _markets.length; i++) {
            address _underlying = IGNft(_markets[i]).underlying();
            string memory _symbol = IERC721Metadata(_underlying).symbol();
            uint256 _totalSupply = 0;
            if (_underlying == LILPUDGYS) {
                _totalSupply = INFT(_underlying).MAX_ELEMENTS();
            } else {
                _totalSupply = IERC721EnumerableUpgradeable(_underlying).totalSupply();
            }
            uint256 _nftCollateralAmount = lendPoolLoan.getNftCollateralAmount(_underlying);
            uint256 _supplyCap = nftCore.marketInfoOf(_markets[i]).supplyCap;
            uint256 _availableNft = _supplyCap.sub(_nftCollateralAmount);
            uint256 _borrowCap = nftCore.marketInfoOf(_markets[i]).borrowCap;
            uint256 _floorPrice = nftOracle.getUnderlyingPrice(_markets[i]);
            uint256 _totalNftValueInETH = _floorPrice.mul(_nftCollateralAmount);
            uint256 _totalBorrowInETH = lendPoolLoan.marketBorrowBalance(_markets[i]);

            _nftMarketInfos[i] = NftMarketInfo({
                symbol: _symbol,
                totalSupply: _totalSupply,
                nftCollateralAmount: _nftCollateralAmount,
                availableNft: _availableNft,
                borrowCap: _borrowCap,
                floorPrice: _floorPrice,
                totalNftValueInETH: _totalNftValueInETH,
                totalBorrowInETH: _totalBorrowInETH
            });
        }
        return _nftMarketInfos;
    }

    // Deposit NFT & Borrow ETH Modal
    function borrowModalInfo(address gNft, address user) external view override returns (BorrowModalInfo memory) {
        BorrowModalInfo memory _borrowModalInfo;

        uint256[] memory tokenIds = _getUserTokenIds(gNft, user);

        _borrowModalInfo.tokenIds = tokenIds;
        _borrowModalInfo.floorPrice = nftOracle.getUnderlyingPrice(gNft);
        _borrowModalInfo.collateralFactor = nftCore.marketInfoOf(gNft).collateralFactor;
        _borrowModalInfo.liquidationThreshold = nftCore.marketInfoOf(gNft).liquidationThreshold;

        return _borrowModalInfo;
    }

    // Manage Loan Modal
    function manageLoanModalInfo(address gNft, address user, uint256[] calldata loanIds) external view override returns (ManageLoanModalInfo memory) {
        ManageLoanModalInfo memory _manageLoanModalInfo;

        UserLoanInfo[] memory userLoanInfos = _getUserLoanInfos(gNft, user, loanIds);

        _manageLoanModalInfo.userLoanInfos = userLoanInfos;
        _manageLoanModalInfo.floorPrice = nftOracle.getUnderlyingPrice(gNft);

        return _manageLoanModalInfo;
    }

    // My Dashboard - NFT Market Info
    function myNftMarketStats(address user) external view override returns (MyNftMarketStats memory) {
        MyNftMarketStats memory _myNftMarketStats;

        uint256 _totalCollateralAmount = 0;
        uint256 _totalBorrowAmount = lendPoolLoan.userBorrowBalance(user);

        address[] memory _markets = nftCore.allMarkets();
        for (uint256 i = 0; i < _markets.length; i++) {
            address _underlying = IGNft(_markets[i]).underlying();
            uint256 _nftCollateralAmount = lendPoolLoan.getUserNftCollateralAmount(user, _underlying);
            _totalCollateralAmount = _totalCollateralAmount.add(_nftCollateralAmount);
        }

        _myNftMarketStats.nftCollateralAmount = _totalCollateralAmount;
        _myNftMarketStats.totalBorrowInETH = _totalBorrowAmount;
        return _myNftMarketStats;
    }

    // My Dashboard - My Collection List
    function myNftMarketInfos(address user) external view override returns (MyNftMarketInfo[] memory) {
        address[] memory _markets = nftCore.allMarkets();
        address _user = user;
        uint256 _activeMarketCount = 0;

        for (uint256 i = 0; i < _markets.length; i++) {
            address _underlying = IGNft(_markets[i]).underlying();
            uint256 _nftCollateralAmount = lendPoolLoan.getUserNftCollateralAmount(_user, _underlying);
            if (_nftCollateralAmount > 0) {
                _activeMarketCount = _activeMarketCount.add(1);
            }
        }

        address[] memory _activeMarkets = new address[](_activeMarketCount);
        uint256 idx = 0;
        for (uint256 i = 0; i < _markets.length; i++) {
            address _underlying = IGNft(_markets[i]).underlying();
            uint256 _nftCollateralAmount = lendPoolLoan.getUserNftCollateralAmount(_user, _underlying);
            if (_nftCollateralAmount > 0) {
                _activeMarkets[idx] = _markets[i];
                idx = idx + 1;
            }
        }

        MyNftMarketInfo[] memory _myNftMarketInfos = new MyNftMarketInfo[](_activeMarkets.length);
        for (uint256 i = 0; i < _activeMarkets.length; i++) {
            address _underlying = IGNft(_activeMarkets[i]).underlying();
            string memory _symbol = IERC721Metadata(_underlying).symbol();
            uint256 _nftCollateralAmount = lendPoolLoan.getUserNftCollateralAmount(_user, _underlying);
            uint256 _floorPrice = nftOracle.getUnderlyingPrice(_activeMarkets[i]);
            uint256 _totalBorrowInETH = lendPoolLoan.marketAccountBorrowBalance(_activeMarkets[i], _user);
            uint256 _collateralFactor = nftCore.marketInfoOf(_activeMarkets[i]).collateralFactor;
            uint256 _collateralValueInETH = _floorPrice.mul(_nftCollateralAmount).mul(_collateralFactor).div(1e18);
            uint256 _marketBorrowBalance = lendPoolLoan.marketBorrowBalance(_activeMarkets[i]);
            uint256 _borrowCap = nftCore.marketInfoOf(_activeMarkets[i]).borrowCap;

            uint256 _availableBorrowInETH = 0;

            if (_collateralValueInETH >= _totalBorrowInETH) {
                _availableBorrowInETH = _collateralValueInETH.sub(_totalBorrowInETH);
            }

            if (_marketBorrowBalance.add(_availableBorrowInETH) > _borrowCap) {
                _availableBorrowInETH = _marketBorrowBalance.add(_availableBorrowInETH).sub(_borrowCap);
            }

            _myNftMarketInfos[i] = MyNftMarketInfo({
                symbol: _symbol,
                availableBorrowInETH: _availableBorrowInETH,
                totalBorrowInETH: _totalBorrowInETH,
                nftCollateralAmount: _nftCollateralAmount,
                floorPrice: _floorPrice,
                marketBorrowBalance: _marketBorrowBalance,
                borrowCap: _borrowCap
            });
        }
        return _myNftMarketInfos;
    }

    // My Dashboard - My Collection List - View Details
    function userLoanInfos(address gNft, address user, uint256[] calldata loanIds) external view override returns (UserLoanInfo[] memory) {
        return _getUserLoanInfos(gNft, user, loanIds);
    }

    function calculateLiquidatePrice(address gNft, uint256 floorPrice, uint256 debt) external view override returns (uint256) {
        uint256 liquidationBonus = nftCore.marketInfoOf(gNft).liquidationBonus;
        uint256 bonusAmount = floorPrice.mul(liquidationBonus).div(1e18);

        uint256 liquidatePrice = floorPrice.sub(bonusAmount);

        if (liquidatePrice < debt) {
            uint256 bidDelta = debt.mul(1e16).div(1e18); // 1%
            liquidatePrice = debt.add(bidDelta).add(1e16); // 0.01ETH
        }
        return liquidatePrice;
    }

    function calculateBiddablePrice(uint256 debt, uint256 bidAmount) external view override returns (uint256) {
        uint256 bidDelta = debt.mul(1e16).div(1e18); // 1%
        return bidAmount.add(bidDelta).add(1e16); // 0.01ETH
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    function _getUserTokenIds(address gNft, address user) private view returns (uint256[] memory) {
        address _underlying = IGNft(gNft).underlying();
        uint256 _balance = IERC721Upgradeable(_underlying).balanceOf(user);

        uint256[] memory tokenIds = new uint256[](_balance);
        tokenIds = INFT(_underlying).walletOfOwner(user);
        return tokenIds;
    }

    function _getUserLoanInfos(address gNft, address user, uint256[] calldata loanIds) private view returns (UserLoanInfo[] memory) {
        address _user = user;
        address _gNft = gNft;
        address _underlying = IGNft(_gNft).underlying();
        uint256 _currentLoanId = lendPoolLoan.currentLoanId();
        uint256 _userLoanCount = 0;
        uint256[] memory _loanIds = loanIds;

        if (_currentLoanId == 1) {
            return new UserLoanInfo[](0);
        }

        for (uint256 i = 0; i < _loanIds.length; i++) {
            Constant.LoanData memory loan = lendPoolLoan.getLoan(_loanIds[i]);
            if (loan.nftAsset == _underlying &&
               (loan.state == Constant.LoanState.Active || loan.state == Constant.LoanState.Auction) &&
                loan.borrower == _user) {
                _userLoanCount = _userLoanCount.add(1);
            }
        }

        UserLoanInfo[] memory _userLoanInfos = new UserLoanInfo[](_userLoanCount);
        uint256 idx = 0;
        uint256 _nftAssetPrice = nftOracle.getUnderlyingPrice(_gNft);
        uint256 _liquidationThreshold = nftCore.marketInfoOf(_gNft).liquidationThreshold;
        uint256 _collateralFactor = nftCore.marketInfoOf(_gNft).collateralFactor;
        uint256 _redeemThreshold = lendPoolLoan.redeemThreshold();
        uint256 _minBidFine = lendPoolLoan.minBidFine();
        uint256 _redeemFineRate = lendPoolLoan.redeemFineRate();

        for (uint256 i = 0; i < _loanIds.length; i++) {
            Constant.LoanData memory loan = lendPoolLoan.getLoan(_loanIds[i]);
            if (loan.nftAsset == _underlying &&
               (loan.state == Constant.LoanState.Active || loan.state == Constant.LoanState.Auction) &&
                loan.borrower == _user) {
                uint256 _borrowBalance = lendPoolLoan.borrowBalanceOf(_loanIds[i]);
                uint256 _nftCollateralInETH = _nftAssetPrice.mul(_collateralFactor).div(1e18);
                uint256 _availableBorrowInETH = 0;
                uint256 _bidFineAmount = _borrowBalance.mul(_redeemFineRate).div(1e18);
                if (_bidFineAmount < _minBidFine) {
                    _bidFineAmount = _minBidFine;
                }

                if (_nftCollateralInETH > _borrowBalance) {
                    _availableBorrowInETH = _nftCollateralInETH.sub(_borrowBalance);
                }
                _userLoanInfos[idx] = UserLoanInfo({
                    loanId: loan.loanId,
                    state: loan.state,
                    tokenId: loan.nftTokenId,
                    healthFactor: _calculateHealthFactor(_nftAssetPrice, _borrowBalance, _liquidationThreshold),
                    debt: _borrowBalance,
                    liquidationPrice: _calculateLiquidationPrice(_borrowBalance, _liquidationThreshold),
                    collateralInETH: loan.state == Constant.LoanState.Active ? _nftCollateralInETH : 0,
                    availableBorrowInETH: _availableBorrowInETH,
                    bidPrice: loan.bidPrice,
                    minRepayAmount: loan.state == Constant.LoanState.Auction ? _borrowBalance.mul(_redeemThreshold).div(1e18) : 0,
                    maxRepayAmount: loan.state == Constant.LoanState.Auction ? _borrowBalance.mul(9e17).div(1e18) : 0,
                    repayPenalty: loan.state == Constant.LoanState.Auction ? _bidFineAmount : 0
                });
                idx = idx.add(1);
            }
        }
        return _userLoanInfos;
    }

    function _calculateHealthFactor(uint256 _totalCollateral, uint256 _totalDebt, uint256 _liquidationThreshold) private pure returns (uint256) {
        if (_totalDebt == 0) {
            return uint256(-1);
        }
        return (_totalCollateral.mul(_liquidationThreshold).mul(1e18).div(_totalDebt).div(1e18));
    }

    function _calculateLiquidationPrice(uint256 _totalDebt, uint256 _liquidationThreshold) private pure returns (uint256) {
        if (_totalDebt == 0) {
            return 0;
        }
        return (_totalDebt.mul(1e18).div(_liquidationThreshold));
    }
}

