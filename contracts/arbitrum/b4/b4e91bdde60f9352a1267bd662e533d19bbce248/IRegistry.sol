// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

interface IRegistry {
    event SignerUpdate(address signer, bool valid);

    function checkIsSigner(address addr) external view returns (bool);

    function getDegen() external view returns (address);

    function getPortal() external view returns (address);

    function getShovel() external view returns (address);

    function getPiggyBank() external view returns (address);
}

