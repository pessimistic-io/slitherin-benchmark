// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20Upgradeable} from "./IERC20Upgradeable.sol";

import {IGenericMintableTo} from "./IGenericMintableTo.sol";
import {IGenericBurnableFrom} from "./IGenericBurnableFrom.sol";

/**
 * @dev Interface of the IMintableTokenUpgradeable standard
 */
interface IMintableTokenUpgradeable is IGenericMintableTo, IERC20Upgradeable {

}

/**
 * @dev Interface of the IMintableBurnableTokenUpgradeable standard
 */
interface IMintableBurnableTokenUpgradeable is IMintableTokenUpgradeable, IGenericBurnableFrom {

}

