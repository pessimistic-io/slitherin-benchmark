// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IQuote} from "./IQuote.sol";
import {LibAsset} from "./LibAsset.sol";
import {LibBytes} from "./LibBytes.sol";
import {Hop} from "./LibHop.sol";

library LibHashflow {
    using LibAsset for address;
    using LibBytes for bytes;

    function swapHashflow(Hop memory h) internal returns (uint256 amountOut) {
        uint256 i;
        uint256 l = h.path.length;

        for (i = 0; i < l - 1; ) {
            bytes memory poolData = h.poolDataList[i];
            IQuote.RFQTQuote memory quote;

            assembly {
                mstore(quote, shr(96, mload(add(poolData, 32)))) // pool
                mstore(add(quote, 32), shr(96, mload(add(poolData, 180)))) // externalAccount
                mstore(add(quote, 96), shr(96, mload(add(poolData, 200)))) // effectiveTrader
                mstore(add(quote, 224), mload(add(poolData, 52))) // baseTokenAmount
                mstore(add(quote, 256), mload(add(poolData, 84))) // quoteTokenAmount
                mstore(add(quote, 288), mload(add(poolData, 116))) // quoteExpiry
                mstore(add(quote, 320), mload(add(poolData, 148))) // nonce
                mstore(add(quote, 352), mload(add(poolData, 220))) // txid
            }

            quote.effectiveBaseTokenAmount = i == 0 ? h.amountIn : amountOut;
            quote.trader = address(this);
            quote.baseToken = h.path[i];
            quote.quoteToken = h.path[i + 1];
            quote.signature = poolData.slice(220, poolData.length - 220);

            h.path[i].approve(h.addr, quote.effectiveBaseTokenAmount);

            IQuote(h.addr).tradeRFQT(quote);

            amountOut = h.path[i + 1].getBalance();

            unchecked {
                i++;
            }
        }
    }
}

