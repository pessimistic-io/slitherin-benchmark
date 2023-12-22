// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.11;

import "./SimpleFactory.sol";
import "./BoringBatchable.sol";
import "./VibeERC20.sol";
import "./VibeERC721.sol";
import "./VibeERC1155.sol";
import "./RoyaltyReceiver.sol";
import "./NFTMintSale.sol";
import "./NFTMintSaleMultiple.sol";
import "./NFTMintSaleWhitelisting.sol";
import "./NFTMintSaleWhitelistingMultiple.sol";
import "./NativeTokenHelper.sol";

contract VibeFactory is BoringBatchable {
    address public immutable vibeERC20Impl;
    address public immutable vibeERC721Impl;
    address public immutable vibeERC1155Impl;
    address public immutable royaltyReceiverImpl;
    address public immutable nftMintSale;
    address public immutable nftMintSaleMultiple;
    address public immutable nftMintSaleWhitelisting;
    address public immutable nftMintSaleWhitelistingMultiple;
    address public immutable claimantDropImpl;
    address public immutable claimantDropLimitedImpl;
    address public immutable vibeWhitelistSaleImpl;
    SimpleFactory public immutable factory;
    IERC20 public immutable WETH;
    NativeTokenHelper public immutable TOKEN_HELPER;

    struct TierInfo {
        uint128 price;
        uint32 beginId;
        uint32 endId;
        uint32 currentId;
    }

    struct RoyaltyInformation {
        address royaltyReceiver_;
        uint16 royaltyRate_;
        uint16 derivativeRoyaltyRate;
        bool isDerivativeAllowed;
    }

    event ERC20Created(address indexed sender, address indexed proxy, bytes data);
    event ERC721Created(address indexed sender, address indexed proxy, bytes data);
    event ERC1155Created(address indexed sender, address indexed proxy, bytes data);
    event LogRoyaltyReceiver(address indexed sender, address indexed proxy, bytes data);
    event LogNFTMintSale(address indexed sender, address indexed proxy, bytes data);
    event LogNFTMintSaleMultiple(address indexed sender, address indexed proxy, bytes data);
    event ClaimantDropCreated(address indexed sender, address indexed proxy, bytes data);
    event ClaimantDropLimitedCreated(
        address indexed sender,
        address indexed proxy,
        bytes data
    );
    event VibeWhitelistSaleCreated(
        address indexed sender,
        address indexed proxy,
        bytes data
    );

    struct TokenHelperStructs {
        SimpleFactory _simpleFactory;
        NativeTokenHelper tokenHelper;
    }

    /**
     * @notice constructor
     * @param _vibeERC20Impl implementation address of VibeERC20 contract
     * @param _vibeERC721Impl implementation address of VibeERC721 contract
     * @param _vibeERC1155Impl implementation address of VibeERC1155 contract
     * @param _royaltyReceiverImpl implementation address of royalty receiver contract
     * @param _NFTMintSale implementation address of nft mint sale contract
     * @param _NFTMintSaleMultiple implementation address of nft mint sale multiple contract
     * @param _claimantDropImpl implementation address of claimantDrop contract
     * @param _claimantDropLimitedImpl implementation address of claimantDrop contract
     * @param _vibeWhitelistSaleImpl implementation address of VibeWhitelistSale contract
     * @param tokenHelperStruct struct of simple factory, token helper and weth address
     */
    constructor(
        address _vibeERC20Impl,
        address _vibeERC721Impl,
        address _vibeERC1155Impl,
        address _royaltyReceiverImpl,
        address _NFTMintSale,
        address _NFTMintSaleMultiple,
        address _nftMintSaleWhitelisting,
        address _nftMintSaleWhitelistingMultiple,
        address _claimantDropImpl,
        address _claimantDropLimitedImpl,
        address _vibeWhitelistSaleImpl,
        TokenHelperStructs memory tokenHelperStruct
    ) {
        vibeERC20Impl = _vibeERC20Impl;
        vibeERC721Impl = _vibeERC721Impl;
        vibeERC1155Impl = _vibeERC1155Impl;
        royaltyReceiverImpl = _royaltyReceiverImpl;
        nftMintSale = _NFTMintSale;
        nftMintSaleMultiple = _NFTMintSaleMultiple;
        claimantDropImpl = _claimantDropImpl;
        claimantDropLimitedImpl = _claimantDropLimitedImpl;
        vibeWhitelistSaleImpl = _vibeWhitelistSaleImpl;
        nftMintSaleWhitelisting = _nftMintSaleWhitelisting;
        nftMintSaleWhitelistingMultiple = _nftMintSaleWhitelistingMultiple;
        {
            factory = tokenHelperStruct._simpleFactory;
            TOKEN_HELPER = NativeTokenHelper(tokenHelperStruct.tokenHelper);
            WETH = IERC20(address(TOKEN_HELPER.WETH()));
        }
    }

    function createRoyaltyReceiver(
        uint256[] calldata recipientBPS_,
        address[] calldata recipients_
    ) external {
        bytes memory data = abi.encode(recipientBPS_, recipients_);
        address proxy = factory.deploy(royaltyReceiverImpl, data, false);
        factory.transferOwnership(proxy, msg.sender);
        emit LogRoyaltyReceiver(msg.sender, proxy, data);
    }

    function createNFTMintSale(
        string memory symbol,
        string memory name,
        string memory baseURI,
        address royaltyReceiver_,
        uint16 royaltyRate_,
        uint16 derivativeRoyaltyRate,
        bool isDerivativeAllowed,
        uint64 maxMint_,
        uint32 beginTime_,
        uint32 endTime_,
        uint128 price_,
        IERC20 paymentToken_
    ) external {
        bytes memory data;

        address nft = createERC721(
            name,
            symbol,
            baseURI,
            royaltyReceiver_,
            royaltyRate_,
            derivativeRoyaltyRate,
            isDerivativeAllowed,
            address(0)
        );

        data = abi.encode(
            nft,
            maxMint_,
            beginTime_,
            endTime_,
            price_,
            paymentToken_,
            msg.sender
        );

        address proxy = factory.deploy(nftMintSale, data, false);

        factory.exec(nft, abi.encodeCall(VibeERC721.setMinter, (proxy, true)));
        factory.transferOwnership(nft, msg.sender);

        if (paymentToken_ == WETH) {
            TOKEN_HELPER.approveSale(proxy);
        }

        emit LogNFTMintSale(msg.sender, proxy, data);
    }

    struct Timeframe {
        uint32 beginTime;
        uint32 endTime;
    }

    struct RoyaltyInfo {
        address receiver;
        uint16 rate;
        uint16 derivativeRate;
        bool allowedDerivative;
    }

    function createNFTMintSaleWhitelisting(
        string memory symbol,
        string memory name,
        string memory baseURI,
        RoyaltyInfo memory royalty,
        uint64 maxMint_,
        Timeframe memory timeframe,
        uint128 price_,
        IERC20 paymentToken_,
        bytes32 merkleRoot_,
        string memory ipfsHash_
    ) external {
        bytes memory data;

        address nft = createERC721(
            name,
            symbol,
            baseURI,
            royalty.receiver,
            royalty.rate,
            royalty.derivativeRate,
            royalty.allowedDerivative,
            address(0)
        );

        data = abi.encode(
            nft,
            maxMint_,
            timeframe.beginTime,
            timeframe.endTime,
            price_,
            paymentToken_,
            address(this)
        );

        address proxy = factory.deploy(nftMintSaleWhitelisting, data, false);
        factory.exec(proxy, abi.encodeCall(NFTMintSaleWhitelisting.setMerkleRoot, (merkleRoot_, ipfsHash_)));
        // factory.transferOwnership(proxy, msg.sender);

        factory.exec(nft, abi.encodeCall(VibeERC721.setMinter, (proxy, true)));
        factory.transferOwnership(nft, msg.sender);

        if (paymentToken_ == WETH) {
            TOKEN_HELPER.approveSale(proxy);
        }

        emit LogNFTMintSale(msg.sender, proxy, data);
    }

    function createNFTMintSaleForExisting(
        address nft,
        uint64 maxMint_,
        uint32 beginTime_,
        uint32 endTime_,
        uint128 price_,
        IERC20 paymentToken_
    ) external {
        bytes memory data;

        data = abi.encode(
            nft,
            maxMint_,
            beginTime_,
            endTime_,
            price_,
            paymentToken_,
            msg.sender
        );

        address proxy = factory.deploy(nftMintSale, data, false);

        if (paymentToken_ == WETH) {
            TOKEN_HELPER.approveSale(proxy);
        }

        emit LogNFTMintSale(msg.sender, proxy, data);
    }

    function createNFTMintSaleMultipleWhitelisting (
        bytes32[] memory merkleRoot_,
        string[] memory ipfsHash_,
        string memory symbol,
        string memory name,
        string memory baseURI,
        RoyaltyInfo memory royalty,
        Timeframe memory timeframe,
        IERC20 paymentToken_,
        TierInfo[] memory tiers_
    ) external {
        bytes memory data;

        address nft = createERC721(
            name,
            symbol,
            baseURI,
            royalty.receiver,
            royalty.rate,
            royalty.derivativeRate,
            royalty.allowedDerivative,
            address(0)
        );

        data = abi.encode(
            nft,
            timeframe.beginTime,
            timeframe.endTime,
            tiers_,
            paymentToken_,
            address(this)
        );

        address proxy = factory.deploy(nftMintSaleWhitelistingMultiple, data, false);
        factory.exec(proxy, abi.encodeCall(NFTMintSaleWhitelistingMultiple.setMerkleRoot, (merkleRoot_, ipfsHash_)));
        factory.transferOwnership(proxy, msg.sender);

        factory.exec(nft, abi.encodeCall(VibeERC721.setMinter, (proxy, true)));
        factory.transferOwnership(nft, msg.sender);

        if (paymentToken_ == WETH) {
            TOKEN_HELPER.approveSale(proxy);
        }

        emit LogNFTMintSaleMultiple(msg.sender, proxy, data);
    }

    function createNFTMintSaleMultiple(
        string memory symbol,
        string memory name,
        string memory baseURI,
        address royaltyReceiver_,
        uint16 royaltyRate_,
        uint16 derivativeRoyaltyRate,
        bool isDerivativeAllowed,
        uint32 beginTime_,
        uint32 endTime_,
        TierInfo[] memory tiers_,
        IERC20 paymentToken_
    ) external {
        bytes memory data;

        address nft = createERC721(
            name,
            symbol,
            baseURI,
            royaltyReceiver_,
            royaltyRate_,
            derivativeRoyaltyRate,
            isDerivativeAllowed,
            address(0)
        );

        data = abi.encode(
            nft,
            beginTime_,
            endTime_,
            tiers_,
            paymentToken_,
            msg.sender
        );

        address proxy = factory.deploy(nftMintSaleMultiple, data, false);

        factory.exec(nft, abi.encodeCall(VibeERC721.setMinter, (proxy, true)));
        factory.transferOwnership(nft, msg.sender);

        if (paymentToken_ == WETH) {
            TOKEN_HELPER.approveSale(proxy);
        }

        emit LogNFTMintSaleMultiple(msg.sender, proxy, data);
    }

    function createNFTMintSaleMultipleForExisting(
        address nft,
        uint32 beginTime_,
        uint32 endTime_,
        TierInfo[] memory tiers_,
        IERC20 paymentToken_
    ) external {
        bytes memory data;

        data = abi.encode(
            nft,
            beginTime_,
            endTime_,
            tiers_,
            paymentToken_,
            msg.sender
        );

        address proxy = factory.deploy(nftMintSaleMultiple, data, false);

        if (paymentToken_ == WETH) {
            TOKEN_HELPER.approveSale(proxy);
        }

        emit LogNFTMintSaleMultiple(msg.sender, proxy, data);
    }

    function createClaimantDrop(
        address _claimantNFT,
        string memory name,
        string memory symbol,
        string memory baseURI,
        address royaltyReceiver_,
        uint16 royaltyRate_,
        uint16 derivativeRoyaltyRate,
        bool isDerivativeAllowed
    ) external {
        bytes memory data;

        address nft = createERC721(
            name,
            symbol,
            baseURI,
            royaltyReceiver_,
            royaltyRate_,
            derivativeRoyaltyRate,
            isDerivativeAllowed,
            address(0)
        );

        data = abi.encode(nft, _claimantNFT);

        address proxy = factory.deploy(claimantDropImpl, data, false);

        factory.exec(nft, abi.encodeCall(VibeERC721.setMinter, (proxy, true)));

        emit ClaimantDropCreated(msg.sender, proxy, data);
    }


    function createClaimantDropLimited(
        address _claimantNFT,
        string memory name,
        string memory symbol,
        string memory baseURI,
        uint128 startTime,
        uint128 endTime,
        address royaltyReceiver_,
        uint16 royaltyRate_,
        uint16 derivativeRoyaltyRate,
        bool isDerivativeAllowed
    ) external {
        bytes memory data;

        address nft = createERC721(
            name,
            symbol,
            baseURI,
            royaltyReceiver_,
            royaltyRate_,
            derivativeRoyaltyRate,
            isDerivativeAllowed,
            address(0)
        );

        data = abi.encode(startTime, endTime, nft, _claimantNFT);

        address proxy = factory.deploy(claimantDropLimitedImpl, data, false);

        factory.exec(nft, abi.encodeCall(VibeERC721.setMinter, (proxy, true)));

        emit ClaimantDropLimitedCreated(msg.sender, proxy, data);
    }

    function createVibeWhitelistSale(
        bytes32 _merkleRoot,
        string calldata _ipfsHash,
        string memory name,
        string memory symbol,
        string memory baseURI,
        address royaltyReceiver_,
        uint16 royaltyRate_,
        uint16 derivativeRoyaltyRate,
        bool isDerivativeAllowed
    ) external {
        bytes memory data;

        address nft = createERC721(
            name,
            symbol,
            baseURI,
            royaltyReceiver_,
            royaltyRate_,
            derivativeRoyaltyRate,
            isDerivativeAllowed,
            address(0)
        );

        data = abi.encode(nft, _merkleRoot, _ipfsHash);

        address proxy = factory.deploy(vibeWhitelistSaleImpl, data, false);

        factory.exec(nft, abi.encodeCall(VibeERC721.setMinter, (proxy, true)));

        emit VibeWhitelistSaleCreated(msg.sender, proxy, data);
    }

    function createERC20(string memory name, string memory symbol) public {
        bytes memory data = abi.encode(name, symbol);
        address proxy = factory.deploy(vibeERC20Impl, data, false);
        factory.transferOwnership(proxy, msg.sender);

        emit ERC20Created(msg.sender, proxy, data);
    }

    function createERC721(
        string memory name,
        string memory symbol,
        string memory baseURI,
        address royaltyReceiver_,
        uint16 royaltyRate_,
        uint16 derivativeRoyaltyRate,
        bool isDerivativeAllowed,
        address owner
    ) public returns (address proxy) {
        bytes memory data = abi.encode(name, symbol, baseURI);
        proxy = factory.deploy(vibeERC721Impl, data, false);

        factory.exec(
            proxy,
            abi.encodeCall(
                VibeERC721.setRoyalty,
                (
                    royaltyReceiver_,
                    royaltyRate_,
                    derivativeRoyaltyRate,
                    isDerivativeAllowed
                )
            )
        );

        if (owner != address(0)) {
            factory.transferOwnership(proxy, owner);
        }

        emit ERC721Created(msg.sender, proxy, data);
    }

    function createERC1155(string memory uri) public {
        bytes memory data = abi.encode(uri);
        address proxy = factory.deploy(vibeERC1155Impl, data, false);

        factory.transferOwnership(proxy, msg.sender);

        emit ERC1155Created(msg.sender, proxy, data);
    }
}

