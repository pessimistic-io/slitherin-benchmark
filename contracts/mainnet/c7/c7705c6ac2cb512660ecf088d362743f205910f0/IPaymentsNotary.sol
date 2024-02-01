// SPDX-License-Identifier: Apache 2.0

pragma solidity ^0.8;

import "./IAspenFeatures.sol";
import "./IAspenVersioned.sol";
import "./IPaymentNotary.sol";

interface IAspenPaymentsNotaryV1 is IAspenFeaturesV0, IAspenVersionedV2, IPaymentNotaryV1 {}

