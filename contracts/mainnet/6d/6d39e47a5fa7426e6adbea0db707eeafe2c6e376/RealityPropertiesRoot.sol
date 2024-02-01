// SPDX-License-Identifier: BUSL-1.1
// Reality NFT Contracts

pragma solidity 0.8.9;

import "./RealityProperties.sol";

/**
* @title Manages shares of properties in Reality realm on the root chain
* @notice This contract extends {RealityProperties} with capabilities
* required for mininting on Ethereum chain.
* @dev The term 'root chain' refers to Ethereum
*/
contract RealityPropertiesRoot is RealityProperties {
    bytes32 public constant MINTING_MANAGER = keccak256("MINTING_MANAGER");

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(string memory uri_, string memory contractUri_, address royaltiesReceiver_) external initializer {
        __RealityPropertiesRoot_init(uri_, contractUri_, royaltiesReceiver_);
    }

    // solhint-disable-next-line func-name-mixedcase
    function __RealityPropertiesRoot_init(string memory uri_, string memory contractUri_, address royaltiesReceiver_) internal onlyInitializing {
        __RealityProperties_init(uri_, contractUri_, royaltiesReceiver_);
        __RealityPropertiesRoot_init_unchained();
    }

    // solhint-disable-next-line func-name-mixedcase
    function __RealityPropertiesRoot_init_unchained() internal onlyInitializing {
        _grantRole(MINTING_MANAGER, msg.sender);
    }

    /**
     * Mints new token id and sends `amount` tokens to the caller
     * @dev A given tokenId can be minted only once, that is guaranteed by _adapterExists() check
     * tokenId zero is not supported, minting fails
     */
    function safeMint(uint256 tokenId, uint256 amount) external virtual onlyRole(MINTING_MANAGER) {
        require(!_adapterExists(tokenId), "RealityPropertiesRoot: Already exists");
        _createAdapter(tokenId);
        _mint(msg.sender, tokenId, amount, "");
    }
}
