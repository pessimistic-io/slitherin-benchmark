// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

//   _  _ _  _ _  _  _  _
//  | || | || | || \| || |
//  n_|||U || U || \\ || |
// \__/|___||___||_|\_||_|

import "./ReentrancyGuardUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./Initializable.sol";
import "./ERC1155Upgradeable.sol";

abstract contract QuestReward {
    // QuestReward contract must implement this function
    // to is used for mint destination
    // zodiaTokenId is used for pulling zodia metadata
    function claimQuestReward(
        address to,
        uint256 zodiaTokenId
    ) external virtual;
}

// Soulbound ERC1155 tickets
contract JuuniRewardTicket is
    ERC1155Upgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    QuestReward
{
    address public zodiaAddress;
    string private _tokenUri;

    error Soulbound();
    error InvalidMintSource();

    function initialize() public initializer {
        __ERC1155_init("");
        __Ownable_init();
        __ReentrancyGuard_init();
    }

    function claimQuestReward(
        address to,
        uint256 zodiaTokenId
    ) external override nonReentrant {
        if (msg.sender != zodiaAddress) revert InvalidMintSource();

        _mint(to, 1, 1, "");
    }

    function setZodiaContract(address newZodiaAddress) external onlyOwner {
        zodiaAddress = newZodiaAddress;
    }

    function setApprovalForAll(
        address operator,
        bool approved
    ) public override {
        revert Soulbound();
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        uint256 amount,
        bytes memory data
    ) public override {
        revert Soulbound();
    }

    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) public override {
        revert Soulbound();
    }

    function uri(uint256) public view virtual override returns (string memory) {
        return _tokenUri;
    }

    function setBaseURI(string calldata tokenUri_) external onlyOwner {
        _tokenUri = tokenUri_;
    }
}

