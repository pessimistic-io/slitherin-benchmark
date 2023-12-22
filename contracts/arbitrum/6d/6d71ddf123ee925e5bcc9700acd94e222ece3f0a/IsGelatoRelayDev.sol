// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {     DEV_GELATO_RELAY,     DEV_GELATO_RELAY_ERC2771,     DEV_GELATO_RELAY_ZKSYNC,     DEV_GELATO_RELAY_ERC2771_ZKSYNC } from "./Addresses.sol";

function _isGelatoRelayDev(address _forwarder) view returns (bool) {
    return _forwarder == _getGelatoRelayDev();
}

function _isGelatoRelayERC2771Dev(address _forwarder) view returns (bool) {
    return _forwarder == _getGelatoRelayERC2771Dev();
}

function _getGelatoRelayDev() view returns (address) {
    return
        block.chainid == 324 || block.chainid == 280
            ? DEV_GELATO_RELAY_ZKSYNC
            : DEV_GELATO_RELAY;
}

function _getGelatoRelayERC2771Dev() view returns (address) {
    return
        block.chainid == 324 || block.chainid == 280
            ? DEV_GELATO_RELAY_ERC2771_ZKSYNC
            : DEV_GELATO_RELAY_ERC2771;
}

