// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "./ERC721.sol";
import "./Pausable.sol";
import "./AccessControl.sol";
import "./Counters.sol";
import "./Strings.sol";

/** Created via https://wizard.openzeppelin.com/#erc721 */
abstract contract MinterPauserNFT is ERC721, Pausable, AccessControl {
    using Counters for Counters.Counter;

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    Counters.Counter private _tokenIdCounter;

    constructor(string memory name, string memory symbol) ERC721(name, symbol) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
    }

    function _baseURI() internal view override returns (string memory) {
        return string(abi.encodePacked(
            "https://api.notional.finance/nft/",
            Strings.toHexString(address(this)),
            "/"
        ));
    }

    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function safeMint(address to) public onlyRole(MINTER_ROLE) {
        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        _safeMint(to, tokenId);
    }

    function minterTransfer(address from, address to, uint256 tokenId) public onlyRole(MINTER_ROLE) {
        _transfer(from, to, tokenId);
    }

    function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize)
        internal
        override
    {
        // Allow minter control while the contract is paused
        if (!hasRole(MINTER_ROLE, msg.sender)) _requireNotPaused();
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    // The following functions are overrides required by Solidity.

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}


