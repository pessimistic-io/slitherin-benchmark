// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import "./INameVersion.sol";
import "./IAdmin.sol";

interface IVault is INameVersion, IAdmin {

    function transferOut(address account, address asset, uint256 amount) external;
}

