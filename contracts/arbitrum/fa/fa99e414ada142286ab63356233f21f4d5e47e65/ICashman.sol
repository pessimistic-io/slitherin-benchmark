// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface ICashman {
    function addMintable(address token) external;
    function removeMintable(address token) external;
    function isMintable(address token) external view returns (bool);

    function transferTo(
        address token,
        address to,
        uint256 amount
    ) external returns (bool success);
}

