// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// Contract imports
import { ERC721BaseInternal } from "./ERC721BaseInternal.sol";
import { ERC721EnumerableInternal } from "./ERC721EnumerableInternal.sol";

// Storage imports
import { WithModifiers } from "./LibStorage.sol";
import { Errors } from "./Errors.sol";
import "./Constants.sol";

// Library imports
import { LibLandUtils } from "./LibLandUtils.sol";

contract WLMintingFacet is WithModifiers, ERC721BaseInternal, ERC721EnumerableInternal {
    /**
     * @dev Mint wastelands provided a valid claim.
     */
    function mintWhitelist(
        uint256 index,
        uint256[] calldata tokens,
        bytes32[] calldata merkleProof
    ) external notPaused {
        LibLandUtils.verifyProof(index, msg.sender, tokens, merkleProof);
        uint256 amount = tokens.length;
        if (_totalSupply() + amount > MAX_CAP_LAND) revert Errors.MaxLandCapReached();
        ws().wastelandsWhitelistMinted[msg.sender] = true;
        for (uint256 i = 0; i < amount; i++) {
            _safeMint(msg.sender, tokens[i]);
        }
    }

    /**
     * @dev Check if the provided account has minted its assigned whitelists yet.
     */
    function hasMintedFromWhitelist(address account) external view returns (bool) {
        return ws().wastelandsWhitelistMinted[account];
    }
}

