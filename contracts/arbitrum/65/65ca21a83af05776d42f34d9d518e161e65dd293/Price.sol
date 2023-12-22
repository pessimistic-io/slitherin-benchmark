// SPDX-License-Identifier: Business Source License 1.1
pragma solidity ^0.8.19;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./IPriceStorage.sol";
import {TransferUtil} from "./Utils.sol";

    error TokenNotSupported(address token);

abstract contract Price is IPriceStorage {
    using SafeERC20 for IERC20;
    using TransferUtil for address;

    function _setPrice(address token, uint price) internal {
        // check token contract somehow
        token.erc20BalanceOf(address(this));

        uint previous = _price(token);

        _price(token, price);

        if (previous == 0) {
            _addTokenToPrice(token);
        }
    }

    function _removePrice(address token) internal {
        _delPrice(token);
        // do not remove token from the list, because it participates in the jackpot
    }

    function _debit(address token, address from, address target, uint multiplier) internal returns (uint) {
        require(multiplier != 0, "Price: multiplier must not be 0");
        uint price = _price(token);
        if (price == 0) {
            revert TokenNotSupported(token);
        }

        uint finalPrice = price * multiplier;
        IERC20(token).safeTransferFrom(from, target, finalPrice);
        return finalPrice;
    }
}
