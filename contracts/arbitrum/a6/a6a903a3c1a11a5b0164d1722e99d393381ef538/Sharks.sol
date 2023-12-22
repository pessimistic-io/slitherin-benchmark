// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;
import "./ERC721.sol";
import "./ERC721Enumerable.sol";
import "./Counters.sol";
import "./Math.sol";
import "./Strings.sol";

import "./SharksAccessControl.sol";
import "./SharksTransferControl.sol";
import "./SharksSizeControl.sol";


contract Sharks is ERC721, ERC721Enumerable, SharksAccessControl {
    using Counters for Counters.Counter;
    Counters.Counter private tokenIdTracker;

    string public baseURI;

    uint256 public immutable MAX_SUPPLY;
    uint256 public immutable INITIAL_XP;

    uint256 public totalSharksSize;

    SharksTransferControl public sharksTransferControl;
    SharksSizeControl public sharksSizeControl;

    mapping(uint256 => uint256) public xp;
    mapping(uint256 => uint256) public rarity;

    event Minted(address to, uint256 indexed tokenId);
    event Revealed(uint256 indexed tokenId, uint256 rarity);
    event XpIncreased(uint256 tokenId, uint256 xpIncrease, uint256 totalXp);

    event BaseURIChanged(string baseURI);
    event SharksSizeControlChanged(address sharksSizeControl);
    event SharksTransferControlChanged(address sharksTransferControl);

    constructor(uint256 maxSupply_) ERC721("Test Smol Sharks", "tSMOLSHARKS") {
        MAX_SUPPLY = maxSupply_;
        INITIAL_XP = 1;
    }


    // internal
    function _requireMinted(uint256 tokenId) internal view virtual {
        require(_exists(tokenId), "ERC721: invalid token ID");
    }

    function _beforeTokenTransfer(address from_, address to_, uint256 tokenId_)
        internal
        override(ERC721, ERC721Enumerable)
    {
        require(sharkCanBeTransferred(tokenId_) == true, "SharksTransferControl: transfer not allowed");

        super._beforeTokenTransfer(from_, to_, tokenId_);
    }

    // onlyOwner

    function setSharksSizeControl(address sharksSizeControl_)
        public
        onlyOwner
    {
        sharksSizeControl = SharksSizeControl(sharksSizeControl_);
        emit SharksSizeControlChanged(sharksSizeControl_);
    }

    function setSharksTransferControl(address sharksTransferControl_)
        public
        onlyOwner
    {
        sharksTransferControl = SharksTransferControl(sharksTransferControl_);
        emit SharksTransferControlChanged(sharksTransferControl_);
    }

    function setBaseURI(string memory baseURI_)
        public
        onlyOwner
    {
        baseURI = baseURI_;
        emit BaseURIChanged(baseURI);
    }


    // onlyMinter

    function mint(
        address to_,
        uint256 mintsCount_
    )
        public
        onlyMinter
    {
        uint256 _actualMintsCount = Math.min(mintsCount_, MAX_SUPPLY - tokenIdTracker.current());

        require(_actualMintsCount > 0, "MAX_SUPPLY reached");

        for (uint256 i = 0; i < _actualMintsCount; i++) {
            tokenIdTracker.increment();

            uint256 _tokenId = tokenIdTracker.current();

            require(_tokenId <= MAX_SUPPLY, "MAX_SUPPLY reached"); // sanity check, should not ever trigger

            _safeMint(to_, _tokenId);
            emit Minted(to_, _tokenId);
        }
    }

    // onlyRevealer

    function reveal(
        uint256 tokenId_,
        uint256 rarity_
    )
        public
        onlyRevealer
    {
        _requireMinted(tokenId_);
        require(rarity[tokenId_] == 0, "already revealed");

        rarity[tokenId_] = rarity_;
        emit Revealed(tokenId_, rarity_);
        _increaseXp(tokenId_, INITIAL_XP);
    }



    // onlyXpManager

    function increaseXp(uint tokenId_, uint xp_)
        public
        onlyXpManager
    {
        _requireMinted(tokenId_);
        _increaseXp(tokenId_, xp_);
    }

    function _increaseXp(uint tokenId_, uint xp_)
        internal
    {
        totalSharksSize += xp_;
        xp[tokenId_] += xp_;
        emit XpIncreased(tokenId_, xp_, xp[tokenId_]);
    }


    // Views

    function sharkCanBeTransferred(uint256 tokenId_)
        public
        view
        returns (bool)
    {
        if (address(sharksTransferControl) != address(0)) {
            return (sharksTransferControl.sharkCanBeTransferred(tokenId_) == true);
        } else {
            return true;
        }
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        _requireMinted(tokenId);

        require(bytes(_baseURI()).length > 0, "baseURI not set");

        string memory tokenFilename = rarity[tokenId] > 0 ? Strings.toString(tokenId) : "0";

        return string(abi.encodePacked(_baseURI(), tokenFilename, ".json"));
    }

    function size(uint256 tokenId_)
        public
        view
        returns (uint256)
    {
        _requireMinted(tokenId_);

        if(address(sharksSizeControl) != address(0)) {
            return sharksSizeControl.sharkSize(tokenId_);
        } else {
            return 0;
        }
    }
}
