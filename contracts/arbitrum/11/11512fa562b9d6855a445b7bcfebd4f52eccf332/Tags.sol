// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.15;

import {Term, IERC165} from "./Term.sol";
import {Right} from "./Right.sol";
import {ITags, IAgreementManager} from "./ITags.sol";
import {UintBitMap} from "./UintBitMap.sol";

/// @notice Agreement Term for 256 flexible read-only tags.
/// @author Dinari (https://github.com/dinaricrypto/dinari-contracts/blob/main/contracts/terms/Tags.sol)
contract Tags is Right, ITags {
    using UintBitMap for uint256;

    /// @dev tags storage per tokenId
    mapping(IAgreementManager => mapping(uint256 => uint256)) internal tags;

    function getTags(IAgreementManager manager, uint256 tokenId) public view virtual override returns (uint256) {
        return tags[manager][tokenId];
    }

    function hasTag(
        IAgreementManager manager,
        uint256 tokenId,
        uint8 tag
    ) public view virtual override returns (bool) {
        return tags[manager][tokenId].get(tag);
    }

    function packTags(uint8[] memory tagSet) public pure virtual returns (uint256 packedTags) {
        packedTags = 0;
        for (uint8 i = 0; i < tagSet.length; i++) {
            packedTags = packedTags.set(tagSet[i]);
        }
    }

    function _createTerm(
        IAgreementManager manager,
        uint256 tokenId,
        bytes calldata data
    ) internal virtual override {
        tags[manager][tokenId] = abi.decode(data, (uint256));
    }

    function _settleTerm(IAgreementManager, uint256) internal virtual override {}

    function _cancelTerm(IAgreementManager, uint256) internal virtual override {}

    function _afterTermResolved(IAgreementManager manager, uint256 tokenId) internal virtual override {
        delete tags[manager][tokenId];

        super._afterTermResolved(manager, tokenId);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165, Term) returns (bool) {
        return interfaceId == type(ITags).interfaceId || super.supportsInterface(interfaceId);
    }
}

