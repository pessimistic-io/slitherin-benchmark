pragma solidity ^0.8.0;
// SPDX-License-Identifier: MIT

pragma experimental ABIEncoderV2;

import "./IERC721.sol";

interface ISecondLiveEditor is IERC721 {
    struct Attribute {
        uint256 rule; //
        uint256 quality; // type -> (Pink | Blue | island)
        uint256 format; // space -> (Person Space | island)
        uint256 extra; // level
    }

    function mint(
        address to,
        Attribute calldata attribute
    ) external returns (uint256);

    function setTokenRoyalty(
        uint256 tokenId,
        address receiver,
        uint96 feeNumerator
    ) external;

    function getAttribute(
        uint256 id
    ) external view returns (Attribute memory attribute);
}

