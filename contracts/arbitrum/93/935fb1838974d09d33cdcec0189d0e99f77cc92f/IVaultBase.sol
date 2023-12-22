// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20Metadata.sol";
import "./IERC4626.sol";
import "./IMulticall.sol";

/**
 * @title Knox Vault Base Interface
 * @dev includes ERC20Metadata and ERC4626 interfaces
 */

interface IVaultBase is IERC20Metadata, IERC4626, IMulticall {

}

