// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

contract CurveErrorCodes {
    enum Error {
        OK, // No error
        INVALID_NUMITEMS, // The numItem value is 0
        SPOT_PRICE_OVERFLOW // The updated spot price doesn't fit into 128 bits
    }

    /**
     *  @return totalProtocolFeeMultiplier totalProtocol fee multiplier
     *  @return totalProtocolFeeAmount total protocol fee amount
     *  @return protocolFeeAmount protocol fee amount
     *  @return protocolFeeReceiver protocol fee receiver
     */
    struct ProtocolFeeStruct {
        uint totalProtocolFeeMultiplier;
        uint totalProtocolFeeAmount;
        uint[] protocolFeeAmount;
        address[] protocolFeeReceiver;
    }

}

