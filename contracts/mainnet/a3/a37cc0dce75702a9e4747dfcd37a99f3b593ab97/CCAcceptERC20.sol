//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./IPriceStrategy.sol";
import "./ICCAcceptERC20.sol";

contract CCAcceptERC20 is ICCAcceptERC20 {
    mapping(IERC20 => IPriceStrategy) private _erc20PriceStrategy;
    mapping(address => bool) private _erc20Allowed;

    modifier erc20ok(address erc20Contract) {
        require(_erc20Allowed[erc20Contract] == true, "non-whitelisted erc20");
        _;
    }

    constructor(address erc20Contract, address priceStrategy)
    {
        _setERC20PriceStrategy(erc20Contract, priceStrategy);
    }

    function _setERC20PriceStrategy(address erc20Contract, address priceStrategyAddress) internal {
        require(erc20Contract != address(0), "invalid erc20Contract");
        _erc20PriceStrategy[IERC20(erc20Contract)] = IPriceStrategy(priceStrategyAddress);

        bool allowedBefore = _erc20Allowed[erc20Contract];
        _erc20Allowed[erc20Contract] = priceStrategyAddress != address(0) ? true : false;
        bool allowedAfter = _erc20Allowed[erc20Contract];

        if (!allowedBefore && allowedAfter) {
            emit ERC20Allowed(erc20Contract);
        } else if (allowedBefore && !allowedAfter) {
            emit ERC20Denied(erc20Contract);
        }
    }

    function _getERC20Price(address erc20Contract, uint256 tokenNum) internal view erc20ok(erc20Contract) returns (uint256)
    {
        IPriceStrategy priceStrategy = _erc20PriceStrategy[IERC20(erc20Contract)];
        return priceStrategy.getPrice(tokenNum);
    }
}

