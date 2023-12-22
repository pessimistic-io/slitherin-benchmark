// SPDX-License-Identifier: MIT LICENSE
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./OwnableUpgradeable.sol";
import "./StringsUpgradeable.sol";
import "./ITraits.sol";
import "./TraitsBase.sol";
import "./IPeekABoo.sol";

contract Traits is Initializable, ITraits, OwnableUpgradeable, TraitsBase {
    using StringsUpgradeable for uint256;

    function initialize(address _peekaboo) public initializer {
        __Ownable_init();
        peekaboo = IPeekABoo(_peekaboo);
    }

    /** ADMIN */
    /**
     * administrative to upload the names and images associated with each trait
     * @param ghostOrBuster 0 if ghost, 1 if buster
     * @param traitType the trait type to upload the traits for (see traitTypes for a mapping)
     * @param traits the names and base64 encoded PNGs for each trait
     */
    function uploadTraits(
        uint256 ghostOrBuster,
        uint256 traitType,
        uint256[] calldata traitIds,
        Trait[] calldata traits
    ) external onlyOwner {
        require(traitIds.length == traits.length, "Mismatched inputs");
        for (uint256 i = 0; i < traits.length; i++) {
            traitData[ghostOrBuster][traitType][traitIds[i]] = Trait(
                traits[i].name,
                traits[i].svg
            );
        }
    }

    function setPeekABoo(address _peekaboo) external onlyOwner {
        peekaboo = IPeekABoo(_peekaboo);
    }

    /** RENDER */
    function drawSVG(
        uint256 tokenId,
        uint256 width,
        uint256 height
    ) public view returns (string memory) {
        IPeekABoo.PeekABooTraits memory _peekaboo = peekaboo.getTokenTraits(
            tokenId
        );
        uint8 peekabooType = _peekaboo.isGhost ? 0 : 1;

        string memory svgString = string(
            abi.encodePacked(
                (traitData[0][0][_peekaboo.background]).svg,
                (traitData[peekabooType][1][_peekaboo.back]).svg,
                (traitData[peekabooType][2][_peekaboo.bodyColor]).svg,
                _peekaboo.isGhost
                    ? (traitData[peekabooType][3][_peekaboo.clothesOrHelmet])
                        .svg
                    : (traitData[peekabooType][3][_peekaboo.hat]).svg,
                _peekaboo.isGhost
                    ? (traitData[peekabooType][4][_peekaboo.hat]).svg
                    : (traitData[peekabooType][4][_peekaboo.face]).svg,
                _peekaboo.isGhost
                    ? (traitData[peekabooType][5][_peekaboo.face]).svg
                    : (traitData[peekabooType][5][_peekaboo.clothesOrHelmet])
                        .svg,
                _peekaboo.isGhost
                    ? (traitData[peekabooType][6][_peekaboo.hands]).svg
                    : ""
            )
        );

        return
            string(
                abi.encodePacked(
                    '<svg width="100%"',
                    ' height="100%" viewBox="0 0 100 100"',
                    ">",
                    svgString,
                    "</svg>"
                )
            );
    }

    function tryOutTraits(
        uint256 tokenId,
        uint256[2][] memory traitsToTry,
        uint256 width,
        uint256 height
    ) external view returns (string memory) {
        IPeekABoo.PeekABooTraits memory _peekaboo = peekaboo.getTokenTraits(
            tokenId
        );
        uint8 peekabooType = _peekaboo.isGhost ? 0 : 1;
        require(traitsToTry.length <= 7, "Trying too many traits");

        string[7] memory traits = [
            (traitData[0][0][_peekaboo.background]).svg,
            (traitData[peekabooType][1][_peekaboo.back]).svg,
            (traitData[peekabooType][2][_peekaboo.bodyColor]).svg,
            _peekaboo.isGhost
                ? (traitData[peekabooType][3][_peekaboo.clothesOrHelmet]).svg
                : (traitData[peekabooType][3][_peekaboo.hat]).svg,
            _peekaboo.isGhost
                ? (traitData[peekabooType][4][_peekaboo.hat]).svg
                : (traitData[peekabooType][4][_peekaboo.face]).svg,
            _peekaboo.isGhost
                ? (traitData[peekabooType][5][_peekaboo.face]).svg
                : (traitData[peekabooType][5][_peekaboo.clothesOrHelmet]).svg,
            _peekaboo.isGhost
                ? (traitData[peekabooType][6][_peekaboo.hands]).svg
                : ""
        ];

        for (uint256 i = 0; i < traitsToTry.length; i++) {
            if (traitsToTry[i][0] == 0) {
                traits[0] = (traitData[0][0][traitsToTry[i][1]]).svg;
            } else if (traitsToTry[i][0] == 1) {
                traits[1] = (traitData[peekabooType][1][traitsToTry[i][1]]).svg;
            } else if (traitsToTry[i][0] == 2) {
                traits[2] = (traitData[peekabooType][2][traitsToTry[i][1]]).svg;
            } else if (traitsToTry[i][0] == 3) {
                traits[3] = (traitData[peekabooType][3][traitsToTry[i][1]]).svg;
            } else if (traitsToTry[i][0] == 4) {
                traits[4] = (traitData[peekabooType][4][traitsToTry[i][1]]).svg;
            } else if (traitsToTry[i][0] == 5) {
                traits[5] = (traitData[peekabooType][5][traitsToTry[i][1]]).svg;
            } else if (traitsToTry[i][0] == 6) {
                traits[6] = (traitData[peekabooType][6][traitsToTry[i][1]]).svg;
            }
        }

        string memory svgString = string(
            abi.encodePacked(
                traits[0],
                traits[1],
                traits[2],
                traits[3],
                traits[4],
                traits[5],
                _peekaboo.isGhost ? traits[6] : ""
            )
        );

        return
            string(
                abi.encodePacked(
                    '<svg width="100%"',
                    // Strings.toString(width),
                    ' height="100%" viewBox="0 0 100 100"',
                    // Strings.toString(height),
                    ">",
                    svgString,
                    "</svg>"
                )
            );
    }

    function attributeForTypeAndValue(
        string memory traitType,
        string memory value
    ) internal pure returns (string memory) {
        return
            string(
                abi.encodePacked(
                    '{"trait_type":"',
                    traitType,
                    '","value":"',
                    value,
                    '"}'
                )
            );
    }

    function attributeForTypeAndValue(string memory traitType, uint64 value)
        internal
        pure
        returns (string memory)
    {
        return
            string(
                abi.encodePacked(
                    '{"trait_type":"',
                    traitType,
                    '","value":"',
                    uint256(value).toString(),
                    '"}'
                )
            );
    }

    function compileAttributes(uint256 tokenId)
        public
        view
        returns (string memory)
    {
        IPeekABoo.PeekABooTraits memory attr = peekaboo.getTokenTraits(tokenId);

        string memory traits;
        if (attr.isGhost) {
            traits = string(
                abi.encodePacked(
                    attributeForTypeAndValue(
                        "Background",
                        traitData[0][0][attr.background].name
                    ),
                    ",",
                    attributeForTypeAndValue(
                        "Back",
                        traitData[0][1][attr.back].name
                    ),
                    ",",
                    attributeForTypeAndValue(
                        "BodyColor",
                        traitData[0][2][attr.bodyColor].name
                    ),
                    ",",
                    attributeForTypeAndValue(
                        "Clothes",
                        traitData[0][3][attr.clothesOrHelmet].name
                    ),
                    ",",
                    attributeForTypeAndValue(
                        "Hat",
                        traitData[0][4][attr.hat].name
                    ),
                    ",",
                    attributeForTypeAndValue(
                        "Face",
                        traitData[0][5][attr.face].name
                    ),
                    ",",
                    attributeForTypeAndValue(
                        "Hands",
                        traitData[0][6][attr.hands].name
                    ),
                    ",",
                    attributeForTypeAndValue("Tier", attr.tier),
                    ",",
                    attributeForTypeAndValue("Level", attr.level)
                )
            );
        } else {
            traits = string(
                abi.encodePacked(
                    attributeForTypeAndValue(
                        "Background",
                        traitData[0][0][attr.background].name
                    ),
                    ",",
                    attributeForTypeAndValue(
                        "Back",
                        traitData[1][1][attr.back].name
                    ),
                    ",",
                    attributeForTypeAndValue(
                        "BodyColor",
                        traitData[1][2][attr.bodyColor].name
                    ),
                    ",",
                    attributeForTypeAndValue(
                        "Hat",
                        traitData[1][3][attr.hat].name
                    ),
                    ",",
                    attributeForTypeAndValue(
                        "Face",
                        traitData[1][4][attr.face].name
                    ),
                    ",",
                    attributeForTypeAndValue(
                        "Helmet",
                        traitData[1][5][attr.clothesOrHelmet].name
                    ),
                    ",",
                    attributeForTypeAndValue("Tier", attr.tier),
                    ",",
                    attributeForTypeAndValue("Level", attr.level)
                )
            );
        }
        return
            string(
                abi.encodePacked(
                    "[",
                    traits,
                    '{"trait_type":"Type","value":',
                    attr.isGhost ? '"Ghost"' : '"Buster"',
                    "}]"
                )
            );
    }

    function compileAttributesAsIDs(uint256 tokenId)
        external
        view
        returns (string memory)
    {
        IPeekABoo.PeekABooTraits memory attr = peekaboo.getTokenTraits(tokenId);

        string memory traits;
        if (attr.isGhost) {
            traits = string(
                abi.encodePacked(
                    attributeForTypeAndValue(
                        "Background",
                        attr.background.toString()
                    ),
                    ",",
                    attributeForTypeAndValue("Back", attr.back.toString()),
                    ",",
                    attributeForTypeAndValue(
                        "BodyColor",
                        attr.bodyColor.toString()
                    ),
                    ",",
                    attributeForTypeAndValue(
                        "Clothes",
                        attr.clothesOrHelmet.toString()
                    ),
                    ",",
                    attributeForTypeAndValue("Hat", attr.hat.toString()),
                    ",",
                    attributeForTypeAndValue("Face", attr.face.toString()),
                    ",",
                    attributeForTypeAndValue("Hands", attr.hands.toString()),
                    ","
                )
            );
        } else {
            traits = string(
                abi.encodePacked(
                    attributeForTypeAndValue(
                        "Background",
                        attr.background.toString()
                    ),
                    ",",
                    attributeForTypeAndValue("Back", attr.back.toString()),
                    ",",
                    attributeForTypeAndValue(
                        "BodyColor",
                        attr.bodyColor.toString()
                    ),
                    ",",
                    attributeForTypeAndValue("Hat", attr.hat.toString()),
                    ",",
                    attributeForTypeAndValue("Face", attr.face.toString()),
                    ",",
                    attributeForTypeAndValue(
                        "Helmet",
                        attr.clothesOrHelmet.toString()
                    ),
                    ","
                )
            );
        }
        return
            string(
                abi.encodePacked(
                    "[",
                    traits,
                    '{"trait_type":"Type","value":',
                    attr.isGhost ? '"Ghost"' : '"Buster"',
                    "}]"
                )
            );
    }

    function tokenURI(uint256 tokenId) external view returns (string memory) {
        IPeekABoo.PeekABooTraits memory attr = peekaboo.getTokenTraits(tokenId);

        string memory metadata = string(
            abi.encodePacked(
                '{"name": "',
                attr.isGhost ? "Ghost #" : "Buster #",
                tokenId.toString(),
                '", "description": "Ghosts have come out to haunt the metaverse as the night awakes, Busters scramble to purge these ghosts and claim the bounties. Ghosts are accumulating $BOO, amassing it to grow their haunted grounds. All the metadata and images are generated and stored 100% on-chain. No IPFS. NO API. The project is built on the Arbitrum L2.", "image": "data:image/svg+xml;base64,',
                bytes(drawSVG(tokenId, 512, 512)),
                '", "attributes":',
                compileAttributes(tokenId),
                "}"
            )
        );

        return
            string(
                abi.encodePacked(
                    "data:application/json;base64,",
                    bytes(metadata)
                )
            );
    }

    function setRarityIndex(
        uint256 ghostOrBuster,
        uint256 traitType,
        uint256[4] calldata traitIndices
    ) external onlyOwner {
        for (uint256 i = 0; i < 4; i++) {
            traitRarityIndex[ghostOrBuster][traitType][i] = traitIndices[i];
        }
    }

    function getRarityIndex(
        uint256 ghostOrBuster,
        uint256 traitType,
        uint256 rarity
    ) external returns (uint256) {
        return traitRarityIndex[ghostOrBuster][traitType][rarity];
    }
}

