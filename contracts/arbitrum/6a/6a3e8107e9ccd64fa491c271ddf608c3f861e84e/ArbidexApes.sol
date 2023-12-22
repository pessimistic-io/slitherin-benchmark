// SPDX-License-Identifier: MIT

/***
 *  ██   █▄▄▄▄     ▄      █▀▄▀█ ████▄    ▄   █  █▀ ▄███▄ ▀▄    ▄  ▄▄▄▄▄
 * █ █  █  ▄▀ ▀▄   █     █ █ █ █   █     █  █▄█   █▀   ▀  █  █  █     ▀▄
 * █▄▄█ █▀▀▌    █ ▀      █ ▄ █ █   █ ██   █ █▀▄   ██▄▄     ▀█ ▄  ▀▀▀▀▄
 * █  █ █  █   ▄ █       █   █ ▀████ █ █  █ █  █  █▄   ▄▀  █   ▀▄▄▄▄▀
 *    █   █   █   ▀▄        █        █  █ █   █   ▀███▀  ▄▀
 *   █   ▀     ▀           ▀         █   ██  ▀
 *  ▀
 * Arbidex Dapp: https://arbidex.fi/
 * Twitter: https://twitter.com/arbidexfi
 * GitHub: https://github.com/ArbitrumExchange
 * Discord: https://discord.com/invite/arbidex
 */

pragma solidity >=0.8.9 <0.9.0;

import "./ERC721AQueryable.sol";
import "./Ownable.sol";
import "./MerkleProof.sol";
import "./ReentrancyGuard.sol";
import "./ERC20.sol";

contract ArbidexApes is ERC721AQueryable, Ownable, ReentrancyGuard {
  using Strings for uint256;

  bytes32 public merkleRoot;
  mapping(address => bool) public whitelistClaimed;
  address public tokenAddress1;
  string public uriPrefix = '';
  string public uriSuffix = '.json';
  string public hiddenMetadataUri;

  uint256 public cost;
  uint256 public maxSupply;
  uint256 public maxMintAmountPerTx;

  bool public paused = true;
  bool public whitelistMintEnabled = false;
  bool public revealed = false;

  event LogAllowanceCheck(
    address indexed sender,
    address indexed spender,
    address indexed contractAddress,
    uint256 totalCost
  );

  constructor(
    string memory _tokenName,
    string memory _tokenSymbol,
    uint256 _cost,
    uint256 _maxSupply,
    uint256 _maxMintAmountPerTx,
    string memory _hiddenMetadataUri,
    address _tokenAddress1
  ) ERC721A(_tokenName, _tokenSymbol) {
    setCost(_cost);
    tokenAddress1 = _tokenAddress1;

    maxSupply = _maxSupply;
    setMaxMintAmountPerTx(_maxMintAmountPerTx);
    setHiddenMetadataUri(_hiddenMetadataUri);
  }

  function safeMint(address to, uint256 tokenId) public {
    ERC20(tokenAddress1).transferFrom(msg.sender, address(this), cost);
    _safeMint(to, tokenId);
  }

  modifier mintCompliance(uint256 _mintAmount) {
    require(
      _mintAmount > 0 && _mintAmount <= maxMintAmountPerTx,
      'Invalid mint amount!'
    );
    require(totalSupply() + _mintAmount <= maxSupply, 'Max supply exceeded!');
    _;
  }

  modifier mintPriceCompliance(uint256 _mintAmount) {
    uint256 totalCost = cost * _mintAmount;
    require(
      ERC20(tokenAddress1).balanceOf(msg.sender) >= totalCost,
      'Insufficient funds!'
    );
    _;
  }

  function whitelistMint(
    uint256 _mintAmount,
    bytes32[] calldata _merkleProof
  ) public mintCompliance(_mintAmount) mintPriceCompliance(_mintAmount) {
    // Verify whitelist requirements
    require(whitelistMintEnabled, 'The whitelist sale is not enabled!');
    require(!whitelistClaimed[_msgSender()], 'Address already claimed!');
    bytes32 leaf = keccak256(abi.encodePacked(_msgSender()));
    require(
      MerkleProof.verify(_merkleProof, merkleRoot, leaf),
      'Invalid proof!'
    );

    whitelistClaimed[_msgSender()] = true;
    safeMint(_msgSender(), _mintAmount);
  }

  function mint(
    uint256 _mintAmount
  ) public mintCompliance(_mintAmount) mintPriceCompliance(_mintAmount) {
    require(!paused, 'The contract is paused!');

    safeMint(_msgSender(), _mintAmount);
  }

  function mintForAddress(
    uint256 _mintAmount,
    address _receiver
  ) public mintCompliance(_mintAmount) onlyOwner {
    safeMint(_receiver, _mintAmount);
  }

  function _startTokenId() internal view virtual override returns (uint256) {
    return 1;
  }

  function tokenURI(
    uint256 _tokenId
  ) public view virtual override returns (string memory) {
    require(
      _exists(_tokenId),
      'ERC721Metadata: URI query for nonexistent token'
    );

    if (revealed == false) {
      return hiddenMetadataUri;
    }

    string memory currentBaseURI = _baseURI();
    return
      bytes(currentBaseURI).length > 0
        ? string(
          abi.encodePacked(currentBaseURI, _tokenId.toString(), uriSuffix)
        )
        : '';
  }

  function setRevealed(bool _state) public onlyOwner {
    revealed = _state;
  }

  function setCost(uint256 _cost) public onlyOwner {
    cost = _cost;
  }

  function setMaxMintAmountPerTx(uint256 _maxMintAmountPerTx) public onlyOwner {
    maxMintAmountPerTx = _maxMintAmountPerTx;
  }

  function setHiddenMetadataUri(
    string memory _hiddenMetadataUri
  ) public onlyOwner {
    hiddenMetadataUri = _hiddenMetadataUri;
  }

  function setUriPrefix(string memory _uriPrefix) public onlyOwner {
    uriPrefix = _uriPrefix;
  }

  function setUriSuffix(string memory _uriSuffix) public onlyOwner {
    uriSuffix = _uriSuffix;
  }

  function setPaused(bool _state) public onlyOwner {
    paused = _state;
  }

  function setMerkleRoot(bytes32 _merkleRoot) public onlyOwner {
    merkleRoot = _merkleRoot;
  }

  function setWhitelistMintEnabled(bool _state) public onlyOwner {
    whitelistMintEnabled = _state;
  }

  function withdraw() public onlyOwner nonReentrant {
    // Get the contract's ERC20 token balance
    uint256 tokenBalance = ERC20(tokenAddress1).balanceOf(address(this));

    // Transfer the ERC20 tokens to the owner
    bool success = ERC20(tokenAddress1).transfer(owner(), tokenBalance);
    require(success, 'Transfer failed');
  }

  function _baseURI() internal view virtual override returns (string memory) {
    return uriPrefix;
  }
}

