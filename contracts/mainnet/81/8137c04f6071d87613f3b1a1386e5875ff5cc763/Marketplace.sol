// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
pragma abicoder v2;

import "./ERC721.sol";
import "./IERC2981.sol";
import "./IERC777.sol";
import "./ReentrancyGuard.sol";
import "./IERC777Recipient.sol";
import "./IERC1820Registry.sol";
import "./Initializable.sol";
import "./Strings.sol";
import "./Ownable.sol";

contract Marketplace is ReentrancyGuard, IERC777Recipient, Initializable, Ownable, IERC2981 {
    uint16 public royalty; // royalty percentage expressed in tenthousandths
    address public tokenAddress; // ERC721 NFT contract address
    ERC721 private _tokenContract; // ERC721 NFT token contract instance
    address payable public splitterAddress; //  The royalty splitter contract address

    /*
    The DUST ERC777 contract address
    It is shared state between all marketplace proxies. 
    */
    address public immutable dustContractAddress;

    struct Offer {
        bool isForSale; // flag to check sale status
        address seller;
        uint256 value;
        address sellOnlyTo; // specify to sell only to a specific address
    }

    struct Bid {
        bool hasBid; // flag to check bid status
        address bidder;
        uint256 value;
    }

    // map offers and bids for each token
    mapping(uint256 => Offer) public cardsForSaleInETH; // list of cards of for sale in ETH
    mapping(uint256 => Offer) public cardsForSaleInDust; // list of cards of for sale in DUST
    mapping(uint256 => Bid) public etherBids; // list of ether bids on cards
    mapping(uint256 => Bid) public dustBids; // list of DUST bids on cards

    event OfferForSale(address _from, address _to, uint256 _tokenId, uint256 _value, bool _isDust);
    event OfferExecuted(address _from, address _to, uint256 _tokenId, uint256 _value, bool _isDust);
    event OfferRevoked(address _from, address _to, uint256 _tokenId, uint256 _value, bool _isDust);
    event OfferModified(address _from, uint256 _tokenId, uint256 _value, address _sellOnlyTo, bool _isDust);

    event BidReceived(
        address _from,
        address _to,
        uint256 _tokenId,
        uint256 _newValue,
        uint256 _prevValue,
        bool _isDust
    );
    event BidAccepted(address _from, address _to, uint256 _tokenId, uint256 _value, bool _isDust);
    event BidRevoked(address _from, uint256 _tokenId, uint256 _value, bool _isDust);
    event RoyaltyChanged(address _from, uint16 _royalty);

    modifier onlyCardOwner(uint256 _tokenId) {
        require(_tokenContract.ownerOf(_tokenId) == msg.sender, "Marketplace: Unauthorized");
        _;
    }

    /**
    @param _dustContractAddress address of the IERC777 DUST contrct
    @dev the constructor is called on implementation contract deploy/upgrade, 
    setting the immutable attributes dustContractAddress 
    which will be shared state between all proxies.
     */
    constructor(address _dustContractAddress) {
        dustContractAddress = _dustContractAddress;
    }

    /**
    @param _tokenAddress address of the IERC721 NFT contract
    which is to be traded on this marketplace instance
    @param _owner address of the owner of thei smarketplace instance.
    Ownership will be transferred to this address after the deployment
    succeeds.
    @param _splitterAddress address of royalty splitter
    @dev this function is called when a proxy is deployed and the state
    modified in it is unique to the proxy instance.
     */
    function initialize(
        address _tokenAddress,
        address _splitterAddress,
        address _owner
    ) external initializer {
        require(_tokenAddress != address(0), "Marketplace: Null address not accepted");
        require(_splitterAddress != address(0), "Marketplace: Null address not accepted");
        require(_owner != address(0), "Marketplace: Null address not accepted");

        tokenAddress = _tokenAddress;
        _tokenContract = ERC721(_tokenAddress);
        splitterAddress = payable(_splitterAddress);
        royalty = 500; // 5%

        _transferOwnership(_owner);
    }

    /**
    @inheritdoc IERC777Recipient
     */
    function tokensReceived(
        address,
        address,
        address,
        uint256,
        bytes calldata,
        bytes calldata
    ) external view override {
        // handle incoming DUST when bids are made
        require(msg.sender == dustContractAddress, "Marketplace: Invalid token type");
    }

    //________________________________Offers______________________________

    function _offerCardForSale(
        uint256 _tokenId,
        uint256 _minPrice,
        address _sellOnlyTo,
        bool _isDustOffer
    ) private onlyCardOwner(_tokenId) {
        // check if the contract is approved by token owner
        require(_tokenContract.isApprovedForAll(msg.sender, address(this)), "Marketplace: Contract not authorized");

        // check if price is set to higher than 0
        require(_minPrice > 0, "Marketplace: Offer price must be > 0");

        require(_sellOnlyTo != msg.sender, "Marketplace: Sell only to address cannot be seller's address");

        // initialize offer
        if (_isDustOffer) {
            cardsForSaleInDust[_tokenId] = Offer(true, msg.sender, _minPrice, _sellOnlyTo);
        } else {
            cardsForSaleInETH[_tokenId] = Offer(true, msg.sender, _minPrice, _sellOnlyTo);
        }

        // emit sale event
        emit OfferForSale(msg.sender, address(0), _tokenId, _minPrice, _isDustOffer);
    }

    function offerCardForSaleInETH(
        uint256 _tokenId,
        uint256 _minPrice,
        address _sellOnlyTo
    ) external {
        _offerCardForSale(_tokenId, _minPrice, _sellOnlyTo, false);
    }

    function offerCardForSaleInDust(
        uint256 _tokenId,
        uint256 _minPrice,
        address _sellOnlyTo
    ) external {
        _offerCardForSale(_tokenId, _minPrice, _sellOnlyTo, true);
    }

    function _modifyOffer(
        uint256 _tokenId,
        uint256 _value,
        address _sellOnlyTo,
        bool _isDustOffer
    ) private onlyCardOwner(_tokenId) {
        Offer memory offer = _isDustOffer ? cardsForSaleInDust[_tokenId] : cardsForSaleInETH[_tokenId];

        require(offer.isForSale, "Marketplace: This token is not for sale");
        require(_value > 0, "Marketplace: Offer price must be > 0");
        require(_sellOnlyTo != msg.sender, "Marketplace: Sell only to address cannot be seller's address");

        Offer memory newOffer = Offer(offer.isForSale, offer.seller, _value, _sellOnlyTo);
        // modify offer
        if (_isDustOffer) {
            cardsForSaleInDust[_tokenId] = newOffer;
        } else {
            cardsForSaleInETH[_tokenId] = newOffer;
        }
        emit OfferModified(msg.sender, _tokenId, _value, _sellOnlyTo, _isDustOffer);
    }

    function modifyEtherOffer(
        uint256 _tokenId,
        uint256 _value,
        address _sellOnlyTo
    ) external {
        _modifyOffer(_tokenId, _value, _sellOnlyTo, false);
    }

    function modifyDustOffer(
        uint256 _tokenId,
        uint256 _value,
        address _sellOnlyTo
    ) external {
        _modifyOffer(_tokenId, _value, _sellOnlyTo, true);
    }

    function _revokeOffer(uint256 _tokenId, bool _isDustOffer) private onlyCardOwner(_tokenId) {
        Offer memory offer = _isDustOffer ? cardsForSaleInDust[_tokenId] : cardsForSaleInETH[_tokenId];
        require(offer.isForSale, "Marketplace: This token is not for sale");

        Offer memory newOffer = Offer(false, address(0), 0, address(0));
        if (_isDustOffer) {
            cardsForSaleInDust[_tokenId] = newOffer;
        } else {
            cardsForSaleInETH[_tokenId] = newOffer;
        }
        emit OfferRevoked(offer.seller, offer.sellOnlyTo, _tokenId, offer.value, _isDustOffer);
    }

    function revokeEtherOffer(uint256 _tokenId) external {
        _revokeOffer(_tokenId, false);
    }

    function revokeDustOffer(uint256 _tokenId) external {
        _revokeOffer(_tokenId, true);
    }

    function _buyItNow(uint256 _tokenId, bool _isDustOffer) private nonReentrant {
        Offer memory offer = _isDustOffer ? cardsForSaleInDust[_tokenId] : cardsForSaleInETH[_tokenId];
        // check if the offer is valid
        require(offer.isForSale, "Marketplace: This token is not for sale");
        require(offer.seller != address(0), "Marketplace: This token is not for sale");
        require(offer.value > 0, "Marketplace: This token is not for sale");

        // check if it is for sale for someone specific
        if (offer.sellOnlyTo != address(0)) {
            // only sell to someone specific
            require(offer.sellOnlyTo == msg.sender, "Marketplace: This token is not for sale for buyer");
        }

        // make sure buyer is not the owner
        require(msg.sender != _tokenContract.ownerOf(_tokenId), "Marketplace: Token already owned");

        // check approval status, user may have modified transfer approval
        require(_tokenContract.isApprovedForAll(offer.seller, address(this)), "Marketplace: Contract not authorized");

        if (_isDustOffer) {
            // check if buyer has enough Dust to purchase
            require(_getDustContract().balanceOf(msg.sender) >= offer.value, "Marketplace: Not enough DUST");
        } else {
            // check if offer value and sent values match
            require(offer.value == msg.value, "Marketplace: Not enough ETH sent");
        }

        // make sure the seller is the owner
        require(offer.seller == _tokenContract.ownerOf(_tokenId), "Marketplace: Unauthorized");

        // save the seller variable
        address seller = offer.seller;

        // reset offers for this card
        cardsForSaleInETH[_tokenId] = Offer(false, address(0), 0, address(0));
        cardsForSaleInDust[_tokenId] = Offer(false, address(0), 0, address(0));

        // check if there were any ether bids on this card
        Bid memory bid = etherBids[_tokenId];
        if (bid.hasBid) {
            // save bid values and bidder variables
            address bidder = bid.bidder;
            uint256 amount = bid.value;
            // reset bid
            etherBids[_tokenId] = Bid(false, address(0), 0);
            // send back bid value to bidder
            bool sent;
            (sent, ) = bidder.call{value: amount}("");
            require(sent, "Marketplace: Failed to send back ETH");
        }

        // check if there were any DUST bids on this card
        Bid memory dustBid = dustBids[_tokenId];
        if (dustBid.hasBid) {
            // save bid values and bidder variables
            address bidder = dustBid.bidder;
            uint256 amount = dustBid.value;
            // reset bid
            dustBids[_tokenId] = Bid(false, address(0), 0);
            // send back bid value to bidder
            _getDustContract().operatorSend(address(this), bidder, amount, "", "");
        }

        // first send the token to the buyer
        _tokenContract.safeTransferFrom(seller, msg.sender, _tokenId);

        // transfer ether to acceptor and pay royalty to the community owner
        if (_isDustOffer) {
            _splitDust(msg.sender, seller, offer.value);
        } else {
            _split(seller, offer.value);
        }

        // check if the user recieved the item
        require(_tokenContract.ownerOf(_tokenId) == msg.sender);

        // emit event
        emit OfferExecuted(offer.seller, msg.sender, _tokenId, offer.value, _isDustOffer);
    }

    function buyItNowForEther(uint256 _tokenId) external payable {
        _buyItNow(_tokenId, false);
    }

    function buyItNowForDust(uint256 _tokenId) external {
        _buyItNow(_tokenId, true);
    }

    //_______________________Bids_________________________________

    function _bidOnCard(
        uint256 _tokenId,
        uint256 _bidValue,
        address _bidder,
        bool _isDustBid
    ) private nonReentrant {
        // check if bid value is valid
        require(_bidValue > 0, "Marketplace: Bid value must be > 0");

        // check that not bidding on owned card
        require(_bidder != _tokenContract.ownerOf(_tokenId), "Marketplace: Token already owned");

        Bid memory lastBid = _isDustBid ? dustBids[_tokenId] : etherBids[_tokenId];

        require(lastBid.value < _bidValue, "Marketplace: Bid must exceed current bid");

        // initialize the bid with the new values
        Bid memory newBid = Bid(true, msg.sender, _bidValue);

        if (_isDustBid) {
            dustBids[_tokenId] = newBid;
            require(_getDustContract().balanceOf(_bidder) >= _bidValue, "Marketplace: Not enough DUST");
            // move DUST into marketplace contract
            _getDustContract().operatorSend(_bidder, address(this), _bidValue, "", "");
        } else {
            etherBids[_tokenId] = newBid;
        }

        // emit event
        emit BidReceived(
            msg.sender,
            _tokenContract.ownerOf(_tokenId),
            _tokenId,
            newBid.value,
            lastBid.value,
            _isDustBid
        );

        // refund previous bidder if exists
        if (lastBid.hasBid) {
            if (_isDustBid) {
                _getDustContract().operatorSend(address(this), lastBid.bidder, lastBid.value, "", "");
            } else {
                bool sent;
                (sent, ) = lastBid.bidder.call{value: lastBid.value}("");
                require(sent, "Marketplace: Failed to send back ETH");
            }
        }
    }

    function bidOnCardWithEther(uint256 _tokenId) external payable {
        _bidOnCard(_tokenId, msg.value, msg.sender, false);
    }

    function bidOnCardWithDust(uint256 _tokenId, uint256 _bidValue) external {
        _bidOnCard(_tokenId, _bidValue, msg.sender, true);
    }

    function _acceptBid(uint256 _tokenId, bool _isDustBid) private nonReentrant {
        Bid memory bid = _isDustBid ? dustBids[_tokenId] : etherBids[_tokenId];

        // make sure there is a valid bid on the card
        require(bid.hasBid, "Marketplace: No bid found for token");
        // check if the contract is still approved for transfer
        require(_tokenContract.isApprovedForAll(msg.sender, address(this)), "Marketplace: Contract not authorized");

        // reset offers for this token
        cardsForSaleInETH[_tokenId] = Offer(false, address(0), 0, address(0));
        cardsForSaleInDust[_tokenId] = Offer(false, address(0), 0, address(0));

        address buyer = bid.bidder;
        uint256 amount = bid.value;

        Bid memory otherBid = _isDustBid ? etherBids[_tokenId] : dustBids[_tokenId];

        // reset bids
        etherBids[_tokenId] = Bid(false, address(0), 0);
        dustBids[_tokenId] = Bid(false, address(0), 0);

        if (_isDustBid) {
            if (otherBid.hasBid) {
                // Refund existing ETH bid
                (bool success, ) = otherBid.bidder.call{value: otherBid.value}("");
                require(success, "Marketplace: Transfer failed");
            }
            // send DUST
            _splitDust(address(this), msg.sender, amount);
        } else {
            if (otherBid.hasBid) {
                // Refund  existing DUST bid
                _getDustContract().send(otherBid.bidder, otherBid.value, "");
            }
            // send ETH
            _split(msg.sender, amount);
        }

        // send token from acceptor to the bidder
        _tokenContract.safeTransferFrom(msg.sender, buyer, _tokenId);

        // check if the user received the token
        require(_tokenContract.ownerOf(_tokenId) == buyer);

        // emit event
        emit BidAccepted(msg.sender, bid.bidder, _tokenId, amount, _isDustBid);
    }

    function acceptEtherBid(uint256 _tokenId) external onlyCardOwner(_tokenId) {
        _acceptBid(_tokenId, false);
    }

    function acceptDustBid(uint256 _tokenId) external onlyCardOwner(_tokenId) {
        _acceptBid(_tokenId, true);
    }

    function _revokeBid(uint256 _tokenId, bool _isDustBid) private nonReentrant {
        Bid memory bid = _isDustBid ? dustBids[_tokenId] : etherBids[_tokenId];
        // check if the bid exists
        require(bid.hasBid, "Marketplace: No bid found for token");
        // check if the bidder is the sender of the message
        require(bid.bidder == msg.sender, "Marketplace: Unauthorized");
        // save bid value into a variable
        uint256 amount = bid.value;

        // reset bid
        if (_isDustBid) {
            dustBids[_tokenId] = Bid(false, address(0), 0);

            // refund DUST
            _getDustContract().send(msg.sender, amount, "");
        } else {
            etherBids[_tokenId] = Bid(false, address(0), 0);
            // transfer back their ether
            (bool sent, ) = msg.sender.call{value: amount}("");
            require(sent, "Marketplace: Failed to send back ETH");
        }

        // emit event
        emit BidRevoked(msg.sender, _tokenId, amount, _isDustBid);
    }

    function revokeEtherBid(uint256 _tokenId) external {
        _revokeBid(_tokenId, false);
    }

    function revokeDustBid(uint256 _tokenId) external {
        _revokeBid(_tokenId, true);
    }

    function setRoyalty(uint16 _royalty) public onlyOwner {
        require(royalty <= 10000, "Marketplace: Royalty too high");
        royalty = _royalty;
        emit RoyaltyChanged(msg.sender, _royalty);
    }

    function _split(address _seller, uint256 _amount) private {
        uint256 royaltyAmount = (_amount * royalty) / 10000;

        bool success = false;

        //send to splitter
        (bool _success, bytes memory returndata) = splitterAddress.call{value: royaltyAmount}("");
        require(_success, string(returndata));

        // transfer rest to the seller
        (success, ) = _seller.call{value: _amount - royaltyAmount}("");
        require(success, "Marketplace: Transfer failed");
    }

    function _splitDust(
        address _buyer,
        address _seller,
        uint256 _amount
    ) private {
        uint256 royaltyAmount = (_amount * royalty) / 10000;

        // send royalty to splitter
        _getDustContract().operatorSend(_buyer, splitterAddress, royaltyAmount, "", "");

        // send rest to seller
        _getDustContract().operatorSend(_buyer, _seller, _amount - royaltyAmount, "", "");
    }

    function _getDustContract() private view returns (IERC777) {
        return IERC777(dustContractAddress);
    }

    /**
    @inheritdoc IERC2981
     */
    function royaltyInfo(uint256, uint256 salePrice)
        external
        view
        override(IERC2981)
        returns (address receiver, uint256 royaltyAmount)
    {
        return (splitterAddress, (salePrice * royalty) / 10000);
    }

    /**
    @inheritdoc IERC165
     */
    function supportsInterface(bytes4 interfaceId) external pure override(IERC165) returns (bool) {
        return interfaceId == type(IERC2981).interfaceId || interfaceId == type(IERC777Recipient).interfaceId;
    }
}

