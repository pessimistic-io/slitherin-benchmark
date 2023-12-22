// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ILegionMetadataStore.sol";

interface IPilgrimage {

    // Removes the given ids as valid ids and removes the mapped rarity as well.
    // Admin only.
    function removeMetadataForIds(uint256[] calldata _ids) external;

    // Returns if the pilgrimage is ready to be completed for the given ID.
    function isPilgrimageReady(uint256 _pilgrimageID) external view returns(bool);

    // Sends the legion 1155s with the given Ids and amounts on the pilgrimage. The legions must be approved before calling this contract.
    function embarkOnPilgrimages(uint256[] calldata _ids, uint256[] calldata _amounts, LegionGeneration _generation) external;

    // Will collect any legions that have finished their pilgrimages and send the newly minted 721 token to the caller.
    // If there are none, or the pilgrimages aren't ready, this will send an event.
    function returnFromPilgrimages() external;
}
