// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./ERC721.sol";
import "./ERC721Enumerable.sol";
import "./Ownable.sol";


interface Souls {

    function soulIsOwnedBy(address noSoulMate) external returns (address);
    function transferSoul(address _to, address noSoulMate) external payable;
}

contract DropBox is Ownable {

    function sendSoul(address soulAddr, address to, Souls soulInt) public payable onlyOwner {
        soulInt.transferSoul{value: msg.value}(to, soulAddr);
    }
}

contract WrappedSouls is ERC721, ERC721Enumerable, Ownable {

    event DropBoxCreated(address indexed owner);
    event Rescued(address indexed soulAddr, address indexed owner);
    event Wrapped(uint256 indexed soulId, address indexed owner);
    event Unwrapped(uint256 indexed soulId, address indexed owner);

    Souls public soulInt = Souls(0x5bF554632a059aE0537a3EEb20Aced49348B8F99);
    
    string public baseTokenURI;
    
    mapping(address => address) public dropBoxes;
    
    uint256 constant numSouls = 7;
    mapping(uint256 => address) public soulAddrs;
    mapping(address => uint256) public soulIds;
    mapping(address => bool) public soulWasListed;
    
    constructor() ERC721("WrappedSouls", "WS") {

        baseTokenURI = "https://souls.ethyearone.com/";

        soulAddrs[0] = 0x5Dc297392Beea0Fd0AF017aA57d9E98eeeb014CC;
        soulAddrs[1] = 0xf0dB738b369E4246d00979393D00D87383BbB0A4;
        soulAddrs[2] = 0xaD62d4fDd2d071536DBCB72202f1ef51B17EcE30;
        soulAddrs[3] = 0x6d064946c159A55A7CBF0f9B6C7bAB073A156c6E;
        soulAddrs[4] = 0xd17e06FfEBB8D116c12c818f5E0D67D4Ef62E21f;
        soulAddrs[5] = 0x3102167c002387AC1287Ac09d47D216CE2Fc672d;
        soulAddrs[6] = 0xFa1Bc61AD08a5032c4784DdCfE1D93285135FAcb;

        for (uint256 i = 0; i < numSouls; i++) {
            soulIds[soulAddrs[i]] = i;
            soulWasListed[soulAddrs[i]] = true;
        }
    }

    function createDropBox() public {
        require(dropBoxes[msg.sender] == address(0), "Drop box already exists.");

        dropBoxes[msg.sender] = address(new DropBox());
        
        emit DropBoxCreated(msg.sender);
    }

    function rescue(address soulAddr) public payable {
        address dropBox = dropBoxes[msg.sender];

        require(dropBox != address(0), "You do not have a dropbox"); 
        require(soulInt.soulIsOwnedBy(soulAddr) == dropBox, "Soul is not in dropbox");

        DropBox(dropBox).sendSoul{value: msg.value}(soulAddr, msg.sender, soulInt);

        emit Rescued(soulAddr, msg.sender);
    }

    function wrap(address soulAddr) public payable {  
        address dropBox = dropBoxes[msg.sender];
        uint256 soulId = soulIds[soulAddr];
        
        require(dropBox != address(0), "You must create a drop box first"); 
        require(soulWasListed[soulAddr], "Soul was not listed for sale long ago");
        require(soulInt.soulIsOwnedBy(soulAddr) == dropBox, "Soul is not in dropbox");
        require(!_exists(soulId), "Token already exists");

        DropBox(dropBox).sendSoul{value: msg.value}(soulAddr, address(this), soulInt);
        _mint(msg.sender, soulId);

        emit Wrapped(soulId, msg.sender);
    }

    function unwrap(uint256 soulId) public payable {
        require(_exists(soulId), "Token does not exist");
        require(msg.sender == ownerOf(soulId), "You are not the owner");

        soulInt.transferSoul{value: msg.value}(msg.sender, soulAddrs[soulId]);
        _burn(soulId);
        
        emit Unwrapped(soulId, msg.sender);
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return baseTokenURI;
    }

    function setBaseTokenURI(string memory _baseTokenURI) public onlyOwner {
        baseTokenURI = _baseTokenURI;
    }

    // The following functions are overrides required by Solidity.

    function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize)
        internal
        override(ERC721, ERC721Enumerable)
    {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
