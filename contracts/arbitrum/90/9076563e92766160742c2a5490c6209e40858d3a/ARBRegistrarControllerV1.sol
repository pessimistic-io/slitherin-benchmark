// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import "./BaseRegistrarImplementation.sol";
import "./StringUtils.sol";
import "./Resolver.sol";
import "./ReverseRegistrar.sol";

import "./Ownable.sol";
import "./IERC165.sol";
import "./Address.sol";

/**
 * @dev A registrar controller for pre-mint and test.
 */
contract ARBRegistrarControllerV1 is Ownable {
    using StringUtils for *;

    uint constant public MIN_REGISTRATION_DURATION = 365 days;

    BaseRegistrarImplementation base;

        event NameRegistered(
        string name,
        bytes32 indexed label,
        address indexed owner,
        uint256 baseCost,
        uint256 premium,
        uint256 expires
    );
    constructor(BaseRegistrarImplementation _base) public {
        base = _base;
    }
    
    function valid(string memory name) public pure returns (bool) {
        bytes memory nb = bytes(name);
        // zero width for /u200b /u200c /u200d and U+FEFF
        for (uint256 i; i < nb.length - 2; i++) {
            if (bytes1(nb[i]) == 0xe2 && bytes1(nb[i + 1]) == 0x80) {
                if (
                    bytes1(nb[i + 2]) == 0x8b ||
                    bytes1(nb[i + 2]) == 0x8c ||
                    bytes1(nb[i + 2]) == 0x8d
                ) {
                    return false;
                }
            } else if (bytes1(nb[i]) == 0xef) {
                if (bytes1(nb[i + 1]) == 0xbb && bytes1(nb[i + 2]) == 0xbf)
                    return false;
            }
        }
        return true;
    }

    function available(string memory name) public view returns(bool) {
        bytes32 label = keccak256(bytes(name));
        return valid(name) && base.available(uint256(label));
    }


    function register(string calldata name, address owner, uint duration) external onlyOwner {
        registerWithConfig(name, owner, duration, address(0), address(0));
    }

    function registerWithConfig(string memory name, address owner, uint duration, address resolver, address addr) public onlyOwner {
        require(available(name), "Name not available");
        bytes32 label = keccak256(bytes(name));
        uint256 tokenId = uint256(label);

        uint expires;
        if(resolver != address(0)) {
            // Set this contract as the (temporary) owner, giving it
            // permission to set up the resolver.
            expires = base.register(tokenId, address(this), duration);

            // The nodehash of this label
            bytes32 nodehash = keccak256(abi.encodePacked(base.baseNode(), label));

            // Set the resolver
            base.arbid().setResolver(nodehash, resolver);

            // Configure the resolver
            if (addr != address(0)) {
                Resolver(resolver).setAddr(nodehash, addr);
            }

            // Now transfer full ownership to the expeceted owner
            base.reclaim(tokenId, owner);
            base.transferFrom(address(this), owner, tokenId);
        } else {
            require(addr == address(0));
            expires = base.register(tokenId, owner, duration);
        }

                emit NameRegistered(
            name,
            keccak256(bytes(name)),
            owner,
            0,
            0,
            expires
        );
    }

}

