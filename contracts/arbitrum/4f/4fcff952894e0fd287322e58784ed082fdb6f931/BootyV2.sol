// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "./Ownable.sol";
import "./Strings.sol";
import "./ERC1155.sol";

error ARRAY_LENGTH_MISMATCH();
error CRAFTING_DISABLED();
error INVALID_ARTIFACT_ID();
error INVALID_CRAFTING_RECIPE();
error MINT_NOT_POSSIBLE();
error ONLY_EOA_CAN_OPEN_CRATE();
error INVALID_CRATE_ID();

contract BootyV2 is ERC1155, Ownable {
    uint256 public constant RARITY_PRECISION = 10000; // Decimal precision of rarity table = 100 / RARITY_PRECISION

    address public immutable oldContract;
    address public random;

    struct Recipe {
        bool active;
        uint256[] inputIDs;
        uint256[] inputQuantities;
        uint256[] outputIDs;
        uint256[] outputQuantities;
    }

    mapping(address => mapping(uint256 => uint256)) public activated;
    Recipe[] public recipes;
    mapping(uint256 => uint256[]) public crateRarities;

    event OpenCrate(address opener, uint256[] tiers, uint256[] amounts);
    event ActivateArtifact(address activator, uint256[] ids, uint256[] amounts);
    event CraftArtifact(address crafter, uint256[] ids, uint256[] amounts);

    constructor(
        string memory _uri,
        address _oldContract
    ) ERC1155(_uri) Ownable(msg.sender) {
        oldContract = _oldContract;
    }

    function migrate(
        uint256[] calldata ids,
        uint256[] calldata amounts
    ) public {
        if (ids.length != amounts.length) revert ARRAY_LENGTH_MISMATCH();

        ERC1155(oldContract).safeBatchTransferFrom(
            msg.sender,
            address(0x000000000000000000000000000000000000dEaD),
            ids,
            amounts,
            ""
        );
        _mintBatch(msg.sender, ids, amounts, "");
    }

    function ownerMint(uint256 id, uint256 amount) public onlyOwner {
        _mint(msg.sender, id, amount, "");
    }

    function openCrate(
        uint256[] calldata crateIDs,
        uint256[] calldata amounts
    ) public {
        if (msg.sender != tx.origin) revert ONLY_EOA_CAN_OPEN_CRATE();
        if (crateIDs.length != amounts.length) revert ARRAY_LENGTH_MISMATCH();

        _burnBatch(msg.sender, crateIDs, amounts);

        for (uint256 i = 0; i < crateIDs.length; ) {
            uint256[] memory artifactAmounts = revealArtifacts(
                crateIDs[i],
                amounts[i]
            );

            for (uint256 j = 0; j < artifactAmounts.length; ) {
                if (artifactAmounts[j] > 0) {
                    _mint(msg.sender, j, artifactAmounts[j], "");
                }
                unchecked {
                    ++j;
                }
            }

            unchecked {
                ++i;
            }
        }

        emit OpenCrate(msg.sender, crateIDs, amounts);
    }

    function activateArtifact(
        uint256[] calldata artifactIDs,
        uint256[] calldata amounts
    ) public {
        if (artifactIDs.length != amounts.length)
            revert ARRAY_LENGTH_MISMATCH();

        for (uint256 i = 0; i < artifactIDs.length; ) {
            if (crateRarities[artifactIDs[i]].length > 0)
                revert INVALID_ARTIFACT_ID();
            activated[msg.sender][artifactIDs[i]] += amounts[i];
            unchecked {
                ++i;
            }
        }

        _burnBatch(msg.sender, artifactIDs, amounts);

        emit ActivateArtifact(msg.sender, artifactIDs, amounts);
    }

    function craftArtifact(
        uint256[] calldata recipeIDs,
        uint256[] calldata amounts
    ) public {
        if (recipeIDs.length != amounts.length) revert ARRAY_LENGTH_MISMATCH();

        Recipe storage recipe;

        for (uint256 i = 0; i < recipeIDs.length; ) {
            recipe = recipes[recipeIDs[i]];
            if (!recipe.active) revert INVALID_CRAFTING_RECIPE();
            for (uint256 j = 0; j < recipe.inputIDs.length; ) {
                _burn(
                    msg.sender,
                    recipe.inputIDs[j],
                    recipe.inputQuantities[j] * amounts[i]
                );
                unchecked {
                    ++j;
                }
            }
            for (uint256 j = 0; j < recipe.outputIDs.length; ) {
                _mint(
                    msg.sender,
                    recipe.outputIDs[j],
                    recipe.outputQuantities[j] * amounts[i],
                    ""
                );
                unchecked {
                    ++j;
                }
            }
            unchecked {
                ++i;
            }
        }

        emit CraftArtifact(msg.sender, recipeIDs, amounts);
    }

    function setRandom(address _random) external onlyOwner {
        random = _random;
    }

    function setCrateRarity(
        uint256 crateID,
        uint256[] calldata rarity
    ) external onlyOwner {
        crateRarities[crateID] = rarity;
    }

    function setRecipe(
        uint256[] calldata inputIDs,
        uint256[] calldata inputQuantities,
        uint256[] calldata outputIDs,
        uint256[] calldata outputQuantities
    ) external onlyOwner {
        if (inputIDs.length != inputQuantities.length)
            revert ARRAY_LENGTH_MISMATCH();
        if (outputIDs.length != outputQuantities.length)
            revert ARRAY_LENGTH_MISMATCH();

        recipes.push(
            Recipe(true, inputIDs, inputQuantities, outputIDs, outputQuantities)
        );
    }

    function setRecipeStatus(uint256 recipeID, bool active) external onlyOwner {
        recipes[recipeID].active = active;
    }

    function getRecipe(
        uint256 index
    ) public view returns (
        bool,
        uint256[] memory,
        uint256[] memory,
        uint256[] memory,
        uint256[] memory
    ) {
        require(index < recipes.length, "Recipe index out of bounds");

        Recipe storage recipe = recipes[index];
        return (
            recipe.active,
            recipe.inputIDs,
            recipe.inputQuantities,
            recipe.outputIDs,
            recipe.outputQuantities
        );
    }

    function revealArtifacts(
        uint256 crateID,
        uint256 amount
    ) private returns (uint256[] memory artifactAmounts) {
        uint256 rarityLength = crateRarities[crateID].length;
        if (rarityLength == 0) revert INVALID_CRATE_ID();

        artifactAmounts = new uint256[](rarityLength);

        uint256 seed;

        for (uint i = 0; i < amount; ) {
            seed = IRandom(random).random() % RARITY_PRECISION;

            for (uint256 j = 0; j < rarityLength; ) {
                if (seed < crateRarities[crateID][j]) {
                    artifactAmounts[j]++;
                    break;
                }
                unchecked {
                    ++j;
                }
            }

            unchecked {
                ++i;
            }
        }
    }

    function uri(uint256 _id) public view override returns (string memory) {
        return string(abi.encodePacked(super.uri(_id), Strings.toString(_id)));
    }
}

interface IRandom {
    function random() external returns (uint256);
}

