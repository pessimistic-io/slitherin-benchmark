// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./IERC20.sol";
import "./IERC721.sol";
import "./IERC721Receiver.sol";
import "./EIP712Upgradeable.sol";
import "./ECDSAUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./IERC20.sol";
import "./IERC721.sol";
import "./IERC721Receiver.sol";

import "./OrderProcessorUpgradable.sol";
import "./PersonalSignLib.sol";

import {   _revertWithUnsupportedCannotBuyYourOwnItem } from "./OrderErrors.sol";

contract ZonicMarketplace is OrderProcessorUpgradable, ReentrancyGuardUpgradeable, PersonalSignLib {
  event ZonicBasicOrderFulfilled(address offerer, address buyer, address token, uint256 identifier, address currency, uint256 totalPrice, uint256 creatorFee, uint256 marketplaceFee, address saleId);
  event ZonicBasicOrderCanceled(address offerer, address token, uint256 identifier, address saleId);

  address signerAddress;
  address adminAddress;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(string memory signDomainName, string memory signVersion, uint256 _maxCreatorFeePercentage, uint256 _marketplaceFeePercentage, address _marketplaceFeePayoutAddress, address _signerAddress, address _adminAddress) public initializer {
    __OrderProcessor_init(signDomainName, signVersion, _maxCreatorFeePercentage, _marketplaceFeePercentage, _marketplaceFeePayoutAddress);
    __ReentrancyGuard_init();
    signerAddress = _signerAddress;
    adminAddress = _adminAddress;
  }

  function fulfillBasicOrder(
    Listing calldata listing,
    bytes calldata signature,
    uint8 adminSignatureV,
    bytes32 adminSignatureR,
    bytes32 adminSignatureS,
    uint32 adminSigExpiredAt
  ) external payable whenNotPaused nonReentrant {
    require(__recoverAddress(abi.encodePacked(listing.saleId, "%", adminSigExpiredAt, "%", block.chainid), adminSignatureV, adminSignatureR, adminSignatureS) == signerAddress, "Invalid admin Signature");
    require(adminSigExpiredAt > block.timestamp, "Admin signature is expired");

    // Offerer and buyer could not be the same address
    if (listing.offerer == msg.sender)
      _revertWithUnsupportedCannotBuyYourOwnItem();

    uint256 marketplaceFee;
    uint256 totalPrice;
    uint256 totalCreatorFee;
    (totalPrice, totalCreatorFee, marketplaceFee) = __validateOrderForFulfill(listing, signature);

    // Mark Sale Id used
    __markSaleIdUsed(listing.saleId);

    // Send Event ahead of Transfer event
    __emitZonicBasicOrderFulfilledEvent(listing, totalPrice, totalCreatorFee, marketplaceFee);

    // -------------------
    // -- Process Order --
    // -------------------

    // Transfer Offered Item
    for (uint i = 0; i < listing.offers.length; i++) {
      IERC721 tokenContract = IERC721(listing.offers[i].token);
      tokenContract.safeTransferFrom(listing.offerer, msg.sender, listing.offers[i].identifier);
    }

    // Transfer Offerer payout
    payable(listing.offererPayout.recipient).transfer(listing.offererPayout.amount);

    // Transfer Creator Payouts
    for (uint i = 0; i < listing.creatorPayouts.length; i++)
      payable(listing.creatorPayouts[i].recipient).transfer(listing.creatorPayouts[i].amount);

    // Transfer Marketplace Fee
    payable(marketplaceFeePayoutAddress).transfer(marketplaceFee);
  }

  function __emitZonicBasicOrderFulfilledEvent(
    Listing calldata listing,
    uint256 totalPrice,
    uint256 totalCreatorFee,
    uint256 marketplaceFee
  ) private {
    emit ZonicBasicOrderFulfilled(
      listing.offerer,
      msg.sender,
      listing.offers[0].token,
      listing.offers[0].identifier,
      listing.offererPayout.token,
      totalPrice,
      totalCreatorFee,
      marketplaceFee,
      listing.saleId);
  }

  function cancelBasicOrder(
    Listing calldata listing,
    bytes calldata signature
  ) external whenNotPaused nonReentrant {
    // Check if caller is of offerer or admin
    require(msg.sender == listing.offerer || msg.sender == adminAddress, "Caller is not offerer or admin");

    __validateOrderForCancelation(listing, signature);
    __markSaleIdUsed(listing.saleId);
    emit ZonicBasicOrderCanceled(
      listing.offerer,
      listing.offers[0].token,
      listing.offers[0].identifier,
      listing.saleId);
  }

  /* Admin Functions */

  function setSignerAddress(address _signerAddress) public onlyOwner {
    signerAddress = _signerAddress;
  }

  function setAdminAddress(address _adminAddress) public onlyOwner {
    adminAddress = _adminAddress;
  }

  function pause() public {
    require(_msgSender() == owner() || _msgSender() == adminAddress, "Caller does not have permission");
    _pause();
  }

  function unpause() public {
    require(_msgSender() == owner() || _msgSender() == adminAddress, "Caller does not have permission");
    _unpause();
  }

  // Storage Gap
  uint256[50] __gap;
}

