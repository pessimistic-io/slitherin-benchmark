// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IBlueChipWhitelist {
    function getBlueChipFloorPrice(uint64 originChain, address nft) external view returns (uint256);

    function bulletBought(address hunter, address game) external view returns (uint64);

    function toleratePriceRate() external view returns (uint8);

    function tolerateBulletRate() external view returns (uint8);
}

