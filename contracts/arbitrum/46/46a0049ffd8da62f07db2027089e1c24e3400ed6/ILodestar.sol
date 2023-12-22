// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import "./ICompound.sol";

interface IComptrollerLodestar is IComptrollerCompound {
    function markets(address cTokenAddress)
        external
        view
        returns (
            bool isListed,
            uint256 collateralFactorMantissa,
            bool isComped
        );

    function oracle() external view returns (address);
}

interface IDistributionLodestar {
    function claimComp(address holder, address[] calldata cTokens) external;

    function compAccrued(address holder) external view returns (uint256);

    function compInitialIndex() external view returns (uint224);

    function compSupplyState(address xToken)
        external
        view
        returns (uint224, uint32);

    function compSupplierIndex(address xToken, address account)
        external
        view
        returns (uint256);

    function compBorrowState(address xToken)
        external
        view
        returns (uint224, uint32);

    function compBorrowerIndex(address xToken, address account)
        external
        view
        returns (uint256);

    function compSpeeds(address _asset) external view returns (uint256);

    function compSupplySpeeds(address _asset) external view returns (uint256);

    function getCompAddress() external view returns (address);
}

interface IOracleLodestar {
    function getUnderlyingPrice(address vToken) external view returns (uint256);

    function ethUsdAggregator() external view returns (address);
}

