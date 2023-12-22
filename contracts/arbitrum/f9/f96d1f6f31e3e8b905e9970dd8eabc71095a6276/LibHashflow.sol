// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.17;

import {IQuote} from "./IQuote.sol";
import {LibAsset} from "./LibAsset.sol";
import {LibBytes} from "./LibBytes.sol";
import {Hop, LibHop} from "./LibHop.sol";

library LibHashflow {
    using LibAsset for address;
    using LibBytes for bytes;
    using LibHop for Hop;

    function swapHashflow(Hop memory h) internal {
        h.enforceSingleHop();
        bytes memory poolData = h.poolDataList[0];
        address poolAddress;
        uint256 baseTokenAmount;
        uint256 quoteTokenAmount;
        uint256 expiry;
        uint256 nonce;
        bytes32 transactionId;

        h.path[0].approve(h.addr, h.amountIn);

        assembly {
            poolAddress := shr(96, mload(add(poolData, 32)))
            baseTokenAmount := mload(add(poolData, 52))
            quoteTokenAmount := mload(add(poolData, 84))
            expiry := mload(add(poolData, 116))
            nonce := mload(add(poolData, 148))
            transactionId := mload(add(poolData, 180))
        }

        uint256 poolDataSize = poolData.length;
        IQuote(h.addr).tradeSingleHop(
            IQuote.Quote({
                pool: poolAddress,
                externalAccount: address(0),
                trader: address(this),
                effectiveTrader: h.recipient,
                baseToken: h.path[0],
                quoteToken: h.path[1],
                effectiveBaseTokenAmount: h.amountIn,
                maxBaseTokenAmount: baseTokenAmount,
                maxQuoteTokenAmount: quoteTokenAmount,
                quoteExpiry: expiry,
                nonce: nonce,
                txid: transactionId,
                signature: poolData.slice(180, poolDataSize - 180)
            })
        );
    }
}

