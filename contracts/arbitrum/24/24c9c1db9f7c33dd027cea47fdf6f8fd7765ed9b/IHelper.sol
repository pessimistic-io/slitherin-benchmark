// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.0;

import "./IAsymptoticPerpetual.sol";

interface IHelper {
    function swapToState(
        Market calldata market,
        State calldata state,
        uint rA,
        uint rB,
        bytes calldata payload
    ) external view returns(State memory state1);
}

