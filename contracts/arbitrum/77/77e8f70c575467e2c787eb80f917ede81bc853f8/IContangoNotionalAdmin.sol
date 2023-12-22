//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface IContangoNotionalAdminEvents {
    event ProxyHashSet(bytes32 proxyHash);
}

interface IContangoNotionalAdmin is IContangoNotionalAdminEvents {
    function setProxyHash(bytes32 proxyHash) external;
}

