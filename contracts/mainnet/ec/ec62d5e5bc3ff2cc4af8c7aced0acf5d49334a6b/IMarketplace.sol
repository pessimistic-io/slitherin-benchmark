// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.10;

import {DataTypes} from "./DataTypes.sol";
import {Errors} from "./Errors.sol";
import {OrderTypes} from "./OrderTypes.sol";
import {SeaportInterface} from "./SeaportInterface.sol";
import {ILooksRareExchange} from "./ILooksRareExchange.sol";
import {SignatureChecker} from "./SignatureChecker.sol";
import {ConsiderationItem} from "./ConsiderationStructs.sol";
import {AdvancedOrder, CriteriaResolver, Fulfillment, OfferItem, ItemType} from "./ConsiderationStructs.sol";
import {Address} from "./Address.sol";
import {IERC1271} from "./IERC1271.sol";

interface IMarketplace {
    function getAskOrderInfo(bytes memory data, address WETH)
        external
        view
        returns (DataTypes.OrderInfo memory orderInfo);

    function getBidOrderInfo(bytes memory data)
        external
        view
        returns (DataTypes.OrderInfo memory orderInfo);

    function matchAskWithTakerBid(
        address marketplace,
        bytes calldata data,
        uint256 value
    ) external payable returns (bytes memory);

    function matchBidWithTakerAsk(address marketplace, bytes calldata data)
        external
        returns (bytes memory);
}

