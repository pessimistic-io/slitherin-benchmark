// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {StringsUpgradeable} from "./StringsUpgradeable.sol";
import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";
import {ERC1155Upgradeable} from "./ERC1155Upgradeable.sol";
import {ERC1155SupplyUpgradeable} from "./ERC1155SupplyUpgradeable.sol";

// error
error InvalidTokenId();
error LengthsNotEqual();
error AboveTheMaxSupply();

/**
 * @title SmolAgeAnimals
 */

contract SmolAgeAnimals is ERC1155SupplyUpgradeable, OwnableUpgradeable {
    using StringsUpgradeable for uint256;
    string private baseUri;

    uint256 public constant MAX_SUPPLY_BABY_DINO = 268; // tokenId - 0
    uint256 public constant MAX_SUPPLY_WOLF = 224; // tokenId - 1
    uint256 public constant MAX_SUPPLY_SABERTOOTH = 173; // tokenId - 2
    uint256 public constant MAX_SUPPLY_TREX = 117; // tokenId - 3
    uint256 public constant MAX_SUPPLY_MAMMOTH = 8; // tokenId - 4 //
    uint256 public constant MAX_SUPPLY_WHALE = 5; // tokenId - 5

    function initialize(string memory _uri) external initializer {
        baseUri = _uri;
        __ERC1155_init(_uri);
        __Ownable_init();
    }

    function airdrop(
        uint256 tokenId,
        address[] calldata receiver,
        uint256[] calldata amount
    ) external onlyOwner {
        if (tokenId > 5) revert InvalidTokenId();
        if (amount.length != receiver.length) revert LengthsNotEqual();
        uint256 i;
        for (; i < receiver.length; ) {
            if (!validateTotalSupply(tokenId, amount[i]))
                revert AboveTheMaxSupply();
            _mint(receiver[i], tokenId, amount[i], "");
            unchecked {
                ++i;
            }
        }
    }

    function name() external pure returns (string memory) {
        return "Smol Age Animals";
    }

    function symbol() external pure returns (string memory) {
        return "SAA";
    }

    function validateTotalSupply(uint256 id, uint256 amount)
        private
        view
        returns (bool)
    {
        uint256 ts = totalSupply(id);
        uint256 max;
        if (id == 0) max = MAX_SUPPLY_BABY_DINO;
        if (id == 1) max = MAX_SUPPLY_WOLF;
        if (id == 2) max = MAX_SUPPLY_SABERTOOTH;
        if (id == 3) max = MAX_SUPPLY_TREX;
        if (id == 4) max = MAX_SUPPLY_MAMMOTH;
        if (id == 5) max = MAX_SUPPLY_WHALE;

        return ts + amount <= max;
    }

    function uri(uint256 tokenId) public view override returns (string memory) {
        if (!exists(tokenId)) revert InvalidTokenId();
        return
            bytes(baseUri).length > 0
                ? string.concat(baseUri, tokenId.toString())
                : "";
    }
}

