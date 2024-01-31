/*
  ･
   *　★
      ･ ｡
        　･　ﾟ☆ ｡
  　　　 *　★ ﾟ･｡ *  ｡
          　　* ☆ ｡･ﾟ*.｡
      　　　ﾟ *.｡☆｡★　･
​
                      `                     .-:::::-.`              `-::---...```
                     `-:`               .:+ssssoooo++//:.`       .-/+shhhhhhhhhhhhhyyyssooo:
                    .--::.            .+ossso+/////++/:://-`   .////+shhhhhhhhhhhhhhhhhhhhhy
                  `-----::.         `/+////+++///+++/:--:/+/-  -////+shhhhhhhhhhhhhhhhhhhhhy
                 `------:::-`      `//-.``.-/+ooosso+:-.-/oso- -////+shhhhhhhhhhhhhhhhhhhhhy
                .--------:::-`     :+:.`  .-/osyyyyyyso++syhyo.-////+shhhhhhhhhhhhhhhhhhhhhy
              `-----------:::-.    +o+:-.-:/oyhhhhhhdhhhhhdddy:-////+shhhhhhhhhhhhhhhhhhhhhy
             .------------::::--  `oys+/::/+shhhhhhhdddddddddy/-////+shhhhhhhhhhhhhhhhhhhhhy
            .--------------:::::-` +ys+////+yhhhhhhhddddddddhy:-////+yhhhhhhhhhhhhhhhhhhhhhy
          `----------------::::::-`.ss+/:::+oyhhhhhhhhhhhhhhho`-////+shhhhhhhhhhhhhhhhhhhhhy
         .------------------:::::::.-so//::/+osyyyhhhhhhhhhys` -////+shhhhhhhhhhhhhhhhhhhhhy
       `.-------------------::/:::::..+o+////+oosssyyyyyyys+`  .////+shhhhhhhhhhhhhhhhhhhhhy
       .--------------------::/:::.`   -+o++++++oooosssss/.     `-//+shhhhhhhhhhhhhhhhhhhhyo
     .-------   ``````.......--`        `-/+ooooosso+/-`          `./++++///:::--...``hhhhyo
                                              `````
   *　
      ･ ｡
　　　　･　　ﾟ☆ ｡
  　　　 *　★ ﾟ･｡ *  ｡
          　　* ☆ ｡･ﾟ*.｡
      　　　ﾟ *.｡☆｡★　･
    *　　ﾟ｡·*･｡ ﾟ*
  　　　☆ﾟ･｡°*. ﾟ
　 ･ ﾟ*｡･ﾟ★｡
　　･ *ﾟ｡　　 *
　･ﾟ*｡★･
 ☆∴｡　*
･ ｡
*/

// SPDX-License-Identifier: MIT OR Apache-2.0

pragma solidity ^0.8.12;

import "./Context.sol";
import "./Initializable.sol";
import "./ReentrancyGuardUpgradeable.sol";

import "./Constants.sol";
import "./FETHNode.sol";
import "./FoundationTreasuryNode.sol";
import "./MarketFees.sol";
import "./MarketSharedCore.sol";
import "./SendValueWithFallbackWithdraw.sol";
import "./RouterContext.sol";

import "./NFTMarketAuction.sol";
import "./NFTMarketBuyPrice.sol";
import "./NFTMarketCore.sol";
import "./NFTMarketOffer.sol";
import "./NFTMarketPrivateSaleGap.sol";
import "./NFTMarketReserveAuction.sol";
import "./NFTMarketExhibition.sol";

/**
 * @title A market for NFTs on Foundation.
 * @notice The Foundation marketplace is a contract which allows traders to buy and sell NFTs.
 * It supports buying and selling via auctions, private sales, buy price, and offers.
 * @dev All sales in the Foundation market will pay the creator 10% royalties on secondary sales. This is not specific
 * to NFTs minted on Foundation, it should work for any NFT. If royalty information was not defined when the NFT was
 * originally deployed, it may be added using the [Royalty Registry](https://royaltyregistry.xyz/) which will be
 * respected by our market contract.
 * @author batu-inal & HardlyDifficult
 */
contract NFTMarket is
  Initializable,
  FoundationTreasuryNode,
  Context,
  RouterContext,
  FETHNode,
  MarketSharedCore,
  NFTMarketCore,
  ReentrancyGuardUpgradeable,
  SendValueWithFallbackWithdraw,
  MarketFees,
  NFTMarketExhibition,
  NFTMarketAuction,
  NFTMarketReserveAuction,
  NFTMarketPrivateSaleGap,
  NFTMarketBuyPrice,
  NFTMarketOffer
{
  /**
   * @notice Set immutable variables for the implementation contract.
   * @dev Using immutable instead of constants allows us to use different values on testnet.
   * @param treasury The Foundation Treasury contract address.
   * @param feth The FETH ERC-20 token contract address.
   * @param royaltyRegistry The Royalty Registry contract address.
   * @param duration The duration of the auction in seconds.
   */
  constructor(address payable treasury, address feth, address royaltyRegistry, uint256 duration, address router)
    FoundationTreasuryNode(treasury)
    FETHNode(feth)
    MarketFees(
      /* protocolFeeInBasisPoints: */
      500,
      royaltyRegistry,
      /* assumePrimarySale: */
      false
    )
    NFTMarketReserveAuction(duration)
    RouterContext(router)
  {
    _disableInitializers();
  }

  /**
   * @notice Called once to configure the contract after the initial proxy deployment.
   * @dev This farms the initialize call out to inherited contracts as needed to initialize mutable variables.
   */
  function initialize() external initializer {
    ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
    NFTMarketAuction._initializeNFTMarketAuction();
  }

  /**
   * @inheritdoc NFTMarketCore
   */
  function _beforeAuctionStarted(address nftContract, uint256 tokenId)
    internal
    override(NFTMarketCore, NFTMarketBuyPrice, NFTMarketOffer)
  {
    // This is a no-op function required to avoid compile errors.
    super._beforeAuctionStarted(nftContract, tokenId);
  }

  /**
   * @inheritdoc NFTMarketCore
   */
  function _transferFromEscrow(address nftContract, uint256 tokenId, address recipient, address authorizeSeller)
    internal
    override(NFTMarketCore, NFTMarketReserveAuction, NFTMarketBuyPrice)
  {
    // This is a no-op function required to avoid compile errors.
    super._transferFromEscrow(nftContract, tokenId, recipient, authorizeSeller);
  }

  /**
   * @inheritdoc NFTMarketCore
   */
  function _transferFromEscrowIfAvailable(address nftContract, uint256 tokenId, address recipient)
    internal
    override(NFTMarketCore, NFTMarketReserveAuction, NFTMarketBuyPrice)
  {
    // This is a no-op function required to avoid compile errors.
    super._transferFromEscrowIfAvailable(nftContract, tokenId, recipient);
  }

  /**
   * @inheritdoc NFTMarketCore
   */
  function _transferToEscrow(address nftContract, uint256 tokenId)
    internal
    override(NFTMarketCore, NFTMarketReserveAuction, NFTMarketBuyPrice)
  {
    // This is a no-op function required to avoid compile errors.
    super._transferToEscrow(nftContract, tokenId);
  }

  /**
   * @inheritdoc MarketSharedCore
   */
  function _getSellerOf(address nftContract, uint256 tokenId)
    internal
    view
    override(MarketSharedCore, NFTMarketCore, NFTMarketReserveAuction, NFTMarketBuyPrice)
    returns (address payable seller)
  {
    // This is a no-op function required to avoid compile errors.
    seller = super._getSellerOf(nftContract, tokenId);
  }

  function _msgSender() internal view override(Context, RouterContext) returns (address sender) {
    sender = super._msgSender();
  }
}

