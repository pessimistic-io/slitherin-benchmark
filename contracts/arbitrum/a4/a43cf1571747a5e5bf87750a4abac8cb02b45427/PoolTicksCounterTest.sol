// SPDX-License-Identifier: GPL-2.0-or-later
import "./IRamsesV2Pool.sol";

pragma solidity >=0.6.0;

import "./PoolTicksCounter.sol";

contract PoolTicksCounterTest {
    using PoolTicksCounter for IRamsesV2Pool;

    function countInitializedTicksCrossed(
        IRamsesV2Pool pool,
        int24 tickBefore,
        int24 tickAfter
    ) external view returns (uint32 initializedTicksCrossed) {
        return pool.countInitializedTicksCrossed(tickBefore, tickAfter);
    }
}

