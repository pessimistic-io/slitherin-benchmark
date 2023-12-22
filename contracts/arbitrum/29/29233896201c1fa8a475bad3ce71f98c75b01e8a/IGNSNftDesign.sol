// SPDX-License-Identifier: MIT
import "./IGToken.sol";

pragma solidity 0.8.17;

interface IGNSNftDesign{
    function buildTokenURI(uint nftType, uint tokenId) external pure returns (string memory);
}
