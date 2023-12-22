// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.18;

import { ICoreUUPS_ABIVersionAware } from "./ICoreUUPS_ABIVersionAware.sol";
import { IERC20Upgradeable } from "./IERC20Upgradeable.sol";
import {     IERC20MetadataUpgradeable } from "./IERC20MetadataUpgradeable.sol";

interface IBaseMultiUserStrategyV1 is IERC20Upgradeable, IERC20MetadataUpgradeable, ICoreUUPS_ABIVersionAware {}

