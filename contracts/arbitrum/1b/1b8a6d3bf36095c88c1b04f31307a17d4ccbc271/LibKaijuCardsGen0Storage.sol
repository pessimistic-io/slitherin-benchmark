//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title LibKaijuCardsGen0Storage library
 * @notice This library contains the storage layout and events/errors for the KaijuCardsGen0Facet contract.
 */
library LibKaijuCardsGen0Storage {
    struct Layout {
        /**
         * @dev Mapping of token ID to staked status
         */
        mapping(uint256 => bool) tokenIsStaked;
        /**
         * @dev Whether staking can be performed
         */
        bool allowStaking;
        /**
         * @dev Whether unstaking can be performed
         */
        bool allowUnstaking;
        /**
         * @dev Base URI for token URIs
         */
        string baseUri;
    }

    uint256 internal constant CHARACTER_TOKEN_OFFSET_AMOUNT = 100_000;

    bytes32 internal constant FACET_STORAGE_POSITION = keccak256("spellcaster.storage.bridging.KaijuCardsGen0");

    function layout() internal pure returns (Layout storage l_) {
        bytes32 _position = FACET_STORAGE_POSITION;
        assembly {
            l_.slot := _position
        }
    }

    error TokenIsStaked(uint256 tokenId);
    error UnknownTokenId(uint256 tokenId);
}

