// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import { IVariableDebtToken } from "./IVariableDebtToken.sol";

interface IDebtToken is IVariableDebtToken {
    function totalSupply() external view returns (uint256);

    function balanceOf(address user) external view returns (uint256);
}

