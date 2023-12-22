// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/* Interfaces */
import "./IRoyaltyRegistry.sol";
import "./ICancellationRegistry.sol";

/* Libraries */
import "./Ownable.sol";
import "./ERC721_IERC721.sol";
import "./ERC1155_IERC1155.sol";
import "./ERC165Checker.sol";
import "./ECDSA.sol";
import "./Address.sol";
import "./Pausable.sol";
import "./ReentrancyGuard.sol";

contract ExchangeV5 is Ownable, Pausable, ReentrancyGuard {
    // ERC-165 identifiers
    bytes4 INTERFACE_ID_ERC721 = 0x80ac58cd;
    bytes4 INTERFACE_ID_ERC1155 = 0xd9b67a26;

    bytes32 constant EIP712_DOMAIN_TYPE_HASH = keccak256("EIP712Domain(string name,string version)");
    bytes32 constant DOMAIN_SEPARATOR = keccak256(
        abi.encode(
            EIP712_DOMAIN_TYPE_HASH,
            keccak256(bytes("Quixotic")),
            keccak256(bytes("5"))
        )
    );

    address payable _makerWallet;
    uint256 _makerFeePerMille = 25;
    uint256 _maxRoyaltyPerMille = 150;

    IRoyaltyRegistry royaltyRegistry;
    ICancellationRegistry cancellationRegistry;

    event SellOrderFilled(
        address indexed seller,
        address payable buyer,
        address indexed contractAddress,
        uint256 indexed tokenId,
        uint256 price
    );

    struct SellOrder {
        address payable seller; // Seller of the NFT
        address contractAddress; // Contract address of NFT
        uint256 tokenId; // Token id of NFT to sell
        uint256 startTime; // Start time in unix timestamp
        uint256 expiration; // Expiration in unix timestamp
        uint256 price; // Price in wei
        uint256 quantity; // Number of tokens to transfer; should be 1 for ERC721
        uint256 createdAtBlockNumber; // Block number that this order was created at
        address paymentERC20; // Should be address(0). Kept for backwards compatibility.
    }

    /********************
     * Public Functions *
     ********************/

    /*
    * @dev External trade function. This accepts the details of the sell order and signed sell
    * order (the signature) as a meta-transaction.
    *
    * Emits a {SellOrderFilled} event via `_fillSellOrder`.
    */
    function fillSellOrder(
        address payable seller,
        address contractAddress,
        uint256 tokenId,
        uint256 startTime,
        uint256 expiration,
        uint256 price,
        uint256 quantity,
        uint256 createdAtBlockNumber,
        address paymentERC20,
        bytes memory signature,
        address payable buyer
    ) external payable whenNotPaused nonReentrant {
        require(paymentERC20 == address(0), "ERC20 payments are disabled.");
        require(msg.value >= price, "Transaction doesn't have the required ETH amount.");

        SellOrder memory sellOrder = SellOrder(
            seller,
            contractAddress,
            tokenId,
            startTime,
            expiration,
            price,
            quantity,
            createdAtBlockNumber,
            paymentERC20
        );

        // Make sure the order is not cancelled
        require(
            cancellationRegistry.getSellOrderCancellationBlockNumber(seller, contractAddress, tokenId) < createdAtBlockNumber,
            "This order has been cancelled."
        );

        // Check signature
        require(_validateSellerSignature(sellOrder, signature), "Signature is not valid for SellOrder.");

        // Check has started
        require((block.timestamp > startTime), "SellOrder start time is in the future.");

        // Check not expired
        require((block.timestamp < expiration), "This sell order has expired.");

        _fillSellOrder(sellOrder, buyer);
    }

    /*
    * @dev Sets the royalty as an int out of 1000 that the creator should receive and the address to pay.
    */
    function setRoyalty(address contractAddress, address payable _payoutAddress, uint256 _payoutPerMille) external {
        require(_payoutPerMille <= _maxRoyaltyPerMille, "Royalty must be between 0 and 15%");
        require(
            ERC165Checker.supportsInterface(contractAddress, INTERFACE_ID_ERC721) ||
            ERC165Checker.supportsInterface(contractAddress, INTERFACE_ID_ERC1155),
            "Is not ERC721 or ERC1155"
        );

        Ownable ownableNFTContract = Ownable(contractAddress);
        require(_msgSender() == ownableNFTContract.owner());

        royaltyRegistry.setRoyalty(contractAddress, _payoutAddress, _payoutPerMille);
    }

    /*
    * @dev Implements one-order-cancels-the-other (OCO) for a token
    */
    function cancelPreviousSellOrders(
        address addr,
        address tokenAddr,
        uint256 tokenId
    ) external {
        require((addr == _msgSender() || owner() == _msgSender()), "Caller must be Exchange Owner or Order Signer");
        cancellationRegistry.cancelPreviousSellOrders(addr, tokenAddr, tokenId);
    }

    function calculateCurrentPrice(uint256 startTime, uint256 endTime, uint256 startPrice, uint256 endPrice) public view returns (uint256) {
        uint256 auctionDuration = (endTime - startTime);
        uint256 timeRemaining = (endTime - block.timestamp);

        uint256 perMilleRemaining = (1000000000000000 / auctionDuration) / (1000000000000 / timeRemaining);

        uint256 variableAmount = startPrice - endPrice;
        uint256 variableAmountRemaining = (perMilleRemaining * variableAmount) / 1000;
        return endPrice + variableAmountRemaining;
    }

    /*
    * @dev Gets the royalty payout address.
    */
    function getRoyaltyPayoutAddress(address contractAddress) external view returns (address) {
        return royaltyRegistry.getRoyaltyPayoutAddress(contractAddress);
    }

    /*
    * @dev Gets the royalty as a int out of 1000 that the creator should receive.
    */
    function getRoyaltyPayoutRate(address contractAddress) external view returns (uint256) {
        return royaltyRegistry.getRoyaltyPayoutRate(contractAddress);
    }
    
    /*******************
     * Admin Functions *
     *******************/

    /*
    * @dev Sets the wallet for the exchange.
    */
    function setMakerWallet(address payable _newMakerWallet) external onlyOwner {
        _makerWallet = _newMakerWallet;
    }

    /*
    * @dev Sets the registry contracts for the exchange.
    */
    function setRegistryContracts(
        address _royaltyRegistry,
        address _cancellationRegistry
    ) external onlyOwner {
        royaltyRegistry = IRoyaltyRegistry(_royaltyRegistry);
        cancellationRegistry = ICancellationRegistry(_cancellationRegistry);
    }

    /*
    * @dev Pauses trading on the exchange. To be used for emergencies.
    */
    function pause() external onlyOwner {
        _pause();
    }

    /*
    * @dev Resumes trading on the exchange. To be used for emergencies.
    */
    function unpause() external onlyOwner {
        _unpause();
    }

    /*
    * Withdraw just in case Ether is accidentally sent to this contract.
    */
    function withdraw() external onlyOwner {
        uint balance = address(this).balance;
        payable(msg.sender).transfer(balance);
    }

    /**********************
     * Internal Functions *
     **********************/

    /*
    * @dev Executes a trade given a sell order.
    *
    * Emits a {SellOrderFilled} event.
    */
    function _fillSellOrder(SellOrder memory sellOrder, address payable buyer) internal {
        // Cancels the order so that future attempts to purchase the NFT fail
        cancellationRegistry.cancelPreviousSellOrders(sellOrder.seller, sellOrder.contractAddress, sellOrder.tokenId);

        emit SellOrderFilled(sellOrder.seller, buyer, sellOrder.contractAddress, sellOrder.tokenId, sellOrder.price);

        // Transfer NFT to buyer
        _transferNFT(sellOrder.contractAddress, sellOrder.tokenId, sellOrder.seller, buyer, sellOrder.quantity);

        // Sends payments to seller, royalty receiver, and marketplace
        _sendETHPaymentsWithRoyalties(sellOrder.contractAddress, sellOrder.seller);
    }

    /*
    * @dev Sends out ETH payments to marketplace, royalty, and the final recipients
    */
    function _sendETHPaymentsWithRoyalties(address contractAddress, address payable finalRecipient) internal {
        uint256 royaltyPayout = (royaltyRegistry.getRoyaltyPayoutRate(contractAddress) * msg.value) / 1000;
        uint256 makerPayout = (_makerFeePerMille * msg.value) / 1000;
        uint256 remainingPayout = msg.value - royaltyPayout - makerPayout;

        if (royaltyPayout > 0) {
            Address.sendValue(royaltyRegistry.getRoyaltyPayoutAddress(contractAddress), royaltyPayout);
        }

        Address.sendValue(_makerWallet, makerPayout);
        Address.sendValue(finalRecipient, remainingPayout);
    }

    /*
    * @dev Validate the sell order against the signature of the meta-transaction.
    */
    function _validateSellerSignature(SellOrder memory sellOrder, bytes memory signature) internal pure returns (bool) {

        bytes32 SELLORDER_TYPEHASH = keccak256(
            "SellOrder(address seller,address contractAddress,uint256 tokenId,uint256 startTime,uint256 expiration,uint256 price,uint256 quantity,uint256 createdAtBlockNumber,address paymentERC20)"
        );

        bytes32 structHash = keccak256(abi.encode(
                SELLORDER_TYPEHASH,
                sellOrder.seller,
                sellOrder.contractAddress,
                sellOrder.tokenId,
                sellOrder.startTime,
                sellOrder.expiration,
                sellOrder.price,
                sellOrder.quantity,
                sellOrder.createdAtBlockNumber,
                sellOrder.paymentERC20
            ));

        bytes32 digest = ECDSA.toTypedDataHash(DOMAIN_SEPARATOR, structHash);

        address recoveredAddress = ECDSA.recover(digest, signature);
        return recoveredAddress == sellOrder.seller;
    }

    function _transferNFT(address contractAddress, uint256 tokenId, address seller, address buyer, uint256 quantity) internal {
        if (ERC165Checker.supportsInterface(contractAddress, INTERFACE_ID_ERC721)) {
            IERC721 erc721 = IERC721(contractAddress);

            // require is approved for all */
            require(erc721.isApprovedForAll(seller, address(this)), "The Exchange is not approved to operate this NFT");

            /////////////////
            ///  Transfer ///
            /////////////////
            erc721.transferFrom(seller, buyer, tokenId);

        } else if (ERC165Checker.supportsInterface(contractAddress, INTERFACE_ID_ERC1155)) {
            IERC1155 erc1155 = IERC1155(contractAddress);

            /////////////////
            ///  Transfer ///
            /////////////////
            erc1155.safeTransferFrom(seller, buyer, tokenId, quantity, "");

        } else {
            revert("We don't recognize the NFT as either an ERC721 or ERC1155.");
        }
    }
}
