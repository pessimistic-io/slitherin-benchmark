// SPDX-License-Identifier: Apache 2.0

pragma solidity ^0.8.0;

import "./IAspenFeatures.sol";
import "./IAspenVersioned.sol";
import "./IGlobalConfig.sol";

interface IAspenCoreRegistryV0 is IAspenFeaturesV0, IAspenVersionedV2, IGlobalConfigV0 {}

