// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "./IERC721.sol";
import "./IERC165.sol";
import "./IERC721Metadata.sol";

/**
 * @title Minimally required collection interface of a LOOT8 compliant contract.
 */
interface ILoot8POAPCollection {

    /**
     * @dev Mints a collectible and transfers it to `_patron`.
     * @param _patron address representing an owner of minted token
     * @param _tokenURI a tokenURI for the minted token
     *
     * Requirements:
     * - `tokenId` must not exist.
     */
    function mint(address _patron, uint256 _tokenId, string memory _tokenURI) external;

}
