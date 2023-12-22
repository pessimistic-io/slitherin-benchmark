// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "./Constant.sol";

interface INftMarketDashboardV2 {

    struct NftMarketStats {
        uint256 collateralLoanRatio;
        uint256 totalNftValueInETH;
        uint256 totalBorrowInETH;
    }

    struct NftMarketInfo {
        string symbol;
        uint256 totalSupply;
        uint256 nftCollateralAmount;
        uint256 availableNft;
        uint256 borrowCap;
        uint256 floorPrice;
        uint256 totalNftValueInETH;
        uint256 totalBorrowInETH;
    }

    struct MyNftMarketInfo {
        string symbol;
        uint256 availableBorrowInETH;
        uint256 totalBorrowInETH;
        uint256 nftCollateralAmount;
        uint256 floorPrice;
        uint256 marketBorrowBalance;
        uint256 borrowCap;
    }

    struct UserLoanInfo {
        uint256 loanId;
        Constant.LoanState state;
        uint256 tokenId;
        uint256 healthFactor;
        uint256 debt;
        uint256 liquidationPrice;
        uint256 collateralInETH;
        uint256 availableBorrowInETH;
        uint256 bidPrice;
        uint256 minRepayAmount;
        uint256 maxRepayAmount;
        uint256 repayPenalty;
    }

    struct BorrowModalInfo {
        uint256[] tokenIds;
        uint256 floorPrice;
        uint256 collateralFactor;
        uint256 liquidationThreshold;
    }

    struct ManageLoanModalInfo {
        UserLoanInfo[] userLoanInfos;
        uint256 floorPrice;
    }

    struct MyNftMarketStats {
        uint256 nftCollateralAmount;
        uint256 totalBorrowInETH;
    }

    function borrowModalInfo(address gNft, address user) external view returns (BorrowModalInfo memory);
    function manageLoanModalInfo(address gNft, address user, uint256[] calldata loanIds) external view returns (ManageLoanModalInfo memory);
    function nftMarketStats() external view returns (NftMarketStats memory);
    function nftMarketInfos() external view returns (NftMarketInfo[] memory);

    function myNftMarketStats(address user) external view returns (MyNftMarketStats memory);
    function myNftMarketInfos(address user) external view returns (MyNftMarketInfo[] memory);

    function userLoanInfos(address gNft, address user, uint256[] calldata loanIds) external view returns (UserLoanInfo[] memory);

    function calculateLiquidatePrice(address gNft, uint256 floorPrice, uint256 debt) external view returns (uint256);
    function calculateBiddablePrice(uint256 debt, uint256 bidAmount) external view returns (uint256);
}

