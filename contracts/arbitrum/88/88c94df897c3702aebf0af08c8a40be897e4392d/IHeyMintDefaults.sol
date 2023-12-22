// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface IHeyMintDefaults {
    function getCreditCardDefaultAddresses()
        external
        view
        returns (address[] memory);
}

