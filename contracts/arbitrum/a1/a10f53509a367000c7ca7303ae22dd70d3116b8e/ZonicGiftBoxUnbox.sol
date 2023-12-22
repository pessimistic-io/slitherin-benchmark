// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./OwnableUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./IERC20.sol";
import "./IERC721.sol";

import "./PersonalSignLib.sol";

struct TokenInfo {
  address contractAddress;
  uint256 identifier;
}

contract ZonicGiftBoxUnbox is OwnableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable, PersonalSignLib {
  event ZonicGiftBoxUnboxed(uint256 identifier, address unboxer);
  event ZonicGiftBoxRewardClaimed(address contractAddress, uint256 identifier, address claimer);

  address public zonicGiftBoxContractAddress;
  address public zonicRewardPoolAddress;
  uint256 public totalUnboxed;

  mapping (address => uint256) public burntOf;

  address private deadAddress;
  address private signerAddress;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(address _zonicGiftBoxContractAddress, address _zonicRewardPoolAddress, address _signerAddress) public initializer {
    __Ownable_init();
    __Pausable_init();

    deadAddress = 0x000000000000000000000000000000000000dEaD;

    zonicGiftBoxContractAddress = _zonicGiftBoxContractAddress;
    zonicRewardPoolAddress = _zonicRewardPoolAddress;
    signerAddress = _signerAddress;
  }

  function burn(uint256[] calldata identifiers) public whenNotPaused {
    IERC721 tokenContract = IERC721(zonicGiftBoxContractAddress);
    for (uint i = 0; i < identifiers.length; i++) {
      tokenContract.transferFrom(msg.sender, deadAddress, identifiers[i]);
      emit ZonicGiftBoxUnboxed(identifiers[i], msg.sender);
    }
    totalUnboxed += identifiers.length;
    burntOf[msg.sender] += identifiers.length;
  }

  function claimReward(
    TokenInfo[] calldata tokensInfo,
    uint8 adminSignatureV,
    bytes32 adminSignatureR,
    bytes32 adminSignatureS
  ) public whenNotPaused {
    bytes memory encodedData = abi.encodePacked(msg.sender, "%", address(this), "%", tokensInfo.length, "%", block.chainid, "%");
    for (uint i = 0; i < tokensInfo.length; i++)
      encodedData = abi.encodePacked(encodedData, tokensInfo[i].contractAddress, "%", tokensInfo[i].identifier, "%");

    require(__recoverAddress(encodedData, adminSignatureV, adminSignatureR, adminSignatureS) == signerAddress, "Invalid Signature");

    for (uint i = 0; i < tokensInfo.length; i++) {
      IERC721 tokenContract = IERC721(tokensInfo[i].contractAddress);
      tokenContract.transferFrom(zonicRewardPoolAddress, msg.sender, tokensInfo[i].identifier);
      emit ZonicGiftBoxRewardClaimed(tokensInfo[i].contractAddress, tokensInfo[i].identifier, msg.sender);
    }
  }

  /*
   * Admin Function
   */

  function setSignerAddress(address _signerAddress) external onlyOwner {
    signerAddress = _signerAddress;
  }

  function setZonicGiftBoxContractAddress(address _zonicGiftBoxContractAddress) external onlyOwner {
    zonicGiftBoxContractAddress = _zonicGiftBoxContractAddress;
  }

  function setZonicRewardPoolAddress(address _zonicRewardPoolAddress) external onlyOwner {
    zonicRewardPoolAddress = _zonicRewardPoolAddress;
  }

  /*
   * Fail Safe Function
   * in case the contract migration is required
   */

  function withdraw() public onlyOwner {
    uint256 balance = address(this).balance;
    payable(msg.sender).transfer(balance);
  }

  function withdrawERC20Token(address tokenAddress) public onlyOwner {
    IERC20 tokenContract = IERC20(tokenAddress);
    tokenContract.transfer(msg.sender, tokenContract.balanceOf(address(this)));
  }

  function withdrawERC721Token(address tokenAddress, uint256 tokenId) public onlyOwner {
    IERC721 tokenContract = IERC721(tokenAddress);
    tokenContract.safeTransferFrom(address(this), msg.sender, tokenId);
  }

  function withdrawERC721Tokens(address tokenAddress, uint256[] memory tokenIds) public onlyOwner {
    IERC721 tokenContract = IERC721(tokenAddress);
    for (uint i = 0; i < tokenIds.length; i++)
      tokenContract.safeTransferFrom(address(this), msg.sender, tokenIds[i]);
  }
}

