// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;


interface IERC20TokenRegistry {

    function addToken(address erc20Token) external;

    function removeToken(address erc20Token) external;

    function tokenInRegistry(address erc20Token) view external returns (bool);

    function setTokenLimit(address _token, uint256 _tokenLimit) external;

    function getTokenLimit(address _token) view external  returns (uint256);

}

