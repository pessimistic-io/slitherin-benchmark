// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;
interface IChildChainManager {
    event TokenMapped(address indexed rootToken, address indexed childToken);

    function mapToken(address rootToken, address childToken) external;
    function cleanMapToken(address rootToken, address childToken) external;
}

