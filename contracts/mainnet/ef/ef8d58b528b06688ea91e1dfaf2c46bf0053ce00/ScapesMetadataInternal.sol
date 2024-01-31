// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {Base64} from "./Base64.sol";
import {UintUtils} from "./UintUtils.sol";
import {ScapesMetadataStorage} from "./ScapesMetadataStorage.sol";
import {IScapesArchive} from "./IScapesArchive.sol";
import {ScapesMerge} from "./ScapesMerge.sol";
import {strings} from "./strings.sol";
import {ScapesERC721MetadataStorage} from "./ScapesERC721MetadataStorage.sol";

/// @title ScapesMetadataInternal
/// @author akuti.eth
/// @notice The functionality to create Scapes metadata.
/// @dev Internal functions to create Scape and merge images and json metadata.
abstract contract ScapesMetadataInternal {
    using UintUtils for uint256;
    using ScapesMerge for ScapesMerge.Merge;
    using strings for *;

    struct Scape {
        string[] traitNames;
        string[] traitValues;
        uint256 date;
    }

    uint256 internal constant SCAPE_WIDTH = 72;
    address internal constant ARCHIVE_ADDRESS =
        0x37292Aec4BB789A3b35b736BB6F06cca69EbFA46;
    IScapesArchive internal constant _archive = IScapesArchive(ARCHIVE_ADDRESS);
    bytes internal constant LANDMARK_ORDER = bytes("MTPARBC");

    /// @dev Get the DNA of a scape
    /// @param tokenId token id
    function _getDNA(uint256 tokenId) internal view returns (uint256) {
        uint256 i = tokenId % 3;
        uint256 filter = (1 << ((i + 1) * 85)) - (1 << (i * 85));
        return
            (ScapesMetadataStorage.layout().scapeData[tokenId / 3] & filter) >>
            (i * 85);
    }

    /// @dev Create a Scape with a list of its attributes
    /// @param tokenId token id
    /// @param withVairations whether to include trait variations
    function _getScape(uint256 tokenId, bool withVairations)
        internal
        view
        returns (Scape memory scape)
    {
        ScapesMetadataStorage.Layout storage d = ScapesMetadataStorage.layout();
        uint256 dna = _getDNA(tokenId);
        uint256 counter;
        uint256 traitIdx;
        ScapesMetadataStorage.Trait memory trait;
        strings.slice memory dot = ".".toSlice();

        string[10] memory traitNames;
        string[10] memory traitValues;

        for (uint256 i = 0; i < d.traitNames.length; i++) {
            trait = d.traits[d.traitNames[i]];
            traitIdx = (dna & trait.filter) >> trait.shift;
            if (
                traitIdx >= trait.startIdx &&
                traitIdx - trait.startIdx < trait.names.length
            ) {
                traitNames[counter] = d.traitNames[i];
                string memory traitValue = trait.names[
                    traitIdx - trait.startIdx
                ];
                if (!withVairations && bytes(traitValue)[1] == ".") {
                    traitValue = traitValue.toSlice().rsplit(dot).toString();
                }
                traitValues[counter] = traitValue;
                counter++;
            }
        }

        // handle 1001 special case
        if (tokenId == 1001) {
            traitNames[counter] = "Monuments";
            traitValues[counter] = "Skull";
            counter++;
        }

        scape.traitNames = new string[](counter);
        scape.traitValues = new string[](counter);
        for (uint256 i = 0; i < counter; i++) {
            scape.traitNames[i] = traitNames[i];
            scape.traitValues[i] = traitValues[i];
        }
        scape.date = (dna & 0x3fffffff) + 1643828103;
    }

    /**
     * @notice get image for given token (1-10k scapes, 10k+ merges)
     * @param tokenId token id
     * @param base64_ Whether to encode the svg with base64
     * @param scale Image scale multiplier (set to 0 for auto scaling)
     * @return image data uri of an svg image
     */
    function _getImage(
        uint256 tokenId,
        bool base64_,
        uint256 scale
    ) internal view returns (string memory) {
        if (tokenId > 10_000) {
            ScapesMerge.Merge memory merge = ScapesMerge.fromId(tokenId);
            return _getMergeImage(merge, base64_, scale);
        } else {
            ScapesMerge.Merge memory merge;
            merge.parts = new ScapesMerge.MergePart[](1);
            merge.parts[0] = ScapesMerge.MergePart(tokenId, false, false);
            return _getMergeImage(merge, base64_, scale);
        }
    }

    /// @dev Get the merged token image as a data uri
    /// @param merge a merge object which specifies scapes and settings
    /// @param base64_ Whether to encode the svg with base64
    /// @param scale Image scale multiplier (set to 0 for auto scaling)
    function _getMergeImage(
        ScapesMerge.Merge memory merge,
        bool base64_,
        uint256 scale
    ) internal view returns (string memory) {
        // Init variables
        ScapesMetadataStorage.Layout storage d = ScapesMetadataStorage.layout();
        ScapesMerge.MergePart[] memory parts = merge.parts;
        (Scape[] memory scapes, int256[2][] memory xOffsets) = _loadScapeData(
            parts
        );
        uint256[] memory offsetIdxs = new uint256[](parts.length);

        // build svg string
        string memory s = _svgInit(parts.length, scale);
        for (uint256 traitIdx = 0; traitIdx < d.traitNames.length; traitIdx++) {
            // required to translate between X.Name and descriptive name of Scapes Archive
            TraitSVGImageArgs memory args;
            args.traitName = d.traitNames[traitIdx];
            for (uint256 scapeIdx = 0; scapeIdx < parts.length; scapeIdx++) {
                Scape memory scape = scapes[scapeIdx];
                args.traitValue = _getScapeTraitValue(scape, args.traitName);
                if (_empty(args.traitValue)) {
                    continue;
                }

                args.xOffset = int256(SCAPE_WIDTH * scapeIdx);
                if (d.traits[args.traitName].isLandmark) {
                    args.xOffset += xOffsets[scapeIdx][offsetIdxs[scapeIdx]];
                    offsetIdxs[scapeIdx]++;
                }
                if (bytes(args.traitValue)[1] == "F") {
                    // check for UFO
                    args.yOffset = _getUFOOffset(scape);
                } else {
                    args.yOffset = 0;
                }
                args.flipX = parts[scapeIdx].flipX;
                args.centerX = SCAPE_WIDTH * scapeIdx + 36;
                s = string.concat(s, _traitSvgImage(args));
                if (merge.isFade && !d.traits[args.traitName].isLandmark) {
                    if (
                        (!args.flipX && scapeIdx > 0) ||
                        (args.flipX && scapeIdx < parts.length - 1)
                    ) {
                        s = string.concat(
                            s,
                            _traitSvgImage(
                                args,
                                "Fades",
                                string.concat(args.traitValue, " left")
                            )
                        );
                    }
                    if (
                        (args.flipX && scapeIdx > 0) ||
                        (!args.flipX && scapeIdx < parts.length - 1)
                    ) {
                        s = string.concat(
                            s,
                            _traitSvgImage(
                                args,
                                "Fades",
                                string.concat(args.traitValue, " right")
                            )
                        );
                    }
                }
                if (
                    parts[scapeIdx].tokenId == 1001 &&
                    bytes(args.traitName)[0] == "M"
                ) {
                    // handle 1001 special case
                    args.xOffset =
                        int256(SCAPE_WIDTH * scapeIdx) +
                        xOffsets[scapeIdx][offsetIdxs[scapeIdx]];
                    s = string.concat(
                        s,
                        _traitSvgImage(args, "Monuments", "Skull")
                    );
                }
            }
        }
        s = string.concat(s, "</svg>");
        if (base64_) {
            return
                string.concat(
                    "data:image/svg+xml;base64,",
                    Base64.encode(bytes(s))
                );
        }
        return string.concat("data:image/svg+xml;utf8,", s);
    }

    /// @dev Get the token json as a data uri
    /// @param tokenId Token ID of a scape
    /// @param base64_ Whether to encode the json with base64
    function _getJson(uint256 tokenId, bool base64_)
        internal
        view
        returns (string memory)
    {
        if (tokenId > 10_000) {
            return _getJsonMerge(tokenId, base64_);
        }
        ScapesERC721MetadataStorage.Layout
            storage md = ScapesERC721MetadataStorage.layout();
        string memory tokenIdStr = tokenId.toString();

        string memory tokenURI = string.concat(
            '{"name":"Scape #',
            tokenIdStr,
            '","description":"',
            md.description,
            '","image":"',
            _getImage(tokenId, true, 15),
            '","external_url":"',
            md.externalBaseURI,
            tokenIdStr,
            '","attributes":',
            _attributeJson(tokenId),
            "}"
        );
        if (base64_) {
            return
                string.concat(
                    "data:application/json;base64,",
                    Base64.encode(bytes(tokenURI))
                );
        }
        return string.concat("data:application/json;utf8,", tokenURI);
    }

    function _getJsonMerge(uint256 mergeId, bool base64_)
        internal
        view
        returns (string memory)
    {
        ScapesERC721MetadataStorage.Layout
            storage md = ScapesERC721MetadataStorage.layout();
        ScapesMerge.Merge memory merge_ = ScapesMerge.fromId(mergeId);
        uint256[] memory tokenIds = merge_.getSortedTokenIds(true);

        string memory tokenURI = string.concat(
            '{"name":"',
            _mergeName(tokenIds),
            '","description":"',
            md.description,
            _mergeDescription(merge_, tokenIds),
            '","image":"',
            _getMergeImage(merge_, true, 15),
            '","external_url":"',
            md.externalBaseURI,
            mergeId.toString(),
            '","attributes":',
            _mergeAttributeJson(merge_, tokenIds),
            "}"
        );
        if (base64_) {
            return
                string.concat(
                    "data:application/json;base64,",
                    Base64.encode(bytes(tokenURI))
                );
        }
        return string.concat("data:application/json;utf8,", tokenURI);
    }

    function _mergeName(uint256[] memory tokenIds)
        internal
        pure
        returns (string memory)
    {
        if (tokenIds.length == 2) {
            return
                string.concat(
                    "Scape Diptych of #",
                    tokenIds[0].toString(),
                    " and #",
                    tokenIds[1].toString()
                );
        }
        if (tokenIds.length == 3) {
            return
                string.concat(
                    "Scape Triptych of #",
                    tokenIds[0].toString(),
                    ", #",
                    tokenIds[1].toString(),
                    " and #",
                    tokenIds[2].toString()
                );
        }
        return
            string.concat(
                "Scape Polyptych of #",
                tokenIds[0].toString(),
                " and ",
                (tokenIds.length - 1).toString(),
                " more Scapes"
            );
    }

    function _mergeDescription(
        ScapesMerge.Merge memory merge_,
        uint256[] memory tokenIds
    ) internal pure returns (string memory s) {
        s = "\\nThis Scape Merge contains the following Scapes: ";
        s = string.concat(s, "#", tokenIds[0].toString());
        for (uint256 i = 1; i < tokenIds.length; i++) {
            s = string.concat(s, ", #", tokenIds[i].toString());
        }
        // add bot command
        s = string.concat(
            s,
            "\\n\\n`!scape ",
            merge_.isFade ? "fade" : "merge"
        );
        for (uint256 i = 0; i < merge_.parts.length; i++) {
            s = string.concat(
                s,
                " ",
                merge_.parts[i].tokenId.toString(),
                merge_.parts[i].flipX ? "h" : "",
                merge_.parts[i].flipY ? "v" : ""
            );
        }
        s = string.concat(s, "`");
    }

    function _mergeAttributeJson(
        ScapesMerge.Merge memory merge_,
        uint256[] memory tokenIds
    ) internal pure returns (string memory s) {
        s = "[";
        s = _traitJson(s, "Type", merge_.isFade ? "Fade" : "Merge", "");
        s = string.concat(s, ",");
        s = _traitJson(s, "Mirror", merge_.hasNoFlip() ? "No" : "Yes", "");
        s = string.concat(s, ",");
        s = _traitJson(s, "Size", merge_.parts.length, "");
        for (uint256 i = 0; i < tokenIds.length; i++) {
            s = string.concat(s, ",");
            s = _traitJson(
                s,
                "Scape",
                string.concat("#", tokenIds[i].toString()),
                ""
            );
        }
        s = string.concat(s, "]");
    }

    function _svgInit(uint256 n, uint256 scale)
        internal
        pure
        returns (string memory)
    {
        return
            string.concat(
                '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ',
                (SCAPE_WIDTH * n).toString(),
                ' 24" height="',
                scale < 1 ? "100%" : (24 * scale).toString(),
                '" width="',
                scale < 1 ? "100%" : (SCAPE_WIDTH * n * scale).toString(),
                '" style="image-rendering:pixelated;width:100%;height:auto;background-color:black;" preserveAspectRatio="xMaxYMin meet">'
            );
    }

    function _loadScapeData(ScapesMerge.MergePart[] memory parts)
        internal
        view
        returns (Scape[] memory scapes, int256[2][] memory xOffsets)
    {
        scapes = new Scape[](parts.length);
        xOffsets = new int256[2][](parts.length);
        for (uint256 i = 0; i < parts.length; i++) {
            scapes[i] = _getScape(parts[i].tokenId, true);
            xOffsets[i] = _landmarkOffsets(scapes[i]);
        }
    }

    function _getScapeTraitIdx(Scape memory scape, string memory traitName)
        internal
        pure
        returns (uint256)
    {
        for (uint256 i = 0; i < scape.traitNames.length; i++) {
            if (
                keccak256(bytes(scape.traitNames[i])) ==
                keccak256(bytes(traitName))
            ) {
                return i;
            }
        }
        return 404;
    }

    function _getScapeTraitValue(Scape memory scape, string memory traitName)
        internal
        view
        returns (string memory)
    {
        bytes32 traitNameHash = keccak256(bytes(traitName));
        if (
            traitNameHash == keccak256(bytes("Topology")) ||
            traitNameHash == keccak256(bytes("Surface"))
        ) {
            return "";
        }

        uint256 i = _getScapeTraitIdx(scape, traitName);
        if (i == 404) {
            return "";
        }

        string memory traitValue = ScapesMetadataStorage
            .layout()
            .variationNames[scape.traitValues[i]];
        if (_empty(traitValue)) {
            traitValue = scape.traitValues[i];
        }

        if (
            traitNameHash == keccak256(bytes("Planet")) ||
            traitNameHash == keccak256(bytes("Landscape"))
        ) {
            traitValue = string.concat(
                scape.traitValues[i - 1],
                " ",
                scape.traitValues[i]
            );
        }
        return traitValue;
    }

    function _getLandmarkOrder(string memory landmark)
        internal
        pure
        returns (uint256)
    {
        for (uint256 i = 0; i < LANDMARK_ORDER.length; i++) {
            if (bytes(landmark)[0] == LANDMARK_ORDER[i]) {
                return i;
            }
        }
        return 404;
    }

    function _landmarkOffsets(Scape memory scape)
        internal
        view
        returns (int256[2] memory out)
    {
        ScapesMetadataStorage.Layout storage d = ScapesMetadataStorage.layout();
        uint256 nrObjects;
        string memory firstLandmark;
        bool flipLandmarks;
        string memory landscape;
        for (uint256 i = 0; i < scape.traitNames.length; i++) {
            if (d.traits[scape.traitNames[i]].isLandmark) {
                nrObjects++;
                if (nrObjects == 1) {
                    firstLandmark = scape.traitNames[i];
                } else {
                    flipLandmarks =
                        _getLandmarkOrder(firstLandmark) >
                        _getLandmarkOrder(scape.traitNames[i]);
                }
            }
            if (
                keccak256(bytes(scape.traitNames[i])) ==
                keccak256(bytes("Landscape"))
            ) {
                landscape = scape.traitValues[i];
            }
        }
        int256[] memory offsets = d.landmarkOffsets[landscape][nrObjects];
        for (uint256 i = 0; i < offsets.length; i++) {
            out[i] = offsets[flipLandmarks ? offsets.length - i - 1 : i];
        }
    }

    function _attributeJson(uint256 tokenId)
        internal
        view
        returns (string memory out)
    {
        Scape memory scape = _getScape(tokenId, false);
        out = "[";
        for (uint256 i = 0; i < scape.traitNames.length; i++) {
            out = string.concat(
                _traitJson(out, scape.traitNames[i], scape.traitValues[i], ""),
                ","
            );
        }
        out = string.concat(_traitJson(out, "date", scape.date, "date"), "]");
    }

    struct TraitSVGImageArgs {
        string traitName;
        string traitValue;
        int256 xOffset;
        int256 yOffset;
        bool flipX;
        uint256 centerX;
    }

    function _traitSvgImage(TraitSVGImageArgs memory args)
        internal
        view
        returns (string memory)
    {
        return _traitSvgImage(args, args.traitName, args.traitValue);
    }

    function _traitSvgImage(
        TraitSVGImageArgs memory args,
        string memory traitName,
        string memory traitValue
    ) internal view returns (string memory s) {
        IScapesArchive.Element memory element = _archive.getElement(
            traitName,
            traitValue
        );
        if (element.data.length == 0) {
            return s;
        }
        int256 xOffset = args.xOffset + element.metadata.x;
        int256 yOffset = args.yOffset + element.metadata.y;
        s = string.concat(
            '<image x="',
            xOffset < 0 ? "-" : "",
            _abs(xOffset).toString(),
            '" y="',
            yOffset < 0 ? "-" : "",
            _abs(yOffset).toString(),
            '" width="',
            uint256(element.metadata.width).toString(),
            '" height="',
            uint256(element.metadata.height).toString()
        );
        if (args.flipX) {
            s = string.concat(
                s,
                '" transform="scale (-1, 1)" transform-origin="',
                args.centerX.toString()
            );
        }
        s = string.concat(
            s,
            '" href="data:image/png;base64,',
            Base64.encode(element.data),
            '"/>'
        );
    }

    function _traitSvgFadeImage(TraitSVGImageArgs memory args, bool left)
        internal
        view
        returns (string memory s)
    {
        IScapesArchive.Element memory element = _archive.getElement(
            "Fades",
            string.concat(args.traitValue, left ? " left" : " right")
        );
        if (element.data.length > 0) {
            int256 xOffset = args.xOffset + element.metadata.x;
            s = string.concat(
                '<image x="',
                xOffset < 0 ? "-" : "",
                _abs(xOffset).toString()
            );
            if (args.flipX) {
                s = string.concat(
                    s,
                    '" transform="scale (-1, 1)" transform-origin="',
                    args.centerX.toString()
                );
            }
            s = string.concat(
                s,
                '" href="data:image/png;base64,',
                Base64.encode(element.data),
                '"/>'
            );
        }
    }

    function _getRawScapeTraitValue(Scape memory scape, string memory traitName)
        internal
        pure
        returns (string memory)
    {
        uint256 traitIdx = _getScapeTraitIdx(scape, traitName);
        if (traitIdx == 404) {
            return "";
        }
        return scape.traitValues[traitIdx];
    }

    function _hasTrait(Scape memory scape, string memory traitName)
        internal
        pure
        returns (bool)
    {
        uint256 traitIdx = _getScapeTraitIdx(scape, traitName);
        return traitIdx != 404;
    }

    function _hasTrait(
        Scape memory scape,
        string memory traitName,
        string memory traitValue
    ) internal pure returns (bool) {
        uint256 traitIdx = _getScapeTraitIdx(scape, traitName);
        if (traitIdx == 404) {
            return false;
        }
        return
            keccak256(bytes(traitValue)) ==
            keccak256(bytes(scape.traitValues[traitIdx]));
    }

    function _getUFOOffset(Scape memory scape) internal pure returns (int256) {
        if (
            !(_hasTrait(scape, "Planet") ||
                _hasTrait(scape, "Landscape") ||
                _hasTrait(scape, "City"))
        ) {
            if (_hasTrait(scape, "Rocketry", "0.UFO")) {
                return 4;
            }
            return 2;
        }
        return 0;
    }

    function _traitJson(
        string memory s,
        string memory category,
        string memory trait,
        string memory display
    ) internal pure returns (string memory) {
        if (bytes(display).length > 0)
            s = string.concat(s, '{"display_type": "', display, '",');
        else s = string.concat(s, "{");
        return
            string.concat(
                s,
                '"trait_type":"',
                category,
                '","value":"',
                trait,
                '"}'
            );
    }

    function _traitJson(
        string memory s,
        string memory category,
        uint256 trait,
        string memory display
    ) internal pure returns (string memory) {
        if (bytes(display).length > 0)
            s = string.concat(s, '{"display_type": "', display, '",');
        else s = string.concat(s, "{");
        return
            string.concat(
                s,
                '"trait_type":"',
                category,
                '","value":',
                trait.toString(),
                "}"
            );
    }

    function _empty(string memory s) internal pure returns (bool) {
        return bytes(s).length == 0;
    }

    function _abs(int256 x) internal pure returns (uint256) {
        return uint256(x < 0 ? -x : x);
    }
}

