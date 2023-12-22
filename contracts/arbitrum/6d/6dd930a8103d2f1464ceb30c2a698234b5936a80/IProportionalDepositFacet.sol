// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {SafeERC20, IERC20} from "./SafeERC20.sol";

import "./IPermissionsFacet.sol";
import "./ICommonFacet.sol";
import "./ITokensManagementFacet.sol";

interface IProportionalDepositFacet {
    function proportionalDeposit(
        uint256[] calldata tokenAmounts,
        uint256 minLpAmount
    ) external returns (uint256 lpAmount, uint256[] memory actualTokenAmounts);
}

