// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./extensions_IERC721EnumerableUpgradeable.sol";

interface IFriendTechReward is IERC721EnumerableUpgradeable {
    event Minted(
        address indexed receiver,
        uint256 indexed tokenId
    );

    error UnexistingToken(uint256 tokenId);
    error IncorrectArrayLength();
    error TransferNotAllowed(address from, address to, uint256 firstTokenId);
    error AccessDenied();
    error InvalidAddress(address account);

    function setMetadataURLOfType(string[] calldata metadata, uint256[] calldata types) external;

    function getMetadataURLOfType(uint256 tokenType) external view returns(string memory);

    function mint(address[] calldata receivers, uint256[] calldata types) external;

    function currentId() external view returns (uint256);
}

