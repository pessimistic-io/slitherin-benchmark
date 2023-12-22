// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./AccessControlEnumerable.sol";
import "./IPriceConsumer.sol";

contract ManualPriceConsumer is IPriceConsumer, AccessControlEnumerable {
    mapping(address => uint256) private _tokenPrice;
    mapping(address => uint256) private _tokenTimestamp;

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function fetchPriceInUSD(address token, uint256 minTimestamp) external override {}

    function getPriceInUSD(address token) external view override returns (uint256, uint256) {
        return (_tokenPrice[token], _tokenTimestamp[token]);
    }

    function updatePrice(
        address token,
        uint256 price,
        uint256 timestamp
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _tokenPrice[token] = price;
        _tokenTimestamp[token] = timestamp;
    }
}

