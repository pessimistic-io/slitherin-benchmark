// SPDX-License-Identifier: LicenseRef-P3-DUAL
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity =0.8.19;

import {UD60x18} from "./UD60x18.sol";

import {OwnableStorage} from "./OwnableStorage.sol";
import {IERC1155} from "./IERC1155.sol";
import {IERC165} from "./IERC165.sol";
import {ERC165BaseInternal} from "./ERC165BaseInternal.sol";
import {Proxy} from "./Proxy.sol";
import {IDiamondReadable} from "./IDiamondReadable.sol";
import {IERC20Metadata} from "./IERC20Metadata.sol";

import {DoublyLinkedListUD60x18, DoublyLinkedList} from "./DoublyLinkedListUD60x18.sol";
import {PRBMathExtra} from "./PRBMathExtra.sol";

import {PoolStorage} from "./PoolStorage.sol";

/// @title Upgradeable proxy with centrally controlled Pool implementation
contract PoolProxy is Proxy, ERC165BaseInternal {
    using DoublyLinkedListUD60x18 for DoublyLinkedList.Bytes32List;
    using PoolStorage for PoolStorage.Layout;
    using PRBMathExtra for UD60x18;

    address private immutable DIAMOND;

    constructor(
        address diamond,
        address base,
        address quote,
        address oracleAdapter,
        UD60x18 strike,
        uint256 maturity,
        bool isCallPool
    ) {
        DIAMOND = diamond;
        OwnableStorage.layout().owner = msg.sender;

        {
            PoolStorage.Layout storage l = PoolStorage.layout();

            l.base = base;
            l.quote = quote;

            l.oracleAdapter = oracleAdapter;

            l.strike = strike;
            l.maturity = maturity;

            uint8 baseDecimals = IERC20Metadata(base).decimals();
            uint8 quoteDecimals = IERC20Metadata(quote).decimals();

            l.baseDecimals = baseDecimals;
            l.quoteDecimals = quoteDecimals;

            l.isCallPool = isCallPool;

            l.tickIndex.push(PoolStorage.MIN_TICK_PRICE);
            l.tickIndex.push(PoolStorage.MAX_TICK_PRICE);

            l.currentTick = PoolStorage.MIN_TICK_PRICE;
            l.marketPrice = PoolStorage.MIN_TICK_PRICE.intoUD50x28();
        }

        _setSupportsInterface(type(IERC165).interfaceId, true);
        _setSupportsInterface(type(IERC1155).interfaceId, true);
    }

    /// @inheritdoc Proxy
    function _getImplementation() internal view override returns (address) {
        return IDiamondReadable(DIAMOND).facetAddress(msg.sig);
    }
}

