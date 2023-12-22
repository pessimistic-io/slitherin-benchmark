// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { IERC20 } from "./IERC20.sol";
import { IERC20Metadata } from "./IERC20Metadata.sol";

import { IValuer } from "./IValuer.sol";

contract Erc20Valuer is IValuer {
    function getVaultValue(
        address vault,
        address asset,
        int256 unitPrice
    ) external view returns (uint256 value) {
        uint balance = IERC20(asset).balanceOf(vault);
        uint decimals = IERC20Metadata(asset).decimals();
        value = (uint(unitPrice) * balance) / (10 ** decimals);
    }

    function getAssetValue(
        uint amount,
        address asset,
        int256 unitPrice
    ) external view returns (uint256 value) {
        uint decimals = IERC20Metadata(asset).decimals();
        value = (uint(unitPrice) * amount) / (10 ** decimals);
    }
}

