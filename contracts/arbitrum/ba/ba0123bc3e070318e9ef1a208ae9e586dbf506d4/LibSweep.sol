// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./IERC721.sol";
import "./IERC1155.sol";
import "./SafeERC20.sol";
import { BuyItemParams } from "./ITroveMarketplace.sol";

import { LibDiamond } from "./LibDiamond.sol";
import { LibMarketplaces, MarketplaceType } from "./LibMarketplaces.sol";

import "./BuyError.sol";
import "./ANFTReceiver.sol";
import "./SettingsBitFlag.sol";
import "./ITroveMarketplace.sol";

import "./BuyOrder.sol";

import "./SwapInput.sol";

import "./ConsiderationStructs.sol";
import "./SeaportInterface.sol";

import "./IShiftSweeperEvents.sol";
// import "@forge-std/src/console.sol";

error InvalidNFTAddress();
error FirstBuyReverted(bytes message);
error AllReverted();

error InvalidMsgValue();
error MsgValueShouldBeZero();
error PaymentTokenNotGiven(address _paymentToken);
error NotEnoughPaymentToken(address _paymentToken, uint256 _amount);

library LibSweep {
  using SafeERC20 for IERC20;

  event SuccessBuyItemTrove(
    address indexed _nftAddress,
    uint256 _tokenId,
    address indexed _buyer,
    uint256 _quantity,
    uint256 _price
  );

  event FailBuyItemTrove(
    address indexed _nftAddress,
    uint256 _tokenId,
    address indexed _buyer,
    uint256 _quantity,
    uint256 _price,
    bytes _errorReason
  );

  event SuccessBuyItemOpensea(
    address indexed _nftAddress,
    uint256 _tokenId,
    address indexed _buyer,
    uint256 _quantity,
    uint256 _price
  );

  event FailBuyItemOpensea(
    address indexed _nftAddress,
    uint256 _tokenId,
    address indexed _buyer,
    uint256 _quantity,
    uint256 _price
  );

  event RefundedToken(address tokenAddress, uint256 amount);

  bytes32 constant DIAMOND_STORAGE_POSITION =
    keccak256("diamond.standard.sweep.storage");

  struct SweepStorage {
    // owner of the contract
    uint256 sweepFee;
    bool feelessNFTActive;
    IERC1155 sweepNFT;
  }
  // uint256 constant SWEEP_NFT_ID = 0;

  uint256 constant FEE_BASIS_POINTS = 1_000_000;

  bytes4 internal constant INTERFACE_ID_ERC721 = 0x80ac58cd;
  bytes4 internal constant INTERFACE_ID_ERC1155 = 0xd9b67a26;

  function DS() internal pure returns (SweepStorage storage ds) {
    bytes32 position = DIAMOND_STORAGE_POSITION;
    assembly {
      ds.slot := position
    }
  }

  function _calculateFee(uint256 _amount) internal view returns (uint256) {
    SweepStorage storage ds = DS();
    return (_amount * ds.sweepFee) / FEE_BASIS_POINTS;
  }

  function _calculateAmountWithoutFees(uint256 _amountWithFee)
    internal
    view
    returns (uint256)
  {
    SweepStorage storage ds = DS();
    return ((_amountWithFee * FEE_BASIS_POINTS) /
      (FEE_BASIS_POINTS + ds.sweepFee));
  }

  function _refundBuyerAllPaymentTokens(
    address[] memory _paymentTokens,
    uint256[] memory _maxSpendIncFees,
    uint256[] memory _totalSpentAmounts
  ) internal {
    // LibSweep.SweepStorage memory sweepStorage = LibSweep.DS();
    // if (sweepStorage.feelessNFTActive) {
    //   try
    //     IERC1155(sweepStorage.sweepNFT).balanceOf(
    //       msg.sender,
    //       LibSweep.SWEEP_NFT_ID
    //     )
    //   returns (uint256 balanceFeeLessNFT) {
    //     if (balanceFeeLessNFT > 0) {
    //       LibSweep._refundBuyerWithoutFees(
    //         _paymentTokens,
    //         _maxSpendIncFees,
    //         _totalSpentAmounts
    //       );
    //     } else {
    //       LibSweep._refundBuyer(
    //         _paymentTokens,
    //         _maxSpendIncFees,
    //         _totalSpentAmounts
    //       );
    //     }
    //   } catch {
    //     LibSweep._refundBuyer(
    //       _paymentTokens,
    //       _maxSpendIncFees,
    //       _totalSpentAmounts
    //     );
    //   }
    // } else {
    LibSweep._refundBuyer(_paymentTokens, _maxSpendIncFees, _totalSpentAmounts);
    // }
  }

  function _refundBuyer(
    address[] memory _paymentTokens,
    uint256[] memory _maxSpendIncFees,
    uint256[] memory _totalSpentAmounts
  ) internal {
    uint256 paymentTokens = _paymentTokens.length;
    for (uint256 i = 0; i < paymentTokens; ) {
      uint256 totalIncFees = (_totalSpentAmounts[i] +
        LibSweep._calculateFee(_totalSpentAmounts[i]));
      if (totalIncFees <= _maxSpendIncFees[i]) {
        uint256 refundAmount = _maxSpendIncFees[i] - totalIncFees;
        if (refundAmount > 0) {
          if (_paymentTokens[i] == address(0)) {
            payable(msg.sender).transfer(_maxSpendIncFees[i] - totalIncFees);
          } else {
            IERC20(_paymentTokens[i]).safeTransfer(
              msg.sender,
              _maxSpendIncFees[i] - totalIncFees
            );
          }
        }
      } else revert NotEnoughPaymentToken(_paymentTokens[i], totalIncFees);

      unchecked {
        ++i;
      }
    }
  }

  function _refundBuyerWithoutFees(
    address[] memory _paymentTokens,
    uint256[] memory _maxSpendIncFees,
    uint256[] memory _totalSpentAmounts
  ) internal {
    uint256 paymentTokens = _paymentTokens.length;
    for (uint256 i = 0; i < paymentTokens; ++i) {
      uint256 totalIncFees = _totalSpentAmounts[i];
      if (totalIncFees <= _maxSpendIncFees[i]) {
        uint256 refundAmount = _maxSpendIncFees[i] - totalIncFees;
        if (refundAmount > 0) {
          if (_paymentTokens[i] == address(0)) {
            payable(msg.sender).transfer(_maxSpendIncFees[i] - totalIncFees);
          } else {
            IERC20(_paymentTokens[i]).safeTransfer(
              msg.sender,
              _maxSpendIncFees[i] - totalIncFees
            );
          }
        }
      } else revert NotEnoughPaymentToken(_paymentTokens[i], totalIncFees);

      unchecked {
        ++i;
      }
    }
  }

  function _maxSpendWithoutFees(uint256[] memory _maxSpendIncFees)
    internal
    view
    returns (uint256[] memory maxSpends)
  {
    uint256 maxSpendLength = _maxSpendIncFees.length;
    maxSpends = new uint256[](maxSpendLength);
    for (uint256 i = 0; i < maxSpendLength; ) {
      maxSpends[i] = LibSweep._calculateAmountWithoutFees(_maxSpendIncFees[i]);
      unchecked {
        ++i;
      }
    }
  }

  function _buyOrdersMultiTokens(
    MultiTokenBuyOrder[] memory _buyOrders,
    uint16 _inputSettingsBitFlag,
    address[] memory _paymentTokens,
    uint256[] memory _maxSpends
  )
    internal
    returns (uint256[] memory totalSpentAmounts, uint256 successCount)
  {
    totalSpentAmounts = new uint256[](_paymentTokens.length);
    // buy all assets
    for (uint256 i = 0; i < _buyOrders.length; ++i) {
      MultiTokenBuyOrder memory _buyOrder = _buyOrders[i];

      if (_buyOrder.marketplaceType == MarketplaceType.TROVE) {
        // check if the listing exists

        BuyItemParams memory buyItemParamsOrder = abi.decode(
          _buyOrder.orderData,
          (BuyItemParams)
        );

        uint64 quantityToBuy = 0;
        uint256 pricesPerItem = 0;
        uint256 totalPrice = 0;
        ITroveMarketplace.ListingOrBid memory listing = ITroveMarketplace(
          _buyOrder.marketplaceAddress
        ).listings(
            buyItemParamsOrder.nftAddress,
            buyItemParamsOrder.tokenId,
            buyItemParamsOrder.owner
          );

        // check if total price is less than max spend allowance left
        if (
          (listing.pricePerItem * buyItemParamsOrder.quantity) >
          (_maxSpends[_buyOrder.tokenIndex] -
            totalSpentAmounts[_buyOrder.tokenIndex]) &&
          SettingsBitFlag.checkSetting(
            _inputSettingsBitFlag,
            SettingsBitFlag.EXCEEDING_MAX_SPEND
          )
        ) break;
        // not enough listed items
        if (listing.quantity < buyItemParamsOrder.quantity) {
          if (
            SettingsBitFlag.checkSetting(
              _inputSettingsBitFlag,
              SettingsBitFlag.INSUFFICIENT_QUANTITY_ERC1155
            )
          ) quantityToBuy = listing.quantity;
          else continue; // skip item
        } else {
          quantityToBuy = buyItemParamsOrder.quantity;
        }

        pricesPerItem = listing.pricePerItem;
        totalPrice += listing.pricePerItem * quantityToBuy;

        BuyItemParams[] memory buyItemParamsArr = new BuyItemParams[](1);
        buyItemParamsArr[0] = buyItemParamsOrder;
        // buy item
        (bool success, bytes memory data) = _buyOrder.marketplaceAddress.call{
          value: (buyItemParamsOrder.usingEth) ? (totalPrice) : 0
        }(
          abi.encodeWithSelector(
            ITroveMarketplace.buyItems.selector,
            buyItemParamsArr
          )
        );

        if (success) {
          if (
            SettingsBitFlag.checkSetting(
              _inputSettingsBitFlag,
              SettingsBitFlag.EMIT_SUCCESS_EVENT_LOGS
            )
          ) {
            emit LibSweep.SuccessBuyItemTrove(
              buyItemParamsOrder.nftAddress,
              buyItemParamsOrder.tokenId,
              payable(msg.sender),
              quantityToBuy,
              pricesPerItem
            );
          }
          if (
            IERC165(buyItemParamsOrder.nftAddress).supportsInterface(
              LibSweep.INTERFACE_ID_ERC721
            )
          ) {
            IERC721(buyItemParamsOrder.nftAddress).safeTransferFrom(
              address(this),
              msg.sender,
              buyItemParamsOrder.tokenId
            );
          } else if (
            IERC165(buyItemParamsOrder.nftAddress).supportsInterface(
              LibSweep.INTERFACE_ID_ERC1155
            )
          ) {
            IERC1155(buyItemParamsOrder.nftAddress).safeTransferFrom(
              address(this),
              msg.sender,
              buyItemParamsOrder.tokenId,
              quantityToBuy,
              ""
            );
          } else revert InvalidNFTAddress();
          totalSpentAmounts[_buyOrder.tokenIndex] += totalPrice;
          successCount++;
        } else {
          if (
            SettingsBitFlag.checkSetting(
              _inputSettingsBitFlag,
              SettingsBitFlag.EMIT_FAILURE_EVENT_LOGS
            )
          ) {
            emit LibSweep.FailBuyItemTrove(
              buyItemParamsOrder.nftAddress,
              buyItemParamsOrder.tokenId,
              payable(msg.sender),
              buyItemParamsOrder.quantity,
              pricesPerItem,
              data
            );
          }
          if (
            SettingsBitFlag.checkSetting(
              _inputSettingsBitFlag,
              SettingsBitFlag.MARKETPLACE_BUY_ITEM_REVERTED
            )
          ) revert FirstBuyReverted(data);
        }
      } else if (_buyOrder.marketplaceType == MarketplaceType.SEAPORT_V1) {
        // check if total price is less than max spend allowance left

        BasicOrderParameters memory osOrderParams = abi.decode(
          _buyOrder.orderData,
          (BasicOrderParameters)
        );

        if (
          (osOrderParams.considerationAmount * osOrderParams.offerAmount) >
          _maxSpends[_buyOrder.tokenIndex] -
            totalSpentAmounts[_buyOrder.tokenIndex] &&
          SettingsBitFlag.checkSetting(
            _inputSettingsBitFlag,
            SettingsBitFlag.EXCEEDING_MAX_SPEND
          )
        ) break;

        uint256 quantityToBuy = osOrderParams.offerAmount;
        uint256 totalPrice = osOrderParams.considerationAmount;
        bool success = SeaportInterface(_buyOrder.marketplaceAddress)
          .fulfillBasicOrder(osOrderParams);

        if (success) {
          if (
            SettingsBitFlag.checkSetting(
              _inputSettingsBitFlag,
              SettingsBitFlag.EMIT_SUCCESS_EVENT_LOGS
            )
          ) {
            emit LibSweep.SuccessBuyItemOpensea(
              osOrderParams.offerToken,
              osOrderParams.offerIdentifier,
              payable(msg.sender),
              quantityToBuy,
              totalPrice
            );
          }
          if (
            IERC165(osOrderParams.offerToken).supportsInterface(
              LibSweep.INTERFACE_ID_ERC721
            )
          ) {
            IERC721(osOrderParams.offerToken).safeTransferFrom(
              address(this),
              msg.sender,
              osOrderParams.offerIdentifier
            );
          } else if (
            IERC165(osOrderParams.offerToken).supportsInterface(
              LibSweep.INTERFACE_ID_ERC1155
            )
          ) {
            IERC1155(osOrderParams.offerToken).safeTransferFrom(
              address(this),
              msg.sender,
              osOrderParams.offerIdentifier,
              quantityToBuy,
              ""
            );
          } else revert InvalidNFTAddress();
          totalSpentAmounts[_buyOrder.tokenIndex] += totalPrice;
          successCount++;
        } else {
          if (
            SettingsBitFlag.checkSetting(
              _inputSettingsBitFlag,
              SettingsBitFlag.EMIT_FAILURE_EVENT_LOGS
            )
          ) {
            emit LibSweep.FailBuyItemOpensea(
              osOrderParams.offerToken,
              osOrderParams.offerIdentifier,
              payable(msg.sender),
              quantityToBuy,
              totalPrice
            );
          }
          if (
            SettingsBitFlag.checkSetting(
              _inputSettingsBitFlag,
              SettingsBitFlag.MARKETPLACE_BUY_ITEM_REVERTED
            )
          ) revert FirstBuyReverted("Seaport V1 buy reverted");
        }
      } else revert InvalidMarketplaceId();
    }
  }
}

