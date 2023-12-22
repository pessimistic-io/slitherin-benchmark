// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import "./Math.sol";
import "./IPayoffProvider.sol";

contract PowerHalf is IPayoffProvider {
    uint256 private constant BASE = 1e6;

    function payoff(Fixed6 price) external pure override returns (Fixed6) {
        return Fixed6Lib.from(UFixed6.wrap(Math.sqrt(UFixed6.unwrap(price.abs()) * BASE)));
    }
}

