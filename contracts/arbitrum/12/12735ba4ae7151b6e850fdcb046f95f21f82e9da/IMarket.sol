// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;
import {IPositionBook} from "./IPositionBook.sol";
import {IFeeRouter} from "./IFeeRouter.sol";
import {IOrderBook} from "./IOrderBook.sol";
import "./OrderStruct.sol";
import {MarketDataTypes} from "./MarketDataTypes.sol";
import "./PositionStruct.sol";
import {IOrderStore} from "./IOrderStore.sol";

interface IMarketStorage {
    function marketValid() external view returns (address);

    function globalValid() external view returns (address);

    function indexToken() external view returns (address);

    function positionBook() external view returns (IPositionBook); // slot 2

    function collateralToken() external view returns (address);

    function orderBookLong() external view returns (IOrderBook); // slot 2

    function orderBookShort() external view returns (IOrderBook); // slot 2

    function feeRouter() external view returns (IFeeRouter); // slot 2

    function priceFeed() external view returns (address); // slot 2

    function positionStoreLong() external view returns (address); // slot 2

    function positionStoreShort() external view returns (address); // slot 2

    function vaultRouter() external view returns (address); // slot 2
}

interface IMarket is IMarketStorage {
    struct OrderExec {
        address market;
        address account;
        uint64 orderID;
        bool isIncrease;
        bool isLong;
    }

    //=============================
    //user actions
    //=============================
    function increasePositionWithOrders(
        MarketDataTypes.UpdatePositionInputs memory _inputs
    ) external;

    function decreasePosition(
        MarketDataTypes.UpdatePositionInputs memory _vars
    ) external;

    function updateOrder(
        MarketDataTypes.UpdateOrderInputs memory _vars
    ) external;

    function cancelOrderList(
        address _account,
        bool[] memory _isIncreaseList,
        uint256[] memory _orderIDList,
        bool[] memory _isLongList
    ) external;

    //=============================
    //sys actions
    //=============================
    function initialize(address[] calldata addrs, string memory _name) external;

    function execOrderKey(
        Order.Props memory exeOrder,
        MarketDataTypes.UpdatePositionInputs memory _params
    ) external;

    function execOrderByIndex(OrderExec memory order) external;

    function liquidatePositions(
        address[] memory accounts,
        bool _isLong
    ) external;

    //=============================
    //read-only
    //=============================
    function getPNL() external view returns (int256);

    function USDDecimals() external pure returns (uint8);

    function priceFeed() external view returns (address);

    function indexToken() external view returns (address);

    function getPositions(
        address account
    ) external view returns (Position.Props[] memory _poss);

    function orderStore(
        bool isLong,
        bool isOpen
    ) external view returns (IOrderStore);
}

library MarketAddressIndex {
    uint public constant ADDR_PB = 0;
    uint public constant ADDR_OBL = 1;
    uint public constant ADDR_OBS = 2;

    uint public constant ADDR_MV = 3;
    uint public constant ADDR_PF = 4;

    uint public constant ADDR_PM = 5;
    uint public constant ADDR_MI = 6;

    uint public constant ADDR_IT = 7;
    uint public constant ADDR_FR = 8;
    uint public constant ADDR_MR = 9;

    uint public constant ADDR_VR = 10;
    uint public constant ADDR_CT = 11;
}

