// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IGnosisSafeProxyFactory {
    function proxyCreationCode() external pure returns (bytes memory);
}

