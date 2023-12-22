// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC721Upgradeable.sol";
import "./ERC721EnumerableUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./AccessControlUpgradeable.sol";
import "./ERC721BurnableUpgradeable.sol";
import "./Initializable.sol";
import "./CountersUpgradeable.sol";
import "./BaseBeasts.sol";

/// @custom:security-contact otium@kurorobeasts.com
contract KuroroBeasts is BaseBeasts {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() initializer public {
        _BaseBeasts_init("KuroroBeasts", "KB");
    }

    function _baseURI() internal pure override returns (string memory) {
        return "https://api.kuroro.com/metadata/beasts/";
    }
}
