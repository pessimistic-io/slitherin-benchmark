// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./ERC721Enumerable.sol";
import "./Ownable.sol";
import "./Counters.sol";

contract ZodiacNFT is ERC721Enumerable, Ownable {
    using Strings for uint256;

    using Counters for Counters.Counter;

    Counters.Counter private _tokenIds;

    uint256 public cost = 0.0001 ether;
    uint256 public maxSupply = 100;
    uint256 public maxMintAmount = 5;
    bool public paused = false;
    mapping(address => bool) public whitelisted;
    mapping(uint256 => string) private _asset;

    constructor(
        string memory _name,
        string memory _symbol,
        string memory _cid
    ) ERC721(_name, _symbol) {
        mint(msg.sender, 1, _cid);
    }


    // public
    function mint(address _to, uint256 _mintAmount, string memory _cid) public payable {
        uint256 supply = totalSupply();
        require(!paused);
        require(_mintAmount > 0);
        require(_mintAmount <= maxMintAmount);
        require(supply + _mintAmount <= maxSupply);

        if (msg.sender != owner()) {
            if (whitelisted[msg.sender] != true) {
                require(msg.value >= cost * _mintAmount);
            }
        }

        for (uint256 i = 1; i <= _mintAmount; i++) {
            _safeMint(_to, supply + i);
            _tokenIds.increment();
            _setImage(_tokenIds.current(), _cid);
        }
    }


    function count() public view returns (uint256){
        return _tokenIds.current();
    }

    function walletOfOwner(address _owner)
    public
    view
    returns (uint256[] memory)
    {
        uint256 ownerTokenCount = balanceOf(_owner);
        uint256[] memory tokenIds = new uint256[](ownerTokenCount);
        for (uint256 i; i < ownerTokenCount; i++) {
            tokenIds[i] = tokenOfOwnerByIndex(_owner, i);
        }
        return tokenIds;
    }

    function tokenURI(uint256 tokenId)
    public
    view
    virtual
    override
    returns (string memory)
    {
        require(
            _exists(tokenId),
            "ERC721Metadata: URI query for nonexistent token"
        );

        return bytes(_asset[tokenId]).length > 0
        ? string(abi.encodePacked("ipfs://", _asset[tokenId]))
        : "";
    }

    //only owner
    function setCost(uint256 _newCost) public onlyOwner() {
        cost = _newCost;
    }

    function setmaxMintAmount(uint256 _newmaxMintAmount) public onlyOwner() {
        maxMintAmount = _newmaxMintAmount;
    }

    function pause(bool _state) public onlyOwner {
        paused = _state;
    }

    function whitelistUser(address _user) public onlyOwner {
        whitelisted[_user] = true;
    }

    function setImage(uint256 _tokenId, string memory _cid) public onlyOwner {
        _asset[_tokenId] = _cid;
    }

    function _setImage(uint256 _tokenId, string memory _cid) internal {
        _asset[_tokenId] = _cid;
    }

    function removeWhitelistUser(address _user) public onlyOwner {
        whitelisted[_user] = false;
    }

    function withdraw() public payable onlyOwner {
        require(payable(msg.sender).send(address(this).balance));
    }
}

