//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {IPool} from "./IPool.sol";
import {StorageLib, YieldStorageLib} from "./StorageLib.sol";
import {InvalidInstrument} from "./ErrorLib.sol";
import {Instrument, Symbol, PositionId, YieldInstrument} from "./libraries_DataTypes.sol";

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

    function cap(function() view external returns (uint128) f) internal view returns (uint128 liquidity) {
        liquidity = f();
        uint256 scaleFactor = IPool(f.address).scaleFactor();
        if (scaleFactor == 1 && liquidity <= 1e12 || scaleFactor == 1e12 && liquidity <= 1e3) {
            liquidity = 0;
        }
    }
}

