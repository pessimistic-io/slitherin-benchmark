// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

interface IVaultV2Simplify {
    function takeAssetOut(
        bytes32 _key,
        address _account, 
        uint256 _fee, 
        uint256 _usdOut, 
        address _token, 
        uint256 _tokenPrice
    ) external;
}
