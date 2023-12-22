// SPDX-License-Identifier: GPL-3.0-only

pragma solidity 0.8.18;

import "./IERC20.sol";
import "./IERC1155.sol";
import "./IOrderUtil.sol";
import {IAddressBook} from "./IAddressBook.sol";

interface IHedgedPool {
    function addressBook() external view returns (IAddressBook);

    function getCollateralBalance() external view returns (uint256);

    function strikeToken() external view returns (IERC20);

    function collateralToken() external view returns (IERC20);

    function getAllUnderlyings() external view returns (address[] memory);

    function getActiveOTokens() external view returns (address[] memory);

    function hedgers(address underlying) external view returns (address);

    function trade(
        IOrderUtil.Order calldata order,
        uint256 traderDeposit,
        uint256 traderVaultId,
        bool autoCreateVault
    ) external;
}

