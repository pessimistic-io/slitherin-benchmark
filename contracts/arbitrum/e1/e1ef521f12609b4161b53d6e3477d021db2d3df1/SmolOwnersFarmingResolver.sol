// SPDX-License-Identifier: MIT

pragma solidity ^0.8.11;

import "./Initializable.sol";

import "./ICreatureOwnerResolver.sol";
import "./ISmolFarm.sol";

/**
 * @title  SmolOwnersFarmingResolver contract
 * @author Archethect
 * @notice This contract contains all functionalities for verifying Smol farming
 */
contract SmolOwnersFarmingResolver is Initializable, ICreatureOwnerResolver {
    address public smolBrains;
    ISmolFarm public smolFarm;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address smolFarm_, address smolBrains_) public initializer {
        require(address(smolFarm_) != address(0), "SMOLOWNERSRESOLVERADAPTER:ILLEGAL_ADDRESS");
        require(address(smolBrains_) != address(0), "SMOLOWNERSRESOLVERADAPTER:ILLEGAL_ADDRESS");
        smolFarm = ISmolFarm(smolFarm_);
        smolBrains = smolBrains_;
    }

    function isOwner(address account, uint256 tokenId) external view override returns (bool) {
        return smolFarm.ownsToken(smolBrains, account, tokenId);
    }
}

