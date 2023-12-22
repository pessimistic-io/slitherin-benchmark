// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.18;

import "./extensions_IERC20MetadataUpgradeable.sol";
import "./IERC4626Upgradeable.sol";
import "./IRewardRouterV2.sol";

contract VaultRouterStorage {
    enum Contracts {
        GLPRewardRouterV2,
        GLPLeverageCompounder,
        GLPBaseCompounder
    }

    IRewardRouterV2 public glpRewardRouterV2;
    IERC4626Upgradeable public glpLeverageCompounderVault;
    IERC4626Upgradeable public glpCompounderVault;

    IERC20MetadataUpgradeable public sGLP;
}
