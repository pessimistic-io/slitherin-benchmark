// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ICToken.sol";

interface IComptroller {
    function oracle() external view returns (address);

    function compAccrued(address user) external view returns (uint256 amount);

    function claimComp(address holder, ICToken[] memory _scTokens) external;

    function claimComp(address holder) external;

    function enterMarkets(address[] memory _scTokens) external;

    function pendingComptrollerImplementation() external view returns (address implementation);

    function markets(address ctoken) external view returns (bool, uint256, bool);

    function compSpeeds(address ctoken) external view returns (uint256); // will be deprecated

    function compBorrowSpeeds(address ctoken) external view returns (uint256);

    function compSupplySpeeds(address ctoken) external view returns (uint256);

    function borrowCaps(address cToken) external view returns (uint256);

    function supplyCaps(address cToken) external view returns (uint256);

    function rewardDistributor() external view returns (address);
}

interface IPriceOracle {
    function getUnderlyingPrice(ICToken cToken) external view returns (uint256);
}

