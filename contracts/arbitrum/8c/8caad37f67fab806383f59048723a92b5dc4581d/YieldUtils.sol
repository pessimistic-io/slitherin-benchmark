//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import {StorageLib, YieldStorageLib} from "./StorageLib.sol";
import {InvalidInstrument} from "./ErrorLib.sol";
import {Instrument, Symbol, PositionId, YieldInstrument} from "./interfaces_DataTypes.sol";

library YieldUtils {
    function loadInstrument(Symbol symbol)
        internal
        view
        returns (Instrument storage instrument, YieldInstrument storage yieldInstrument)
    {
        instrument = StorageLib.getInstruments()[symbol];
        if (instrument.maturity == 0) {
            revert InvalidInstrument(symbol);
        }
        yieldInstrument = YieldStorageLib.getInstruments()[symbol];
    }

    function toVaultId(PositionId positionId) internal pure returns (bytes12) {
        return bytes12(uint96(PositionId.unwrap(positionId)));
    }
}

