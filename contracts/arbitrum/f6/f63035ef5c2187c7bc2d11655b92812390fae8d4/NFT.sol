// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

// Contracts
import "./Ownable.sol";
import "./MerkleProof.sol";
import "./ERC721Enumerable.sol";
import "./ERC721PresetMinterPauserAutoId.sol";
import "./Ownable.sol";
import { IERC721 } from "./IERC721.sol";

// Libraries
import "./Counters.sol";
import { SafeERC20 } from "./SafeERC20.sol";

// Interfaces
import { IERC20 } from "./IERC20.sol";

contract MithicalPFPNFT is ERC721PresetMinterPauserAutoId, Ownable {
  using Strings for uint256;
  using Counters for Counters.Counter;
  using SafeERC20 for IERC20;

  Counters.Counter public _tokenIdTracker;

  string public baseURI;
  string public baseExtension = ".json";

  bytes32 public immutable merkleRoot;

  uint256 public startTimeStamp;
  uint256 tokenHolderPrice = 8 * 1e16;
  uint256 whitelistPrice = 10 * 1e16;
  uint256 publicPrice = 15 * 1e16;

  address gen1ContractAddress = 0xD3976f93Ac8bFC32568FBFcAEdAfFc3f96E67D5c;

  // This is a packed array of booleans.
  mapping(address => bool) private whiteListclaimed;
  mapping(uint256 => bool) isMinted;

  event OwnerMint(address user, uint256 tokenId);
  event WhitelistMint(address user, uint256 tokenId);
  event GeneralMint(address user, uint256 tokenId);

  constructor(
    string memory _name,
    string memory _symbol,
    string memory _initBaseURI,
    bytes32 _merkleRoot
  ) ERC721PresetMinterPauserAutoId(_name, _symbol, _initBaseURI) {
    setBaseURI(_initBaseURI);
    merkleRoot = _merkleRoot;

    _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
    _setupRole(MINTER_ROLE, _msgSender());
    _setupRole(PAUSER_ROLE, _msgSender());
    for (uint256 i = 0; i < 15; i++) {
      internalMint(_msgSender(), false);
    }
    for (uint256 i = 1001; i <= 1010; i++) {
      _safeMint(_msgSender(), i);
    }
    burn(0);
    startTimeStamp = block.timestamp;
  }

  receive() external payable {
    assert(msg.sender != tx.origin);
  }

  function internalMint(address _to, bool isWhitelistMint) internal {
    while (isMinted[_tokenIdTracker.current()]) {
      _tokenIdTracker.increment();
    }
    require(_tokenIdTracker.current() <= 1000, "Sale has already ended");
    _safeMint(_to, _tokenIdTracker.current());
    isMinted[_tokenIdTracker.current()] = true;
    _tokenIdTracker.increment();
    if (isWhitelistMint) {
      _setClaimed(_to);
      emit WhitelistMint(_to, _tokenIdTracker.current());
    } else {
      emit GeneralMint(_to, _tokenIdTracker.current());
    }
  }

  function withdraw(address[] calldata tokens) public onlyOwner {
    payable(msg.sender).transfer(address(this).balance);

    for (uint256 i = 0; i < tokens.length; i++) {
      IERC20 token = IERC20(tokens[i]);
      token.safeTransfer(msg.sender, token.balanceOf(address(this)));
    }
  }

  // gen 1 holders mint
  function ownerMint(uint256 tokenId) public payable {
    require(isMinted[tokenId] == false);
    require(
      IERC721(gen1ContractAddress).ownerOf(tokenId) == _msgSender(),
      "minter is not the owner"
    );
    if (block.timestamp <= startTimeStamp + 144000) {
      require(
        msg.value == tokenHolderPrice,
        "amount sent less than mint price"
      );
    } else {
      require(msg.value == whitelistPrice, "amount sent less than mint price");
    }
    _safeMint(_msgSender(), tokenId);
    isMinted[tokenId] = true;
    emit OwnerMint(_msgSender(), tokenId);
  }

  // whitelist mint
  function whitelistMint(address account, bytes32[] calldata merkleProof)
    public
    payable
  {
    require(
      block.timestamp > (startTimeStamp + 86400),
      "whitelist mint is not open"
    );
    require(
      block.timestamp <= startTimeStamp + 144000,
      "Whitelist mint is over"
    );
    require(!isClaimed(account), "Drop already claimed.");

    require(msg.value == whitelistPrice, 'amount sent less than mint price"');

    // Verify the merkle proof.
    bytes32 node = keccak256(abi.encodePacked(account));
    require(
      MerkleProof.verify(merkleProof, merkleRoot, node),
      "Invalid proof."
    );

    internalMint(account, true);
  }

  // normal mint
  function generalMint() public payable {
    require(
      block.timestamp > (startTimeStamp + 144000),
      "public mint is not open"
    );
    require(msg.value == publicPrice, "amount sent less than mint price");

    internalMint(_msgSender(), false);
  }

  function checkIfMinted(uint256 tokenId) public view returns (bool) {
    return isMinted[tokenId];
  }

  function isClaimed(address account) public view returns (bool) {
    return whiteListclaimed[account];
  }

  function _setClaimed(address account) private {
    whiteListclaimed[account] = true;
  }

  //only owner
  function setBaseURI(string memory _newBaseURI) public onlyOwner {
    baseURI = _newBaseURI;
  }

  function setBaseExtension(string memory _newBaseExtension) public onlyOwner {
    baseExtension = _newBaseExtension;
  }

  // internal
  function _baseURI() internal view virtual override returns (string memory) {
    return baseURI;
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

    string memory currentBaseURI = _baseURI();
    return
      bytes(currentBaseURI).length > 0
        ? string(
          abi.encodePacked(currentBaseURI, tokenId.toString(), baseExtension)
        )
        : "";
  }
}

