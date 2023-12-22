// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import { ProxyAdmin } from "./ProxyAdmin.sol";

contract CoinBookProxyAdmin is ProxyAdmin {
    constructor(address _multiSig) {
        _transferOwnership(_multiSig);
    }
}

