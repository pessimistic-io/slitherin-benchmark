// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import "./IPayoffProvider.sol";

contract Kilo is IPayoffProvider {
    Fixed6 private constant MULTIPLICAND = Fixed6.wrap(1e9);

    function payoff(Fixed6 price) external pure override returns (Fixed6) {
        return price.mul(MULTIPLICAND);
    }
}

