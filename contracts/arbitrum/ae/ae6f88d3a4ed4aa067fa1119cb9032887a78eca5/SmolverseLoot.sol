//SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {Initializable} from "./Initializable.sol";
import {ERC721Upgradeable} from "./ERC721Upgradeable.sol";
import {IERC721} from "./IERC721.sol";
import {IERC20} from "./IERC20.sol";
import {AccessControlEnumerableUpgradeable} from "./AccessControlEnumerableUpgradeable.sol";
import {ISmolChopShop} from "./ISmolChopShop.sol";

import {SmolverseLootAdmin} from "./SmolverseLootAdmin.sol";
import {ISmolTreasures} from "./ISmolTreasures.sol";

import {MerkleProof} from "./MerkleProof.sol";

import {SmolsLibrary, Smol} from "./SmolsLibrary.sol";

interface ISmolsState{
    function getSmol(uint256 tokenId) external view returns (Smol memory);
}

/*
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&PPPPPPPPPPPPPPPPP55PPP5YJ~^J@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@#GGBBGYYYYYYYYYYYYYYYYJJJYYYJJ?^^7GG5JJ#@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@PJJYYYYYYJJJJJJJJJJJJJJJJJJJJJJ?????^  G@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@PJJYYYYYYJJJJJJJJJJJJJJ??JJJJJJ?????^  G@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@PJJYYYYYYJJJJJJ??JJJJJJJJJJJJJJ?????^  G@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@PJJYYYYYYJJJJJJJJJJJJJJJJJJJJJJ?????^  G@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@PJJYYYYYYJJJJJJJJJJJJJJJJJ??JJJ?????^  G@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@PJJYYYYYY??JJJJJJJJJJJJJJJJJJJJ?????^  G@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@PJJYYYYYYJJJJJ555?7?PPY77JYJJJJ?????^  G@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@PJJYYYYYYJJY555P5YYYJJJYYJ??JJJ?????^  G@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@PJJYYYYYYJJ5PPPPPPP577?YY?77JJJ?????^  G@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@PJJYYYYYYJJY55PPP55Y77777777JJJ?????^  G@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@PJJYYYYYYJJJJJ5P5?7?JJJJJJJJJJJ?????^  G@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@PJJYYYYYY??JJJYYYJJJJJJJJJ?JJJJ?????^  G@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@PJJYYYYYYJJJJJJJJJJJJJJJJJJJJJJ?????^  G@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@PJJYYYYYYJJJJJJJJJJJJJJJJJJJJJJ?????^  G@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@PJJYYYYYYJJJJJJJJ???JJJJJJJJJJJ?????^  G@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@PJJYYYYYYJJJJJJJJJJJJJJJJJJJJJJ?????^  G@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@PJJYYYYYYJJJJJJJJJJJJJJJJJJJJJJ?????^  G@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@PJJYYYYYYJJJJJJJJJJY55555555555YYYYY!..B@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@PJYYYYYYYJJJJJYYYYYP@@@@@@@@@@@@@@@@P??#@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&&&&&5YYYYYJJJJJ#&&&@#??JJJJJJJJJJJJ??G&&&&&@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@G5PB#BBBBBBBBBGGGP5PPPY7777777777JPPP55#&&@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@#PG?!!B##########5YY77J@@P7777777777Y@@5!7B@&@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@&@5:^^^^JYYYYYYYYYYYYY77J&@P7777777777Y@@577B&&@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@&@P!7~^^JYYYYYYYYYYYYY?7Y@@P77~^^^^~77Y@@577!~!#&&@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@&&GJJ7!!JYYYYYYYYYY7!!~~!??7~~^^^::^~~!??!^~^^~&@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@#PGY??YYYYYYYYJ??~^^^^^::^^^^^^?J?^^^::!JJ~^~5PG@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&&G55555YYYYY!:^^^^~~~^^^^^^^^B&B^^^^:Y&#7^^^:!&&@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&&&&&&&#YYYYY7^^^^~#&G^^^^^^^^^^^^^^^^^^^^^^^:7&&@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@B5PPPPPPP##GYY?!!!!7JY5GGGGGGGGGGGGGGGGGGGGGGGGB&&@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@&GBPYYYYYYYYBBGGGJ!777777?GGGGGGGGGGGGGGGGPPPPPG&@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@##BJJJJJJJJJJJYYP&&5??JJJ7777777777777777777?????J&&@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@&&&5YJ!!!!!!!!!!7YYYYYG&&&&#?777777777777777777P&&&&&@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@&?77!!!!!!!!!!!77777JP555PB##################G55#&&@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@P557!!!!!!!!!!!!!!!!!!7?????GGGGGGGGGGGGGGGGGGG5YY#&&@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@&&?!!!!!!!!!!!!!777!!!!!!!!!!!JJJJJYYYYYYYYYYYYYYYYY#&&@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@&&&J!!!!!!!!!!!!!YYY7!!!!!!!!!!!!!!!?YYYYYYYYYYYYYYYY#&&@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@&@57?7!!!!!!!!!!!!!B&#YY?!!!!!!!!!!!!!777777YYYYYP&&PYY555&&&@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@&@5!!!!!!!!!!!!!?JJ#@&YYYJJ7!!!!!!!!!!!!!?JJYYYYYP&&GYYYYY&&&@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@&@5!!!!!!!!!!!!!YPPBBBYYYYYJ7???????????7JYYYYYYYP&&GYYYYY&&&@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@&@5!!!!!!!!!!!!!G@&5YYYYYYYYYYYYYYYYYYYYYYYYYYYYYP&&GYYYYY&&&@@@@@@@@@@@@@@@@@@@@@@
*/

contract SmolverseLoot is Initializable, SmolverseLootAdmin, ERC721Upgradeable {
    function initialize() external initializer {
        SmolverseLootAdmin.__SmolverseLootAdmin_init();
    }

    function craftRainbowTreasures(
        RainbowTreasureCraftInput[] calldata _rainbowTreasureCraftInputs
    ) external whenNotPaused {
        for (uint256 craftInputIndex = 0; craftInputIndex < _rainbowTreasureCraftInputs.length; craftInputIndex++) {
            //Pull tokends from input
            uint256[] memory tokenIds = _rainbowTreasureCraftInputs[craftInputIndex].tokenIds;

            //Ensure they are using 15 tokens
            if (tokenIds.length != 15) revert InvalidCraft(_rainbowTreasureCraftInputs[craftInputIndex]);

            //Pull what type they want to craft with, shape or color
            bool isByShape = _rainbowTreasureCraftInputs[craftInputIndex].craftType == CraftType.BY_SHAPE;

            //Initialize the value to hold the current Id of the craft element
            uint8 current;

            for (uint256 tokenIndex = 0; tokenIndex < tokenIds.length; tokenIndex++) {
                //Pull the tokenId from this input
                uint256 tokenId = tokenIds[tokenIndex];

                //Only token owners can burn
                if (ownerOf(tokenId) != msg.sender) revert NotOwner(tokenId, msg.sender);

                //Pull LootToken into storage
                LootToken storage _lootToken = lootTokens[tokenId];

                //Pull the next tokens craft element ID (shape ID or color ID)
                uint8 next = isByShape ? loots[_lootToken.lootId].shape : loots[_lootToken.lootId].color;

                //If the current craft element ID is not defined, revert
                //If the current craft element ID and the next craft element ID are different, revert
                //This ensures that all 15 tokens are of the same craft element ID
                if (current != 0 && next != current) revert InvalidCraft(_rainbowTreasureCraftInputs[craftInputIndex]);
                
                //Store the current craft element ID as the next craft element
                current = next;
                
                //Burn this loot token, so it cannot be reused.
                _burn(tokenId);
            }
        }

        //Mint as many rainbow treasures as they crafted
        ISmolTreasures(treasuresAddress).mint(msg.sender, RAINBOW_TREASURE_ID, _rainbowTreasureCraftInputs.length);
    }

    function rerollLoots(uint256[] calldata _tokenIds) external whenNotPaused {
        for (uint256 index = 0; index < _tokenIds.length; index++) {
            //Pull the tokenId from this input
            uint256 tokenId = _tokenIds[index];

            //Pull LootToken into storage
            LootToken storage _lootToken = lootTokens[tokenId];

            //Ensure they own this token
            if (ownerOf(tokenId) != msg.sender) revert NotOwner(tokenId, msg.sender);

            //Regenerate this loot id, with the generate function
            _lootToken.lootId = generateRandomLootId(tokenId);

            //Emit reroll event
            emit LootTokenRerolled(tokenId, _lootToken);
        }

        //Transfer 1 magic for each reroll
        IERC20(magicAddress).transferFrom(msg.sender, address(this), 1 ether * _tokenIds.length);
    }

    function convertToLoot(LootConversionInput calldata _lootConversionInput) external whenNotPaused {
        //Start their loot count at zero.
        uint256 runningLootCount = 0;

        if (_lootConversionInput.smolCarIds.length > 0) {
            //If they would like to convert smol cars into loot.
            runningLootCount += burnSmolCarsAndGetLootCount(_lootConversionInput.smolCarIds);
        }
        if (_lootConversionInput.swolercycleIds.length > 0) {
            //If they would like to convert swolercycles to loot.
            runningLootCount += burnSwolercyclesAndGetLootCount(_lootConversionInput.swolercycleIds);
        }
        if (_lootConversionInput.treasureIds.length > 0) {
            //If they would like to convert treasures to loot.
            runningLootCount += burnTreasuresAndGetLootCount(
                _lootConversionInput.treasureIds,
                _lootConversionInput.treasureAmounts
            );
        }

        if (_lootConversionInput.smolTraitShopSkinCount > 0) {
            //They would like to convert skins to loot
            runningLootCount += redeemSkinsAndGetLootCount(
                _lootConversionInput.merkleProofsForSmolTraitShop,
                _lootConversionInput.smolTraitShopSkinCount
            );
        }

        if(_lootConversionInput.smolPetIds.length > 0) runningLootCount += burnSmolPetsAndGetLootCount(_lootConversionInput.smolPetIds);
        if(_lootConversionInput.swolPetIds.length > 0) runningLootCount += burnSwolPetsAndGetLootCount(_lootConversionInput.swolPetIds);

        if(_lootConversionInput.smolFemaleIds.length > 0) burnSmolFemalesAndMintRainbowTreasures(_lootConversionInput.smolFemaleIds);

        //Mint they running count
        mintLoots(msg.sender, runningLootCount);
    }

    function burnSmolCarsAndGetLootCount(uint256[] calldata _tokenIds) internal returns (uint256) {
        //Store their skincount
        uint256 skinCount;

        for(uint256 i = 0; i < _tokenIds.length; i++){
            //Pull how many upgrades this token
            uint256[] memory allUnlockedUpgrades = ISmolChopShop(smolChopShopAddress).getAllUnlockedUpgrades(smolCarsAddress, _tokenIds[i]);
            
            //Add that length to skinCount
            skinCount += allUnlockedUpgrades.length;
        }
        
        //Burn all of the tokens
        burnERC721(smolCarsAddress, _tokenIds);

        //10 loot per car, 3 loot per skin
        return (_tokenIds.length * 10) + (skinCount * 3);
    }

    function burnSwolercyclesAndGetLootCount(uint256[] calldata _tokenIds) internal returns (uint256) {
        //Store their skincount
        uint256 skinCount;

        for(uint256 i = 0; i < _tokenIds.length; i++){
            //Pull how many upgrades this token
            uint256[] memory allUnlockedUpgrades = ISmolChopShop(smolChopShopAddress).getAllUnlockedUpgrades(swolercyclesAddress, _tokenIds[i]);
            
            //Add that length to skinCount
            skinCount += allUnlockedUpgrades.length;
        }

        //Burn all of the tokens
        burnERC721(swolercyclesAddress, _tokenIds);

        //3 loot per swolercycle, 3 loot per skin
        return (_tokenIds.length * 3) + (skinCount * 3);
    }

    function burnTreasuresAndGetLootCount(
        uint256[] calldata _ids,
        uint256[] calldata _amounts
    ) internal returns (uint256) {
        //Store their lootCount
        uint256 lootCount;
        for (uint256 index = 0; index < _ids.length; index++) {
            uint256 treasureId = _ids[index];
            //If the treasureId is not 1-4, revert
            if (treasureId == 0 || treasureId > 5) revert InvalidTreasure(treasureId);

            //Burn the requested treasures
            ISmolTreasures(treasuresAddress).burn(msg.sender, treasureId, _amounts[index]);

            //If its a moon rock, add one loot per moon rock
            if (treasureId == 1) lootCount += _amounts[index] * 1; // Moon Rock
            //If its a stardust, add two loot per stardust
            if (treasureId == 2) lootCount += _amounts[index] * 2; // Stardust
            //If its a comet shard, add twelve loot per comet shard
            if (treasureId == 3) lootCount += _amounts[index] * 12; // Comet Shard
            //If its a lunar gold, add sixteen loot per lunar gold
            if (treasureId == 4) lootCount += _amounts[index] * 16; // Lunar Gold
            // Alien Relic
            if (treasureId == 5) {
                //Mint 40 rainbow treasures for each alien relic
                ISmolTreasures(treasuresAddress).mint(msg.sender, RAINBOW_TREASURE_ID, 40 * _amounts[index]);
            }
        }
        //Return the loot count
        return lootCount;
    }

    function redeemSkinsAndGetLootCount(
        bytes32[] calldata _merkleProofs,
        uint256 _skinCount
    ) internal returns (uint256) {
        //Make sure they haven't already claimed.
        if (hasClaimedSkinLoot[msg.sender]) revert UserHasAlreadyClaimedSkinLoot(msg.sender);

        //Store that they claimed
        hasClaimedSkinLoot[msg.sender] = true;

        //Make sure supplied info (address and count) is correct.
        if (
            !MerkleProof.verify(
                _merkleProofs,
                traitShopSkinsMerkleRoot,
                keccak256(abi.encodePacked(msg.sender, _skinCount))
            )
        ) revert UserIsNotInMerkleTree(msg.sender);

        //3 loots per skin
        return _skinCount * 3;
    }

    function burnSmolPetsAndGetLootCount(uint256[] calldata _tokenIds) internal returns (uint256) {
        burnERC721(smolPetsAddress, _tokenIds);
        return _tokenIds.length * 50;
    }

    function burnSwolPetsAndGetLootCount(uint256[] calldata _tokenIds) internal returns (uint256) {
        burnERC721(swolPetsAddress, _tokenIds);
        return _tokenIds.length * 25;
    }

    function burnSmolFemalesAndMintRainbowTreasures(uint256[] calldata _tokenIds) internal {
        for (uint256 index = 0; index < _tokenIds.length; index++) {
            Smol memory _thisSmol = ISmolsState(smolsStateAddress).getSmol(_tokenIds[index]);
            if(_thisSmol.gender != 2) revert SmolIsNotFemale(_tokenIds[index]);
        }

        ISmolTreasures(treasuresAddress).mint(msg.sender, RAINBOW_TREASURE_ID, 100 * _tokenIds.length);

        burnERC721(smolBrainsAddress, _tokenIds);
    }

    function burnERC721(address tokenAddress, uint256[] calldata _tokenIds) internal {
        for (uint256 index = 0; index < _tokenIds.length; index++) {
            //Transfer to dead address
            //Dont need to check owner, because contract will check owner.
            IERC721(tokenAddress).safeTransferFrom(msg.sender, DEAD_ADDRESS, _tokenIds[index], "");
        }
    }

    function mintLoots(address _user, uint256 _count) internal {

        if(_count > 1000){
            //Give them the modulo treatment
            
            //Rounding down, find how many rainbow loots to mint
            uint256 _totalRainbowLootToMint = _count / 15;

            //Using mod, find how many loots to mint
            uint256 _totalLootToMint = _count % 15;

            //Mint rainbow treasures
            ISmolTreasures(treasuresAddress).mint(msg.sender, RAINBOW_TREASURE_ID, _totalRainbowLootToMint);

            //Mint individual loots
            for (uint256 index = 0; index < _totalLootToMint; index++) {
                //Increment tokenIds to get this tokenId
                uint256 tokenId = ++tokenIds;
                
                //Store the metadata for this loot token, including the expiry
                lootTokens[tokenId] = LootToken(generateRandomLootId(tokenId), uint40(block.timestamp + 30 days));
                
                //Mint this token
                _safeMint(_user, tokenId);

                //Emit event
                emit LootTokenMinted(tokenId, lootTokens[tokenId]);
            }
            
        } else {
            //Mint individual loots
            for (uint256 index = 0; index < _count; index++) {
                //Increment tokenIds to get this tokenId
                uint256 tokenId = ++tokenIds;
                
                //Store the metadata for this loot token, including the expiry
                lootTokens[tokenId] = LootToken(generateRandomLootId(tokenId), uint40(block.timestamp + 30 days));
                
                //Mint this token
                _safeMint(_user, tokenId);

                //Emit event
                emit LootTokenMinted(tokenId, lootTokens[tokenId]);
            }
        }

    }

    function mintLootsAsAdmin(address _receiver, uint256 _count) external requiresRole(SMOL_LOOT_MINTER_ROLE) {
        //Admin func to arbitrarily mint loots (first called by transmolg claim)
        mintLoots(_receiver, _count);
    }

    // This function generates a pseudo-random number between the lootIds range.
    function generateRandomLootId(uint256 nonce) internal view returns (uint16) {
        //Generate a seed from the prev blockhash, the current timestamp, and the tokenId.
        uint256 seed = uint256(keccak256(abi.encodePacked(blockhash(block.number - 1), block.timestamp, nonce)));
        
        //Mod the seed by how many loot types exist.
        //For example, with 30 loots, and a random number of 534697348
        //The result is 28, then add 1 because loot IDs are 1 indexed.
        return uint16(1 + (seed % (lootIds - 1 + 1)));
    }

    function ownerOf(uint256 _tokenId) public view override returns (address) {
        //Call the previous ownerOf to get the current owner
        address owner = super.ownerOf(_tokenId);

        //If the owner is not the null address
        //and the token has expired, return null address
        if (owner != address(0) && lootTokens[_tokenId].expireAt < block.timestamp) return address(0);
        
        //Otherwise, return the owner.
        return owner;
    }

    function _beforeTokenTransfer(address _from, address _to, uint256 _tokenId) internal override {
        super._beforeTokenTransfer(_from, _to, _tokenId);

        // If the token is NOT being minted or burned
        // AND
        // The operator is NOT trove
        // revert

        if(_from == address(0) || _to == address(0)){
            //It is being minted or burned.
        } else {
            //It isn't being minted or burned.
            if(msg.sender != troveAddress) revert("No allowed transfers");
        }

        //If the token has expired, do not let them transfer
        if (lootTokens[_tokenId].expireAt < block.timestamp) revert NotOwner(_tokenId, _from);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(AccessControlEnumerableUpgradeable, ERC721Upgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    /// @dev Constructs and returns metadata for a loot.
    /// @param _tokenId The tokenId of the smol to return.
    /// @return loot The smol to return.
    function tokenURI(uint256 _tokenId) public override view returns (string memory) {
        require(_exists(_tokenId), "ERC721: operator query for nonexistent token");

        //Pull loot opject storage pointer.
        Loot storage _loot = loots[lootTokens[_tokenId].lootId];

        //Create and return the metadata object
        return
            string(
                abi.encodePacked( 
                    "data:application/json;base64,",
                    SmolsLibrary.encode(
                        abi.encodePacked(
                            '{"name": "',
                            abi.encodePacked(_loot.colorName, " ", _loot.shapeName),
                            '","description": "',
                            collectionDescription,
                            '","image": "',
                            baseURI,
                            SmolsLibrary.toString(lootTokens[_tokenId].lootId),
                            ".png"
                            '","attributes":',
                            abi.encodePacked(
                                "[",
                                abi.encodePacked('{"trait_type":"', "Color", '","value":"', _loot.colorName, '"}'),
                                ",",
                                //Load the Body
                                abi.encodePacked('{"trait_type":"', "Shape", '","value":"', _loot.shapeName, '"}'),
                                "]"
                            ),
                            "}"
                        )
                    )
                )
            );
    }

    function walletOfOwner(address _address)
        public
        view
        virtual
        returns (uint256[] memory)
    {
        //Thanks 0xinuarashi for da inspo
        uint256 _balance;

        for (uint256 i = 0; i < tokenIds; i++) {
            if (_exists(i) && ownerOf(i) == _address) _balance++;
        }

        uint256[] memory _tokens = new uint256[](_balance);
        uint256 _addedTokens;
        for (uint256 i = 0; i < tokenIds; i++) {
            if (_exists(i) && ownerOf(i) == _address) {
                _tokens[_addedTokens] = i;
                _addedTokens++;
            }

            if (_addedTokens == _balance) break;
        }
        return _tokens;
    }
}

