// SPDX-License-Identifier: LIC
pragma solidity 0.8.18;

//import "@layerzerolabs/solidity-examples/contracts/token/oft/extension/ProxyOFT.sol";
import "./ProxyOFT.sol";

contract Proxy is ProxyOFT {
    constructor(
        address _lzEndpoint,
        address _token
    ) ProxyOFT(_lzEndpoint, _token) {}
}
