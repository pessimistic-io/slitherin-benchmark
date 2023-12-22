// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IERC2981 } from "./IERC2981.sol";

interface ISeaDrop1155TokenContractMetadata is IERC2981 {

    /**
     * @dev Revert if the royalty basis points is greater than 10_000.
     */
    error InvalidRoyaltyBasisPoints(uint256 basisPoints);

    /**
     * @dev Revert if the royalty address is being set to the zero address.
     */
    error RoyaltyAddressCannotBeZeroAddress();

    error OnlyOwner();

    /**
     * @dev Emit an event when the royalties info is updated.
     */
    event RoyaltyInfoUpdated(address receiver, uint256 bps);

    /**
     * @dev Emit an event when the royalties address is updated.
     */
    event RoyaltyAddressUpdated(address receiver);

    /**
     * @dev Emit an event when the royalties bps is updated.
     */
    event RoyaltyBpsUpdated(uint256 bps);

    /**
     * @notice A struct defining royalty info for the contract.
     */
    struct RoyaltyInfo {
        address royaltyAddress;
        uint96 royaltyBps;
    }

    /**
     * @notice Throw if the max supply exceeds uint64, a limit
     *         due to the storage of bit-packed variables in ERC721A.
     */
    error CannotExceedMaxSupplyOfUint64(uint256 newMaxSupply);

    /**
     * @dev Emit an event when the max token supply is updated.
     */
    event MaxSupplyUpdated(uint256 newMaxSupply);

    /**
     * @dev Emit an event when the URI is updated.
     */
    event URIUpdated(string newURI);
}

