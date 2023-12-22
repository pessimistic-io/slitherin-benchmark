//SPDX-License-Identifier: UXUY
pragma solidity ^0.8.11;

import "./AdapterBase.sol";
import "./IBridgeAdapter.sol";
import "./SafeNativeAsset.sol";
import "./SafeERC20.sol";

abstract contract BridgeAdapterBase is IBridgeAdapter, AdapterBase {}

