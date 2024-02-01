// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.15;

import "./IContractPayoffProvider.sol";

contract MilliSqueethPayoff is IContractPayoffProvider {
    function payoff(Fixed18 price) external pure override returns (Fixed18) {
        return price.mul(price).div(Fixed18Lib.from(1000));
    }
}

