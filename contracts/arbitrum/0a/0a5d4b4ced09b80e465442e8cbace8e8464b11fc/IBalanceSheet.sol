// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

//   /$$$$$$$            /$$$$$$$$
//  | $$__  $$          | $$_____/
//  | $$  \ $$  /$$$$$$ | $$     /$$$$$$  /$$$$$$   /$$$$$$
//  | $$  | $$ /$$__  $$| $$$$$ /$$__  $$|____  $$ /$$__  $$
//  | $$  | $$| $$$$$$$$| $$__/| $$  \__/ /$$$$$$$| $$  \ $$
//  | $$  | $$| $$_____/| $$   | $$      /$$__  $$| $$  | $$
//  | $$$$$$$/|  $$$$$$$| $$   | $$     |  $$$$$$$|  $$$$$$$
//  |_______/  \_______/|__/   |__/      \_______/ \____  $$
//                                                 /$$  \ $$
//                                                |  $$$$$$/
//                                                 \______/

/// @author DeFragDAO
interface IBalanceSheet {
    function setLoan(
        address _userAddress,
        uint256[] memory _tokenIds,
        uint256 _borrowedAmount
    ) external;

    function updateFees() external;

    function removeCollateral(
        address _userAddress,
        uint256[] memory _tokenIds
    ) external;

    function isExistingUser(address _userAddress) external view returns (bool);

    function removingCollateralProjectedLTV(
        address _userAddress,
        uint256 _numberOfTokens
    ) external view returns (uint256 newCollateralRatio);

    function setPayment(
        address _userAddress,
        uint256 _paymentAmount
    ) external returns (uint256);

    function getLoanBasics(
        address _userAddress
    )
        external
        view
        returns (
            uint256[] memory tokenIds,
            uint256 accruedFees,
            uint256 borrowedAmount,
            uint256 paymentsAmount,
            uint256 claimableFees
        );

    function getLoanMetrics(
        address _userAddress
    )
        external
        view
        returns (
            uint256 collateralizationRatio,
            uint256 outstandingLoan,
            uint256 borrowingPower,
            uint256 collateralValue,
            uint256 loanToValueRatio,
            uint256 healthScore
        );

    function getTokenIds(
        address _userAddress
    ) external view returns (uint256[] memory tokenIds);

    function getAccruedFees(
        address _userAddress
    ) external view returns (uint256);

    function getBorrowedAmount(
        address _userAddress
    ) external view returns (uint256);

    function getPaymentsAmount(
        address _userAddress
    ) external view returns (uint256);

    function getCurrentPremium(
        uint256 _numberOfTokens,
        uint256 _strikePrice
    ) external view returns (uint256);

    function getAssetAveragePrice()
        external
        view
        returns (uint256 assetAveragePrice);

    function getCollateralValue(
        address _userAddress
    ) external view returns (uint256 collateralValue);

    function getOutstandingLoan(
        address _userAddress
    ) external view returns (uint256);

    function getBorrowingPower(
        address _userAddress
    ) external view returns (uint256 borrowingPower);

    function getCollateralizationRatio(
        address _userAddress
    ) external view returns (uint256 collateralizationRatio);

    function isLiquidatable(address _userAddress) external view returns (bool);

    function getLiquidatables() external view returns (address[] memory);

    function getTotalAmountBorrowed()
        external
        view
        returns (uint256 totalAmountBorrowed);

    function getSystemTotalCollateral()
        external
        view
        returns (uint256 systemTotalCollateral);

    function getTotalAccruedFees()
        external
        view
        returns (uint256 totalAccruedFees);

    function getTotalPayments() external view returns (uint256 totalPayments);

    function setLiquidation(address _userAddress) external;

    function getLiquidationCount(
        address _userAddress
    ) external view returns (uint256 liquidationCount);

    function getTotalLiquidationCount()
        external
        view
        returns (uint256 totalLiquidationCount);

    function getClaimableFees(
        address _userAddress
    ) external view returns (uint256 claimableFees);

    function getTotalClaimableFees()
        external
        view
        returns (uint256 totalClaimableFees);

    function getTotalCollateralValue()
        external
        view
        returns (uint256 totalCollateralValue);

    function getTotalNumberOfTokens()
        external
        view
        returns (uint256 totalNumberOfTokens);

    function getProtocolBasics()
        external
        view
        returns (
            uint256 totalBorrowedAmount,
            uint256 totalCollateralValue,
            uint256 totalNumberOfTokens,
            uint256 totalAccruedFees,
            uint256 totalPayments,
            uint256 totalClaimableFees,
            uint256 totalLiquidationCount
        );

    function getProtocolMetrics()
        external
        view
        returns (
            uint256 totalOutstandingLoan,
            uint256 getProtocolLoanToValueRatio,
            uint256 getProtocolHealthScore
        );

    function getTotalOutstandingLoans()
        external
        view
        returns (uint256 totalOutstandingLoans);

    function getAllUsers() external view returns (address[] memory);

    function getLoanToValueRatio(
        address _userAddress
    ) external view returns (uint256 loanToValueRatio);

    function getProtocolLoanToValueRatio()
        external
        view
        returns (uint256 protocolLoanToValueRatio);

    function getProtocolLTVThreshold()
        external
        view
        returns (uint256 protocolLTVThreshold);

    function getHealthScore(
        address _userAddress
    ) external view returns (uint256 healthScore);

    function getProtocolHealthScore()
        external
        view
        returns (uint256 protocolHealthScore);
}

