// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

import "./IERC20Metadata.sol";

interface IFeeRouter {
    function colletFees() external;

    function getDAOVault() external view returns (address);

    function getGewardVault() external view returns (address);

    function getPercentForGeward() external view returns (uint256);

    function getTokens() external view returns (address[] memory);
}

