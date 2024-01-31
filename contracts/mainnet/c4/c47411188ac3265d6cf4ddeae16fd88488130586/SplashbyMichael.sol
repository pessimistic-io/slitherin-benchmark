// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./Ownable.sol";
import "./TinyERC721.sol";
import "./IERC721.sol";

contract SplashbyMichael is TinyERC721, Ownable {

    string public baseURI;

    address public proxyRegistryAddress = 0xa5409ec958C83C3f309868babACA7c86DCB077c1;
    address public lead;

    bool public publicPaused = true;
    
    uint256 public cost = 0.005 ether;
    uint256 public maxSupply = 333;
    uint256 public maxPerWalletPublic = 2;
    uint256 public maxPerWalletFree = 0;
    uint256 public maxPerTxPublic = 2;
    uint256 public maxPerTxFree = 0;
    address public contractV1;
    uint256 supply = totalSupply();

    mapping(address => uint) public addressMintedBalance;
    mapping(address => uint) public addressMintedBalanceFree;
    

 constructor(
    string memory _baseURI,
    address _lead,
    address _contractV1
  )TinyERC721("Splash by Micheal", "SBM", 0) {
    baseURI = _baseURI;
    lead = _lead;
    contractV1 = _contractV1;
  }

  modifier publicnotPaused() {
    require(!publicPaused, "Contract is Paused");
     _;
  }

  modifier callerIsUser() {
    require(tx.origin == msg.sender, 'The caller is another contract.');
    _;
  }


  function setContractV1Address(address _contractV1) public onlyOwner {
    contractV1 =_contractV1;
  }

  function tokenURI(uint256 _tokenId) public view override returns (string memory) {
    require(_exists(_tokenId), "Token does not exist.");
    return string(abi.encodePacked(baseURI, Strings.toString(_tokenId),".json"));
  }

  function setProxyRegistryAddress(address _proxyRegistryAddress) external onlyOwner {
    proxyRegistryAddress = _proxyRegistryAddress;
  }

  function togglePublic(bool _state) external onlyOwner {
    publicPaused = _state;
  }

  function reserveTokens(uint256 _quanitity) public onlyOwner {        
    uint256 supply = totalSupply();
    require(_quanitity + supply <= maxSupply);
    _safeMint(msg.sender, _quanitity);
  }

  function setBaseURI(string memory _baseURI) public onlyOwner {
    baseURI = _baseURI;
  }

  function publicMint(uint256 _quantity)
    public 
    payable 
    publicnotPaused() 
    callerIsUser() 
  {
    uint256 supply = totalSupply();
    require(msg.value >= cost * _quantity, "Not Enough Ether");
    require(_quantity <= maxPerTxPublic, "Over Tx Limit");
    require(_quantity + supply <= maxSupply, "SoldOut");
    require(addressMintedBalance[msg.sender] < maxPerWalletPublic, "Over MaxPerWallet");
    addressMintedBalance[msg.sender] += _quantity;
    
    _safeMint(msg.sender, _quantity);
  }

  function freeMint(uint256 _quantitty)
    public  
    publicnotPaused() 
    callerIsUser() 
  {
    uint256 supply = totalSupply();
    require(_quantitty <= maxPerTxFree, "Over Tx Limit");
    require(_quantitty + supply <= maxSupply, "SoldOut");
    require(addressMintedBalanceFree[msg.sender] < maxPerWalletFree, "Over MaxPerWallet");
    addressMintedBalanceFree[msg.sender] += _quantitty;
    
    _safeMint(msg.sender, _quantitty);
  }

  function isApprovedForAll(address _owner, address operator) public view override returns (bool) {
    OpenSeaProxyRegistry proxyRegistry = OpenSeaProxyRegistry(proxyRegistryAddress);
    if (address(proxyRegistry.proxies(_owner)) == operator) return true;
    return super.isApprovedForAll(_owner, operator);
  }
    
  function withdraw() public onlyOwner {
    (bool success, ) = lead.call{value: address(this).balance}("");
    require(success, "Failed to send to lead.");
  }

}

contract OwnableDelegateProxy { }
contract OpenSeaProxyRegistry {
    mapping(address => OwnableDelegateProxy) public proxies;
    }
