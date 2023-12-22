// SPDX-License-Identifier: UNLICENSED
/*
* This code must not be forked, replicated, modified or used by any other entity or person without explicit approval of Wavect GmbH.
* Website: https://wavect.io
* E-Mail: office@wavect.io
*/
pragma solidity ^0.8.16;

import "./ERC721.sol";
import "./Strings.sol";
import "./Pausable.sol";
import "./SignatureChecker.sol";
import "./ReentrancyGuard.sol";
import "./Multicall.sol";
import "./Ownable.sol";
import "./LayerZero.sol";
import "./LinearlyAssigned.sol";

contract Wavect is ERC721, Ownable, LinearlyAssigned, Pausable, Multicall, ReentrancyGuard {

    bool public publicSaleEnabled;
    /// @dev If true then there is no way to change the license on-chain. This is more or less a security parameter in case of errors.
    bool public licenseFrozen;
    bool public metadataFrozen;

    uint128 public maxWallet;
    uint128 public maxTier;

    uint256 public mintPrice;

    string public licenseURI;
    string public contractURI;
    string public baseURI;

    /// @dev (tokenId=>tier): Used to have yearly paid memberships for specific benefits, ..
    mapping(uint256 => Subscription) public subscriptionTier;
    /// @dev (tier=>price): Used to have yearly paid memberships for specific benefits, ..
    mapping(uint128 => uint256) public subscriptionPrice;
    mapping(address => uint256) public minted;

    event ChangedSubscription(uint256 indexed tokenId, uint128 newTier);
    event BaseURIChanged(string baseUri);
    event MaxTierChanged(uint128 maxTier);
    event MaxWalletChanged(uint128 maxWallet);

    error Frozen();
    error InvalidTier();

    LayerZero public immutable layerZero;

    struct Subscription {
        uint128 tier;
        uint256 timePaidUntil;
    }

    constructor(
        string memory baseURI_,
        string memory licenseURI_,
        string memory name_,
        string memory ticker_,
        uint256 totalSupply_,
        address owner_,
        address layerZero_)
    ERC721(name_, ticker_)
    LinearlyAssigned(totalSupply_, 1)
    {
        maxWallet = 3;
        maxTier = 3;
        baseURI = baseURI_;
        licenseURI = licenseURI_;
        layerZero = LayerZero(layerZero_);

        /* Important to ensure that NFT only exists on one chain (for regular NFTs)
        * and for the reward nfts to ensure that nonces/signatures cannot be reused. */
        _pause();
        // NOTE: Enable mint & changeSubscription on main chain

        super.transferOwnership(owner_);
        // using create2
    }

    function isBelowMaxWallet(address wallet_, uint256 amount_) public view returns (bool) {
        return (minted[wallet_] + amount_) <= maxWallet;
    }

    // no nonce, since usable infinitely, but maxwallet restriction + bound to wallet
    function isWhitelisted(address sender_, bytes memory sig_) public view returns (bool) {
        bytes32 hash = ECDSA.toEthSignedMessageHash(keccak256(abi.encodePacked(sender_)));
        return sender_ == owner() || SignatureChecker.isValidSignatureNow(owner(), hash, sig_);
    }

    function mint(address recipient_, bytes memory sig_, uint256 amount_) payable public whenNotPaused nonReentrant {
        require(isBelowMaxWallet(recipient_, amount_), "Max wallet");
        // no nonce needed reuse sig until maxWallet reached
        uint256 sumMintPrice = mintPrice * amount_;
        require(msg.value >= sumMintPrice, "Payment too low");

        if (!publicSaleEnabled) {
            require(isWhitelisted(recipient_, sig_), "Invalid sig");
        }
        for (uint256 i = 0; i < amount_; i++) {
            _safeMint(recipient_, nextToken());
        }
        minted[recipient_] += amount_;

        if (msg.value > sumMintPrice) {
            // if paid too much, send remaining funds back, using ReentrancyGuard
            (bool success, ) = payable(recipient_).call{value: msg.value - sumMintPrice}("");
            require(success, "Failed to send ether");
        }
    }

    function withdrawRevenue() external onlyOwner {
        (bool success, ) = payable(owner()).call{value: address(this).balance}("");
        require(success, "Failed to withdraw");
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireMinted(tokenId);
        return string(abi.encodePacked(baseURI, Strings.toString(tokenId), ".json"));
    }

    /// @dev Can only be called when subscriptionTiers have been configured
    function changeSubscription(uint256 tokenID_, uint128 desiredTier_) payable external nonReentrant {
        if (desiredTier_ >= maxTier) revert InvalidTier();
        if (desiredTier_ != 0) {
            require(subscriptionPrice[desiredTier_] > 0, "Tiers not set"); // maxTier >= 2 (0 can be 0 as free, 1 is the first paid tier)
        }
        _requireMinted(tokenID_);
        require(_msgSender() == ownerOf(tokenID_) || _msgSender() == owner(), "Not holder");
        require(subscriptionPrice[desiredTier_] == msg.value, "Invalid payment");

        subscriptionTier[tokenID_] = Subscription(desiredTier_, block.timestamp + 365 days);
        emit ChangedSubscription(tokenID_, desiredTier_);
    }

    function isSubscriptionValid(uint256 tokenID_) public view returns (bool) {
        _requireMinted(tokenID_);
        if (subscriptionTier[tokenID_].tier == 0) return true;
        return subscriptionTier[tokenID_].timePaidUntil > block.timestamp;
    }

    function setContractURI(string calldata contractURI_) external onlyOwner() {
        if (metadataFrozen) revert Frozen();
        contractURI = contractURI_;
    }

    /// @dev Separate option to freeze this to avoid renouncing ownership too early or when not desired
    function setLicenseURI(string calldata licenseURI_, bool freeze_) external onlyOwner() {
        if (licenseFrozen) revert Frozen();
        licenseURI = licenseURI_;
        if (freeze_) {
            licenseFrozen = true;
        }
    }

    function setBaseURI(string calldata baseURI_) external onlyOwner() {
        if (metadataFrozen) revert Frozen();
        baseURI = baseURI_;
        emit BaseURIChanged(baseURI);
    }

    function freezeMetadata() external onlyOwner() {
        if (metadataFrozen) revert Frozen();
        metadataFrozen = true;
    }

    function setSubscriptionPrice(uint128 tier_, uint256 price_) external onlyOwner() {
        if (tier_ >= maxTier) revert InvalidTier();
        subscriptionPrice[tier_] = price_;
    }

    function setMaxTier(uint128 maxTier_) external onlyOwner {
        if (maxTier_ < 2) revert InvalidTier();
        // to ensure prices are set crosschain
        maxTier = maxTier_;
        emit MaxTierChanged(maxTier_);
    }

    function setMintPrice(uint256 mintPrice_) external onlyOwner {
        mintPrice = mintPrice_;
    }

    function setPublicSale(bool publicSale_) external onlyOwner {
        publicSaleEnabled = publicSale_;
    }

    /* @dev Important to ensure that NFT only exists on one chain (for regular NFTs)
        * and for the reward nfts to ensure that nonces/signatures cannot be reused. */
    function setEnableMint(bool enable_) external onlyOwner {
        require(bytes(contractURI).length != 0, "CUri null");
        require(address(layerZero.lzEndpoint()) != address(0), "L0 not set");

        if (enable_) {
            _unpause();
        } else {
            _pause();
        }
    }

    function setMaxWallet(uint128 maxWallet_) external onlyOwner {
        maxWallet = maxWallet_;
        emit MaxWalletChanged(maxWallet_);
    }

    function debitFrom(address _sender, address _from, uint256 _tokenId) external returns (Subscription memory) {
        require(_msgSender() == address(layerZero), "Caller not layer0");
        require(_isApprovedOrOwner(_sender, _tokenId), "Caller not owner or approved");
        require(ERC721.ownerOf(_tokenId) == _from, "Incorrect owner");
        _burn(_tokenId);
        Subscription memory tier = subscriptionTier[_tokenId];
        subscriptionTier[_tokenId] = Subscription(0, 0);
        return tier;
    }

    function creditTo(address toAddress_, uint256 tokenId_, bytes memory tier_) external {
        require(_msgSender() == address(layerZero), "Caller not layer0");
        _safeMint(toAddress_, tokenId_);
        subscriptionTier[tokenId_] = abi.decode(tier_, (Subscription));
    }
}

