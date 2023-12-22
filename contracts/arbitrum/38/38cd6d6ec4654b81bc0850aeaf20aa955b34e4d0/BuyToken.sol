// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./AccessControl.sol";
import "./IERC20.sol";

contract BuyToken is AccessControl {
    struct OrderStruct {
        uint256 limit_usd;
        uint256 total_buy_usd;
    }

    event BUY_TOKEN_EVENT(
        address user,
        uint256 id,
        uint256 amount,
        uint256 timestamp
    );

    address public PAYMENT_TOKEN = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
    address public RECEIVER = 0x0D564801cB47d7Ab32460c5310c9500cD344D2f8;

    mapping(address => mapping(uint256 => OrderStruct)) public buyDetails;

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function buy(uint256 _seedId, uint256 _amount) public {
        OrderStruct storage order = buyDetails[msg.sender][_seedId];
        require(
            order.total_buy_usd + _amount <= order.limit_usd,
            "limit buy seed"
        );

        order.total_buy_usd += _amount;
        IERC20(PAYMENT_TOKEN).transferFrom(msg.sender, RECEIVER, _amount);
        emit BUY_TOKEN_EVENT(msg.sender, _seedId, _amount, block.timestamp);
    }

    function setBuyDetail(
        address _user,
        uint256 _seedId,
        uint256 _limitUsd
    ) public {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "not have permission");
        buyDetails[_user][_seedId] = OrderStruct(_limitUsd, 0);
    }

    function setPaymentToken(address _token) public {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "not have permission");
        PAYMENT_TOKEN = _token;
    }

    function setReceiver(address _address) public {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "not have permission");
        RECEIVER = _address;
    }
}

