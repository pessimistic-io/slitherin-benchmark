// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC721A.sol";
import "./Ownable.sol";

contract jpogs is ERC721A, Ownable {
    uint256 public maxMintAmountPerTxn = 5;
	uint256 public freeSupply = 2000;
    uint256 public maxSupply = 10000;
    uint256 public mintPrice = 0.002 ether;
    bool public paused = true;
    string public baseURI = "https://gateway.pinata.cloud/ipfs/QmcHQUqMG7QkuevR4fapFWc3QsPEwGnnJgvm471M5KUure/";
    mapping(address => uint) private _walletMintedCount;

    constructor() ERC721A("Jpogs", "jpgs") {}

    function mintTo(address to, uint256 count) external onlyOwner {
		require(_totalMinted() + count <= maxSupply, 'Too much');
		_safeMint(to, count);
	}

    function mint(uint256 count) external payable {
      require(!paused, 'Paused');
      require(count <= maxMintAmountPerTxn, 'Too many amount');
      require(_totalMinted() + count <= maxSupply, 'Sold out');
      uint256 price = 0;
      if(_totalMinted() + count <= freeSupply && _walletMintedCount[msg.sender] + count <= maxMintAmountPerTxn) {
        price = 0;
      }
      else {
        price = mintPrice;
      }
        require(msg.value >= count * price, 'Not enough balance');
        _walletMintedCount[msg.sender] += count;
        _safeMint(msg.sender, count);
	}

    function mintedCount(address owner) external view returns (uint256) {
        return _walletMintedCount[owner];
    }

    function withdraw() external payable onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    function setPaused(bool _state) public onlyOwner {
        paused = _state;
    }

    function setMintPrice(uint256 _mintPrice) public onlyOwner {
        mintPrice = _mintPrice;
    }

    function setMaxMintAmountPerTxn(uint256 _maxMintAmountPerTxn) public onlyOwner {
        maxMintAmountPerTxn = _maxMintAmountPerTxn;
    }
	
	function setMaxSupply(uint256 _maxSupply) public onlyOwner {
        maxSupply = _maxSupply;
    }

    function setBaseURI(string memory _uri) external onlyOwner {
        baseURI = _uri;
    }

    function totalMinted() external view returns (uint256) {
        return _totalMinted();
    }
}
