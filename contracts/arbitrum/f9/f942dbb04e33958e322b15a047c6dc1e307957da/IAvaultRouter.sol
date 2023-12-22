// SPDX-License-Identifier: GLP-v3.0

pragma solidity ^0.8.4;


interface IAvaultRouter{
    function SALT_NONCE() external view returns(uint);
    function computeSafeAddress(address _srcAddress) external pure returns (address _safeAddr, bytes memory _initializer);
}
