// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {     IUniswapV3Factory } from "./IUniswapV3Factory.sol";
import {     IUniswapV3Pool } from "./IUniswapV3Pool.sol";
import {     IERC20,     SafeERC20 } from "./SafeERC20.sol";
import {     OwnableUpgradeable } from "./OwnableUpgradeable.sol";
import {     ERC20Upgradeable } from "./ERC20Upgradeable.sol";
import {     ReentrancyGuardUpgradeable } from "./ReentrancyGuardUpgradeable.sol";
import {     EnumerableSet } from "./EnumerableSet.sol";
import {Range, Rebalance, InitializePayload} from "./SArrakisV2.sol";
import {hundredPercent} from "./CArrakisV2.sol";
import {     UUPSUpgradeable } from "./UUPSUpgradeable.sol";
import {     IUniswapV3Pool } from "./IUniswapV3Pool.sol";

struct ArrakisStorage {
    IUniswapV3Factory factory;
    IERC20 token0;
    IERC20 token1;
    uint256 init0;
    uint256 init1;
    uint16 managerFeeBPS;
    uint256 managerBalance0;
    uint256 managerBalance1;
    address manager;
    Range[] ranges;
    EnumerableSet.AddressSet pools;
    EnumerableSet.AddressSet routers;
}

library ArrakisStorageLib {
    // keccak256("arrakis.vault");
    // solhint-disable-next-line const-name-snakecase
    bytes32 private constant storagePosition =
        0xe3ad27f6776c50a3e2a472a1ca98705922a7e91abcd31c1ccc4121e91e8cee38;

    function getStorage() internal pure returns (ArrakisStorage storage ts) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            ts.slot := storagePosition
        }
    }
}

