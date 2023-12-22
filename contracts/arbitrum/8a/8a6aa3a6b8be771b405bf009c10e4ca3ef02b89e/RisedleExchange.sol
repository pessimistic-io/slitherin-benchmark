// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.6.0;

import { ZeroExOptimized } from "./ZeroExOptimized.sol";

/**
 * @title Risedle Exchange
 * @author bayu <bayu@risedle.com> <https://github.com/pyk>
 * @notice Risedle Exchange is the main proxy contract to interact with
 *         deployed features.
 */
contract RisedleExchange is ZeroExOptimized {
    constructor(address bootstrapper)
        public
        ZeroExOptimized(bootstrapper) {}
}


