// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.20;

interface ITokenDescriptor {
    function constructMetadata(
        uint256 id
    ) external view returns (string memory);

    function getName(uint256 id) external view returns (string memory);

    function getSymbol(uint256 id) external view returns (string memory);

    function getDecimals(uint256 id) external view returns (uint8);
}

