// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

interface ILibraryBuilder {

    function getLibraryPool(address _token) external view returns (bool libraryExists, address libraryAddress);

    function getLibraryPool(
        address _tokenA, 
        address _tokenB
    ) external view returns (
        bool libraryExistsA, 
        address libraryAddressA,
        bool libraryExistsB, 
        address libraryAddressB
    );
}

