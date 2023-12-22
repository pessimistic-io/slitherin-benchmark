// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./ERC721A.sol";
import "./Address.sol";

error BeanCannotBeClaimed();
error ClaimWindowNotOpen();
error MismatchedTokenOwner();
error MaxSupplyReached();
error TokenAlreadyWon();
error AddressAlreadyWonOrOwner();
error RaffleWinnerIsContract();
error ChunkHasBeenAirdropped();
error AzukiNotOwnedLongEnough();
error InvalidChunk();

contract Beanz is ERC721A {
  using Address for address;

  uint256 public immutable maxSupply;
  uint256 public constant BATCH_SIZE = 6;
  uint256 public constant MIN_OWNERSHIP_TIME_FOR_CLAIM = 120;

  string private _baseTokenURI;

  mapping(address => bool) owners;

  modifier onlyOwner() {
      require(owners[msg.sender], "Not owner");
      _;
  }

  constructor(
    uint256 _maxSupply,
    string memory initialName,
    string memory initialSymbol
  ) ERC721A('Beanz', 'BEANZ') {
    owners[msg.sender] = true;
    maxSupply = _maxSupply;
    _nameOverride = initialName;
    _symbolOverride = initialSymbol;
  }

  function addOwner(address _newOwner) external onlyOwner {
      owners[_newOwner] = true;
  }

  // Used to claim unclaimed tokens after airdrop/claim phase
  function devClaim(uint256 numToMint) external onlyOwner {
    _mintWrapper(msg.sender, numToMint);
  }

  function _mintWrapper(address to, uint256 numToMint) internal {
    if (totalSupply() + numToMint > maxSupply) {
      revert MaxSupplyReached();
    }
    uint256 numBatches = numToMint / BATCH_SIZE;
    for (uint256 i; i < numBatches; ++i) {
      _mint(to, BATCH_SIZE, '', true);
    }
    if (numToMint % BATCH_SIZE > 0) {
      _mint(to, numToMint % BATCH_SIZE, '', true);
    }
  }

  function _baseURI() internal view virtual override returns (string memory) {
    return _baseTokenURI;
  }

  function setBaseURI(string calldata baseURI) external onlyOwner {
    _baseTokenURI = baseURI;
  }

  string private _nameOverride;
  string private _symbolOverride;

  function name() public view override returns (string memory) {
    if (bytes(_nameOverride).length == 0) {
      return ERC721A.name();
    }
    return _nameOverride;
  }

  function symbol() public view override returns (string memory) {
    if (bytes(_symbolOverride).length == 0) {
      return ERC721A.symbol();
    }
    return _symbolOverride;
  }

  function setNameAndSymbol(
    string calldata _newName,
    string calldata _newSymbol
  ) external onlyOwner {
    _nameOverride = _newName;
    _symbolOverride = _newSymbol;
  }
}
