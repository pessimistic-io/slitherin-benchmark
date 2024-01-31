// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;

import "./ERC721.sol";
import "./Counters.sol";
import "./Ownable.sol";

contract DiamondPass is ERC721, Ownable {

    uint256 public immutable MAX_SUPPLY = 5000;
    uint256 public immutable PRICE = 0.1 ether;
    uint256 public maxPerWallet = 1;
    uint256 public freeAmount = 500;
    string private _baseTokenURI;


    using Counters for Counters.Counter;
    Counters.Counter currentMintCounter;
    mapping(address => uint8) public _mintCounter;

    constructor() ERC721("Diamond Pass", "DIAMOND") {
        currentMintCounter.increment();
    }

    function mint() payable public {
        require(_mintCounter[msg.sender] + 1 <= maxPerWallet, 'Exceeds max per wallet');
        require(currentMintCounter.current() <= MAX_SUPPLY, 'Reached max supply');
        if (currentMintCounter.current() > freeAmount) {
            require(msg.value == PRICE, "Incorrect ETH amount");
        } else {
            require(msg.value == 0, "Passes are currently free!");
        }
        _mintCounter[msg.sender] = _mintCounter[msg.sender] + 1;
        _safeMint(msg.sender, currentMintCounter.current());
        currentMintCounter.increment();
    }

    function setMaxPerWallet(uint256 _maxPerWallet) external onlyOwner {
        maxPerWallet = _maxPerWallet;
    }
    function setFreeAmount(uint256 _freeAmount) external onlyOwner {
        freeAmount = _freeAmount;
    }

    function setBaseURI(string calldata baseURI) external onlyOwner {
        _baseTokenURI = baseURI;
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return _baseTokenURI;
    }

    function totalSupply() external view returns (uint256) {
        return currentMintCounter.current() - 1;
    }
    
    function withdraw() external onlyOwner(){
        (bool success, ) = msg.sender.call{value: address(this).balance}("");
        require(success, "Transfer failed.");
    }
}
