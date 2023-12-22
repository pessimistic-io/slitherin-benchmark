// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "./OwnableUpgradeable.sol";
import "./IBridgeworldLegion.sol";
import "./ILegion.sol";
import "./ILegionMetadataStore.sol";

error ContractsNotSet();

contract VerifyLegionGenesis is OwnableUpgradeable {
    ILegionMetadataStore public metadata;
    IBridgeworldLegion public atlas;
    IBridgeworldLegion public crafting;
    IBridgeworldLegion public questing;
    IBridgeworldLegion public summoning;
    ILegion public legion;

    function initialize() external initializer {
        __Ownable_init();
    }

    function balanceOf(address owner) external view returns (uint256 balance) {
        balance += tokensToBalance(tokensInBridgeworld(atlas, owner));
        balance += tokensToBalance(tokensInBridgeworld(crafting, owner));
        balance += tokensToBalance(tokensInBridgeworld(questing, owner));
        balance += tokensToBalance(tokensInBridgeworld(summoning, owner));
        balance += tokensToBalance(tokensInWallet(owner));
    }

    function setContracts(
        address metadata_,
        address atlas_,
        address crafting_,
        address questing_,
        address summoning_,
        address legion_
    ) external onlyOwner {
        metadata = ILegionMetadataStore(metadata_);
        atlas = IBridgeworldLegion(atlas_);
        crafting = IBridgeworldLegion(crafting_);
        questing = IBridgeworldLegion(questing_);
        summoning = IBridgeworldLegion(summoning_);
        legion = ILegion(legion_);
    }

    modifier contractsAreSet() {
        if (!areContractsSet()) {
            revert ContractsNotSet();
        }

        _;
    }

    function areContractsSet() public view returns (bool) {
        return
            address(metadata) != address(0) &&
            address(atlas) != address(0) &&
            address(crafting) != address(0) &&
            address(questing) != address(0) &&
            address(summoning) != address(0) &&
            address(legion) != address(0);
    }

    function tokensToBalance(uint256[] memory tokenIds)
        internal
        view
        returns (uint256 balance)
    {
        uint256 length = tokenIds.length;

        for (uint256 index = 0; index < length; index++) {
            LegionMetadata memory _metadata = metadata.metadataForLegion(
                tokenIds[index]
            );

            if (_metadata.legionGeneration == LegionGeneration.GENESIS) {
                balance++;
            }
        }
    }

    function tokensInWallet(address owner)
        internal
        view
        returns (uint256[] memory)
    {
        uint256 balance = legion.balanceOf(owner);
        uint256[] memory tokenIds = new uint256[](balance);

        for (uint256 index = 0; index < balance; index++) {
            tokenIds[index] = legion.tokenOfOwnerByIndex(owner, index);
        }

        return tokenIds;
    }

    function tokensInBridgeworld(IBridgeworldLegion bridgeworld, address owner)
        internal
        view
        returns (uint256[] memory)
    {
        return bridgeworld.getStakedLegions(owner);
    }
}

