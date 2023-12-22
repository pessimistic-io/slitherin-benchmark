//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./IContango.sol";

interface IContangoYield is IContango {
    function yieldInstrumentV2(Symbol symbol) external view returns (YieldInstrument memory instrument);
}

