// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.18;

import "./extensions_IERC20MetadataUpgradeable.sol";
import "./IRewardRouterV2.sol";
import "./IRewardReader.sol";

contract GLPVaultStorageV1 {
    address public WETH;
    IRewardRouterV2 public GMXRewardRouterV2;
    IRewardRouterV2 public GLPRewardRouterV2;

    uint public lastCompoundTimestamp; // Unused storage slot from previous implementation that has since been upgraded
    uint public minimumCompoundInterval; // Unused storage slot from previous implementation that has since been upgraded

    enum Contracts {
        GMXRewardRouterV2,
        GLPRewardRouterV2
    }

    bool public shouldCompound;
}

