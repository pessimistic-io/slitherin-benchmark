// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Counters} from "./Counters.sol";
import {Ownable} from "./Ownable.sol";

import {Pausable} from "./Pausable.sol";
import {IPyth} from "./IPyth.sol";
import {PythStructs} from "./PythStructs.sol";

contract PerpMock is Ownable, Pausable {
  
    struct Order {
        uint256 timestamp;
        uint256 amount;
        int64 price;
        uint256 publishTime;
    }


    IPyth private _pyth;
    uint256 public orderId;
    address public immutable gelatoMsgSender;

    mapping(uint256 => Order) public ordersByOrderId;
    mapping(address => uint256[]) public ordesByUser;

    event setOrderEvent(uint256 timestamp, uint256 orderId);

    modifier onlyGelatoMsgSender() {
        require(
            msg.sender == gelatoMsgSender,
            "Only dedicated gelato msg.sender"
        );
        _;
    }

    constructor(address _gelatoMsgSender, address pythContract) {
        gelatoMsgSender = _gelatoMsgSender;
        _pyth = IPyth(pythContract);
    }

    /* solhint-disable-next-line no-empty-blocks */
    receive() external payable {}

    function setOrder(uint256 _amount) external {
        orderId+=1;
        ordersByOrderId[orderId]= Order(block.timestamp,_amount,0,0);
        ordesByUser[msg.sender].push(orderId);
        emit setOrderEvent(block.timestamp, orderId);      

    }

    function updatePrice(
        bytes[] memory updatePriceData,
        uint256[] memory orders
    ) external onlyGelatoMsgSender {
        uint256 fee = _pyth.getUpdateFee(updatePriceData);
        _pyth.updatePriceFeeds{value: fee}(updatePriceData);
        /* solhint-disable-next-line */
        bytes32 priceID = bytes32(
            0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace
        );

        PythStructs.Price memory checkPrice = _pyth.getPriceUnsafe(priceID);
      
        for (uint256 i = 0; i < orders.length; i++) {
            Order storage order = ordersByOrderId[orders[i]];
            require(
                order.timestamp + 12 < checkPrice.publishTime,
                "NOT 12 sec elapsed"
            );

            order.price = checkPrice.price;
            order.publishTime = checkPrice.publishTime;
            }
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function withdraw() external onlyOwner returns (bool) {
        (bool result, ) = payable(msg.sender).call{
            value: address(this).balance
        }("");
        return result;
    }

    function getOrder(uint256 _order) public view returns (Order memory) {
        return ordersByOrderId[_order];
    }
}

