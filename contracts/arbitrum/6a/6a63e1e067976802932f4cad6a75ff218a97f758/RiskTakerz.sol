// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC721Upgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./ERC721ConsecutiveUpgradeable.sol";

contract RiskTakerz is Initializable, ERC721Upgradeable,  OwnableUpgradeable, UUPSUpgradeable,ERC721ConsecutiveUpgradeable {
    using StringsUpgradeable for uint256;

    uint256 public constant MAX_SUPPLY = 10000;
    string private baseURI;

    event BaseURIUpdated(string baseUri);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _tokensReceiver,string memory _baseURI) initializer public {
        __ERC721_init("RiskTakerz", "RT");
        __Ownable_init();
        __UUPSUpgradeable_init();

        baseURI = _baseURI;
        
        _mintConsecutive(_tokensReceiver,5000);
        _mintConsecutive(_tokensReceiver,5000);
    }

  

    function updateBaseURI(string memory _baseURI) public onlyOwner {
        baseURI = _baseURI;
    }


     function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        _requireMinted(tokenId);

        
        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, tokenId.toString(),'.json')) : "";
    }

    function totalSupply() public pure returns(uint256){
        return MAX_SUPPLY;
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        onlyOwner
        override
    {}

    function _ownerOf(uint256 tokenId) internal view virtual override(ERC721Upgradeable,ERC721ConsecutiveUpgradeable) returns (address) {
       return super._ownerOf(tokenId);
    }
    

    function _afterTokenTransfer(
        address from,
        address to,
        uint256 firstTokenId,
        uint256 batchSize
    ) internal virtual override(ERC721Upgradeable,ERC721ConsecutiveUpgradeable) {
        
        super._afterTokenTransfer(from, to, firstTokenId, batchSize);
    }

    function _mint(address to, uint256 tokenId) internal virtual override(ERC721Upgradeable,ERC721ConsecutiveUpgradeable) {
        
        super._mint(to, tokenId);
    }
}
