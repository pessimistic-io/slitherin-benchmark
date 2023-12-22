pragma solidity ^0.8.0;
//SPDX-License-Identifier: MIT

import "./Ownable.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./ISignature.sol";
import "./IEllerianHero.sol";

/// No Mints Left.
error InsufficientQuantity(); 

/// Bad User Input
error BadUserInput();

/// No ongoing mints.
error NoOngoingMint();

/// @title [Tales of Elleria - Heroes] Mint Manager. 
/// @author Wayne (Ellerian Prince)
/// @notice Allows minting of heroes using ERC20 tokens.
/// @dev Requires owner to set up mint cycles via SetMintCycle.
/// maximumMintable in EllerianHero need to be adjusted for seasons beyond dawn.
/// This contract needs to be set as the tokenMinterAddress in EllerianHero.
contract ElleriaHeroMintManager is Ownable, ReentrancyGuard {
  using SafeERC20 for IERC20;

  /// @notice Address receiving the ERC20 Tokens used for minting.
  address public safeAddr;

  /// @notice Address of the ERC20 Token used to mint.
  address public erc20Address;

  /// @dev ABI of the ERC721 Token to mint.
  IEllerianHero private heroAbi;

  /// @notice Price of this mint cycle.
  uint256 public mintPrice;

  /// @notice ID of this mint cycle.
  uint256 public cycleId;

  /// @notice Maximum mints this cycle.
  uint256 public maxMints;

  /// @notice Mints left this cycle.
  uint256 public mintsLeft;

  /// @notice Variant of this mint cycle.
  uint256 public mintVariant;

  /// @notice Date to allow mints
  uint public mintOpeningTime;


  /// @dev Initializes fixed dependencies.
  /// @param _heroAddress Address of the Ellerian Hero ERC721.
  /// @param _safeAddress Address of Project Treasury.
  /// @param _erc20Address Address of the ERC20 token used to mint.
  constructor(address _heroAddress, address _safeAddress, address _erc20Address)
  {
     heroAbi = IEllerianHero(_heroAddress);
     erc20Address = _erc20Address;
     safeAddr = _safeAddress;
     mintsLeft = 0;
  }

  /// @dev Owner only. Prepares a new mint cycle.
  /// @param _cycleId ID of this cycle.
  /// @param _max Maximum mints this cycle.
  /// @param _price Mint price in WEI.
  /// @param _variant Mint Variant.
  /// @param _mintOpeningTime Mint Opening Date.
  function SetMintCycle(uint256 _cycleId, uint256 _max, uint256 _price, uint256 _variant, uint _mintOpeningTime) 
  external onlyOwner {
    if (_price < 1000000000000000000) {
      revert BadUserInput();
    }

    maxMints = _max;
    mintsLeft = _max;
    cycleId = _cycleId;
    mintPrice = _price;
    mintVariant = _variant;
    mintOpeningTime = _mintOpeningTime;

    emit CycleReset(cycleId, maxMints, mintPrice, mintVariant, mintOpeningTime);
  }

  /// @dev Owner only. Updates the mint opening date.
  /// @param _mintOpeningTime Date when the mint starts.
  function SetMintTime(uint _mintOpeningTime) external onlyOwner {
    mintOpeningTime = _mintOpeningTime;
    emit MintDateChange(_mintOpeningTime);
  }

    /// @dev Owner only. Updates the erc20 Address.
  /// @param _erc20Address New Erc20 Address to Receive.
  function SetErc20Address(address _erc20Address) external onlyOwner {
    if (_erc20Address == address(0)) {
      revert BadUserInput();
    }

    erc20Address = _erc20Address;
    emit Erc20AddressChange(_erc20Address);
  }

  /// @notice Mint heroes
  /// @param quantity Quantity to mint.
  function Mint(uint256 quantity) external nonReentrant {
    if(mintsLeft < quantity) {
      revert InsufficientQuantity();
    }

    if (block.timestamp < mintOpeningTime) {
      revert NoOngoingMint();
    }

    // Transfer funds from caller to treasury.
    uint256 totalMintValue = mintPrice * quantity;
    IERC20(erc20Address).safeTransferFrom(msg.sender, safeAddr, totalMintValue);

    // Mint heroes to the caller.
    mintsLeft -= quantity;
    heroAbi.mintUsingToken(msg.sender, quantity, mintVariant);
    emit Minted(msg.sender, totalMintValue, quantity, cycleId);
  }



  // Events
  event Minted(address indexed minter, uint256 mintValue, uint256 quantity, uint256 cycleId);
  event CycleReset(uint256 cycleId, uint256 quantity, uint256 price, uint256 variant, uint mintOpeningTime);
  event MintDateChange(uint mintOpeningTime);
  event Erc20AddressChange(address erc20Address);
}

