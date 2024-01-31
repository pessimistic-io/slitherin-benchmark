// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "./ERC721Enumerable.sol";
import "./AccessControlEnumerable.sol";
import "./Context.sol";
import "./Counters.sol";
import "./Ownable.sol";
import "./MerkleProof.sol";
import "./ERC721Tradeable.sol";
import "./DefaultOperatorFilterer.sol";

//   _ \     \    __ )  __ )_ _|__ __| 
//  |   |   _ \   __ \  __ \  |    |   
//  __ <   ___ \  |   | |   | |    |   
// _| \_\_/    _\____/ ____/___|  _|   

contract Rabbit is DefaultOperatorFilterer, Context, ERC721Tradeable {
  using SafeMath for uint256;
  using SafeMath for int256;
  address payable payableAddress;
  bytes32 public merkleRoot = 0x00000000;
  using Counters for Counters.Counter;
  // mintStage 1 == Whitelist, 2 == public
  uint256 mintStage = 0;

  constructor(address _proxyAddress) ERC721Tradeable("RabbitOfTheYear", "RABBIT", _proxyAddress) {
    _baseTokenURI = "ipfs://bafybeigsslxso5dsvkrgouk6vjymcqqhae3zt3pg36hxzdmqpvewikv55m/";
    payableAddress = payable(0x2858DDB404B60b65b2F570c13B6E61952c978557);
  }

    function mint(
        uint256 amount
    ) public virtual payable {
        require(mintStage == 2 || mintStage == 1, "Public mint not started");
        _mintValidate(amount, _msgSender(), false);
        _safeMintTo(_msgSender(), amount);
    }

    function whitelistMint(uint256 amount, bytes32[] calldata merkleProof) public virtual payable {
      require(mintStage == 1, "Whitelist mint not started");
      require(isWhitelisted(merkleProof), "not whitelisted");
      _mintValidate(amount, _msgSender(), true);
      _safeMintTo(_msgSender(), amount);
    }

    function isWhitelisted(bytes32[] calldata _merkleProof) internal view returns (bool) {
      bytes32 leaf = keccak256(abi.encodePacked(_msgSender()));
      return MerkleProof.verify(_merkleProof, merkleRoot, leaf);
    }

    function updateMerkleRoot(bytes32 newMerkleRoot) public onlyOwner {
      merkleRoot = newMerkleRoot;
    }

    function teamMint(
        uint256 amount,
        address to
    ) public virtual onlyOwner {
        _safeMintTo(to, amount);
    }

    function setBaseTokenURI(string memory uri) public onlyOwner {
      _baseTokenURI = uri;
    }

    function mintTo(address _to) public onlyOwner {
      _mintValidate(1, _to, false);
      _safeMintTo(_to, 1);
    }

    function _safeMintTo(
        address to,
        uint256 amount
    ) internal {
      uint256 startTokenId = _nextTokenId.current();
      require(SafeMath.sub(startTokenId, 1) + amount <= MAX_SUPPLY, "collection sold out");
      require(to != address(0), "cannot mint to the zero address");
      
      _beforeTokenTransfers(address(0), to, startTokenId, amount);
        for(uint256 i; i < amount; i++) {
          uint256 tokenId = _nextTokenId.current();
          _nextTokenId.increment();
          _mint(to, tokenId);
        }
      _afterTokenTransfers(address(0), to, startTokenId, amount);
    }

    function _mintValidate(uint256 amount, address to, bool isWhitelist) internal virtual {
      require(amount != 0, "cannot mint 0");
      require(isSaleActive() == true, "sale non-active");
      uint256 balance = balanceOf(to);
      
      if (balance + amount > maxFree()) {
        int256 free = int256(maxFree()) - int256(balance);
        if(free > 0) {
          require(int256(msg.value) >= (int256(amount) - free) * int256(mintPriceInWei()), "incorrect value sent");
        } else {
          require(msg.value >= SafeMath.mul(amount, mintPriceInWei()), "incorrect value sent");
        }
      }
      require(amount <= maxMintPerTx(), "quantity is invalid, max reached on tx");
      require(balance + amount <= maxMintPerWallet(), "quantity is invalid, max reached on wallet");
    }

    function _afterTokenTransfers(
        address from,
        address to,
        uint256 startTokenId,
        uint256 quantity
    ) internal virtual {}

    function setPublicSale(bool toggle) public virtual onlyOwner {
        _isActive = toggle;
    }

    function setMintStage(uint256 stage) public virtual onlyOwner {
        mintStage = stage;
    }

    function isSaleActive() public view returns (bool) {
        return _isActive;
    }

    function totalSupply() public view returns (uint256) {
        return _nextTokenId.current() - 1;
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function isApprovedForAll(address owner, address operator)
        override
        public
        view
        returns (bool)
    {
        ProxyRegistry proxyRegistry = ProxyRegistry(proxyRegistryAddress);
        if (address(proxyRegistry.proxies(owner)) == operator) {
            return true;
        }

        return super.isApprovedForAll(owner, operator);
    }

    function _beforeTokenTransfers(
        address from,
        address to,
        uint256 startTokenId,
        uint256 quantity
    ) internal virtual {}

    function baseTokenURI() public view returns (string memory) {
        return _baseTokenURI;
    }

    function updateContractURI(string memory newContractURI) public onlyOwner {
      _contractURI = newContractURI;
    }

    function contractURI() public view returns (string memory) {
      //return "ipfs://bafkreie4hhb4ghsilgvglir5froufk56eddxqkr3fxeqp7lbclugorm3gm";
      return _contractURI;
    }

    function withdraw() public onlyOwner  {
      (bool success, ) = payableAddress.call{value: address(this).balance}('');
      require(success);
    }

    function maxSupply() public view virtual returns (uint256) {
        return MAX_SUPPLY;
    }

    function maxMintPerTx() public view virtual returns (uint256) {
        return MAX_PER_TX;
    }

    function maxMintPerWallet() public view virtual returns (uint256) {
        return MAX_PER_WALLET;
    }

    function cutSupply(uint256 newSupply) public onlyOwner {
      require(newSupply < MAX_SUPPLY, "cannot cut supply to more than max supply");
      require(newSupply > totalSupply(), "cannot cut supply to less than current supply");
      MAX_SUPPLY = newSupply;
    }

    //new fees stuff
    function setApprovalForAll(address operator, bool approved) public override onlyAllowedOperatorApproval(operator) {
        super.setApprovalForAll(operator, approved);
    }

    function approve(address operator, uint256 tokenId) public override onlyAllowedOperatorApproval(operator) {
        super.approve(operator, tokenId);
    }

    function transferFrom(address from, address to, uint256 tokenId) public override onlyAllowedOperator(from) {
        super.transferFrom(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) public override onlyAllowedOperator(from) {
        super.safeTransferFrom(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data)
        public
        override
        onlyAllowedOperator(from)
    {
        super.safeTransferFrom(from, to, tokenId, data);
    }
}

