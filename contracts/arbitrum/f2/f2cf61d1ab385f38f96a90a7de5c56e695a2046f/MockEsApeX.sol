// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./EsAPEX.sol";

contract MockEsApeX is EsAPEX {
    constructor(address _stakingPoolFactory) EsAPEX(_stakingPoolFactory) {}

    function setFactory(address f) external {
        _addOperator(f);
    }
}

