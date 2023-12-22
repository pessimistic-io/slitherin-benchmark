// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

interface ILoot8BurnableCollection {

    /**
     * @dev Burns a token belonging to the collection
     * @param tokenId uint256 tokenId that should be burned
     */
    function burn(uint256 tokenId) external;

}
