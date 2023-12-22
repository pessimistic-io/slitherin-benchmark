// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.11;

import "./SimpleFactory.sol";
import "./BoringBatchable.sol";
import "./VibeERC20.sol";
import "./VibeERC721.sol";
import "./VibeERC721WithAccount.sol";
import "./VibeERC1155.sol";
import "./RoyaltyReceiver.sol";
import "./NFTMintSale.sol";
import "./NFTMintSaleMultiple.sol";
import "./NFTMintSaleWhitelisting.sol";
import "./NFTMintSaleWhitelistingMultiple.sol";
import "./Airdrop.sol";

contract VibeFactory is BoringBatchable {
    address public immutable vibeERC20Impl;
    address public immutable vibeERC721Impl;
    address public immutable vibeERC721WithAccountImpl;
    address public immutable vibeERC1155Impl;
    address public immutable royaltyReceiverImpl;
    address public immutable nftMintSale;
    address public immutable nftMintSaleMultiple;
    address public immutable nftMintSaleWhitelisting;
    address public immutable nftMintSaleWhitelistingMultiple;
    address public immutable vibeAccountImpl;
    address public immutable vibeAccountRegistryImpl;
    address public immutable airdropImpl;

    SimpleFactory public immutable factory;
    struct Timeframe {
        uint32 beginTime;
        uint32 endTime;
    }

    struct TierInfo {
        uint128 price;
        uint32 beginId;
        uint32 endId;
        uint32 currentId;
    }

    struct NFTInfo {
        string symbol;
        string name;
        string baseURI;
    }

    struct RoyaltyInformation {
        address royaltyReceiver_;
        uint16 royaltyRate_;
        uint16 derivativeRoyaltyRate;
        bool isDerivativeAllowed;
    }

    struct MerkleInformation {
        bytes32 merkleRoot_;
        string externalURI_;
        uint256 maxNonWhitelistedPerUser;
    }

    struct AirdropInformation {
        uint32 beginTime;
        uint32 endTime;
        address paymentToken;
        uint96 fee;
        uint256 maxRedemption;
        bool isPhysical;
        bool specifyId;
    }

    event ERC20Created(
        address indexed sender,
        address indexed proxy,
        bytes data
    );
    event ERC721Created(
        address indexed sender,
        address indexed proxy,
        bytes data
    );
    event ERC1155Created(
        address indexed sender,
        address indexed proxy,
        bytes data
    );
    event LogRoyaltyReceiver(
        address indexed sender,
        address indexed proxy,
        bytes data
    );
    event LogNFTMintSale(
        address indexed sender,
        address indexed proxy,
        bytes data
    );
    event LogNFTMintSaleMultiple(
        address indexed sender,
        address indexed proxy,
        bytes data
    );
    event ClaimantDropCreated(
        address indexed sender,
        address indexed proxy,
        bytes data
    );
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
    event LogAirdrop(address indexed sender, address indexed proxy, bytes data);

    struct TokenHelperStructs {
        SimpleFactory _simpleFactory;
    }

    struct Erc6551Structs {
        address _vibeAccountImpl;
        address _vibeAccountRegistryImpl;
    }

    struct NFTMintSaleStructs {
        address _nftMintSale;
        address _nftMintSaleMultiple;
        address _nftMintSaleWhitelisting;
        address _nftMintSaleWhitelistingMultiple;
    }

    struct TokenStructs {
        address _vibeERC20Impl;
        address _vibeERC721Impl;
        address _vibeERC721WithAccountImpl;
        address _vibeERC1155Impl;
    }

    /**
     * @notice constructor
     * @param tokenStruct implementation address of all token contracts
     * @param _royaltyReceiverImpl implementation address of royalty receiver contract
     * @param nftMintSaleStruct implementation address of all nft mint sale contracts
     * @param tokenHelperStruct struct of simple factory, token helper and weth address
     */
    constructor(
        TokenStructs memory tokenStruct,
        address _royaltyReceiverImpl,
        NFTMintSaleStructs memory nftMintSaleStruct,
        Erc6551Structs memory erc6551Struct,
        TokenHelperStructs memory tokenHelperStruct,
        address _airdropImpl
    ) {
        {
            vibeERC20Impl = tokenStruct._vibeERC20Impl;
            vibeERC721Impl = tokenStruct._vibeERC721Impl;
            vibeERC1155Impl = tokenStruct._vibeERC1155Impl;
            vibeERC721WithAccountImpl = tokenStruct._vibeERC721WithAccountImpl;
        }

        royaltyReceiverImpl = _royaltyReceiverImpl;
        airdropImpl = _airdropImpl;

        {
            nftMintSale = nftMintSaleStruct._nftMintSale;
            nftMintSaleMultiple = nftMintSaleStruct._nftMintSaleMultiple;
            nftMintSaleWhitelisting = nftMintSaleStruct
                ._nftMintSaleWhitelisting;
            nftMintSaleWhitelistingMultiple = nftMintSaleStruct
                ._nftMintSaleWhitelistingMultiple;
        }

        {
            factory = tokenHelperStruct._simpleFactory;
        }

        {
            vibeAccountImpl = erc6551Struct._vibeAccountImpl;
            vibeAccountRegistryImpl = erc6551Struct._vibeAccountRegistryImpl;
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
        NFTInfo memory nftInfo,
        RoyaltyInformation memory royaltyInfo,
        Timeframe memory timeframe,
        uint64 maxMint_,
        uint128 price_,
        IERC20 paymentToken_,
        bool withErc6551Account
    ) external {
        bytes memory data;

        address nft;
        if (withErc6551Account) {
            nft = createERC721WithAccount(
                nftInfo.name,
                nftInfo.symbol,
                nftInfo.baseURI,
                royaltyInfo.royaltyReceiver_,
                royaltyInfo.royaltyRate_,
                royaltyInfo.derivativeRoyaltyRate,
                royaltyInfo.isDerivativeAllowed,
                address(0)
            );
        } else {
            nft = createERC721(
                nftInfo.name,
                nftInfo.symbol,
                nftInfo.baseURI,
                royaltyInfo.royaltyReceiver_,
                royaltyInfo.royaltyRate_,
                royaltyInfo.derivativeRoyaltyRate,
                royaltyInfo.isDerivativeAllowed,
                address(0)
            );
        }

        data = abi.encode(
            nft,
            maxMint_,
            timeframe.beginTime,
            timeframe.endTime,
            price_,
            paymentToken_,
            msg.sender
        );

        address proxy = factory.deploy(nftMintSale, data, false);

        factory.exec(
            nft,
            abi.encodeCall(VibeERC721.setMinter, (proxy, true)),
            0
        );
        factory.transferOwnership(nft, msg.sender);

        emit LogNFTMintSale(msg.sender, proxy, data);
    }

    function createNFTMintSaleWhitelisting(
        NFTInfo memory nftInfo,
        RoyaltyInformation memory royaltyInfo,
        Timeframe memory timeframe,
        uint64 maxMint_,
        uint128 price_,
        IERC20 paymentToken_,
        MerkleInformation memory merkleInformation,
        bool withErc6551Account
    ) external {
        bytes memory data;

        address nft;
        if (withErc6551Account) {
            nft = createERC721WithAccount(
                nftInfo.name,
                nftInfo.symbol,
                nftInfo.baseURI,
                royaltyInfo.royaltyReceiver_,
                royaltyInfo.royaltyRate_,
                royaltyInfo.derivativeRoyaltyRate,
                royaltyInfo.isDerivativeAllowed,
                address(0)
            );
        } else {
            nft = createERC721(
                nftInfo.name,
                nftInfo.symbol,
                nftInfo.baseURI,
                royaltyInfo.royaltyReceiver_,
                royaltyInfo.royaltyRate_,
                royaltyInfo.derivativeRoyaltyRate,
                royaltyInfo.isDerivativeAllowed,
                address(0)
            );
        }

        data = abi.encode(
            nft,
            maxMint_,
            timeframe.beginTime,
            timeframe.endTime,
            price_,
            paymentToken_,
            address(factory)
        );

        address proxy = factory.deploy(nftMintSaleWhitelisting, data, false);

        factory.exec(
            proxy,
            abi.encodeCall(
                NFTMintSaleWhitelisting.setMerkleRoot,
                (
                    merkleInformation.merkleRoot_,
                    merkleInformation.externalURI_,
                    merkleInformation.maxNonWhitelistedPerUser
                )
            ),
            0
        );
        factory.transferOwnership(proxy, msg.sender);

        factory.exec(
            nft,
            abi.encodeCall(VibeERC721.setMinter, (proxy, true)),
            0
        );
        factory.transferOwnership(nft, msg.sender);

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

        emit LogNFTMintSale(msg.sender, proxy, data);
    }

    function createNFTMintSaleMultipleWhitelisting(
        bytes32[] memory merkleRoot_,
        string[] memory externalURI_,
        uint256 maxNonWhitelistedPerUser,
        NFTInfo memory nftInfo,
        RoyaltyInformation memory royaltyInfo,
        Timeframe memory timeframe,
        IERC20 paymentToken_,
        TierInfo[] memory tiers_,
        bool withErc6551Account
    ) external {
        bytes memory data;

        address nft;
        if (withErc6551Account) {
            nft = createERC721WithAccount(
                nftInfo.name,
                nftInfo.symbol,
                nftInfo.baseURI,
                royaltyInfo.royaltyReceiver_,
                royaltyInfo.royaltyRate_,
                royaltyInfo.derivativeRoyaltyRate,
                royaltyInfo.isDerivativeAllowed,
                address(0)
            );
        } else {
            nft = createERC721(
                nftInfo.name,
                nftInfo.symbol,
                nftInfo.baseURI,
                royaltyInfo.royaltyReceiver_,
                royaltyInfo.royaltyRate_,
                royaltyInfo.derivativeRoyaltyRate,
                royaltyInfo.isDerivativeAllowed,
                address(0)
            );
        }

        data = abi.encode(
            nft,
            timeframe.beginTime,
            timeframe.endTime,
            tiers_,
            paymentToken_,
            address(factory)
        );

        address proxy = factory.deploy(
            nftMintSaleWhitelistingMultiple,
            data,
            false
        );
        factory.exec(
            proxy,
            abi.encodeCall(
                NFTMintSaleWhitelistingMultiple.setMerkleRoot,
                (merkleRoot_, externalURI_, maxNonWhitelistedPerUser)
            ),
            0
        );
        factory.transferOwnership(proxy, msg.sender);

        factory.exec(
            nft,
            abi.encodeCall(VibeERC721.setMinter, (proxy, true)),
            0
        );
        factory.transferOwnership(nft, msg.sender);

        emit LogNFTMintSaleMultiple(msg.sender, proxy, data);
    }

    function createNFTMintSaleMultiple(
        NFTInfo memory nftInfo,
        RoyaltyInformation memory royaltyInfo,
        Timeframe memory timeframe,
        TierInfo[] memory tiers_,
        IERC20 paymentToken_,
        bool withErc6551Account
    ) external {
        bytes memory data;

        address nft;
        if (withErc6551Account) {
            nft = createERC721WithAccount(
                nftInfo.name,
                nftInfo.symbol,
                nftInfo.baseURI,
                royaltyInfo.royaltyReceiver_,
                royaltyInfo.royaltyRate_,
                royaltyInfo.derivativeRoyaltyRate,
                royaltyInfo.isDerivativeAllowed,
                address(0)
            );
        } else {
            nft = createERC721(
                nftInfo.name,
                nftInfo.symbol,
                nftInfo.baseURI,
                royaltyInfo.royaltyReceiver_,
                royaltyInfo.royaltyRate_,
                royaltyInfo.derivativeRoyaltyRate,
                royaltyInfo.isDerivativeAllowed,
                address(0)
            );
        }

        data = abi.encode(
            nft,
            timeframe.beginTime,
            timeframe.endTime,
            tiers_,
            paymentToken_,
            msg.sender
        );

        address proxy = factory.deploy(nftMintSaleMultiple, data, false);

        factory.exec(
            nft,
            abi.encodeCall(VibeERC721.setMinter, (proxy, true)),
            0
        );
        factory.transferOwnership(nft, msg.sender);

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

        emit LogNFTMintSaleMultiple(msg.sender, proxy, data);
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
            ),
            0
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

    function createERC721WithAccount(
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
        proxy = factory.deploy(vibeERC721WithAccountImpl, data, false);

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
            ),
            0
        );
        factory.exec(
            proxy,
            abi.encodeCall(
                VibeERC721WithAccount.setAccountInfo,
                (vibeAccountRegistryImpl, vibeAccountImpl)
            ),
            0
        );
        if (owner != address(0)) {
            factory.transferOwnership(proxy, owner);
        }

        emit ERC721Created(msg.sender, proxy, data);
    }

    function createAirdrop(
        NFTInfo memory nftInfo,
        RoyaltyInformation memory royaltyInfo,
        MerkleInformation memory merkleInformation,
        address originalNFT,
        AirdropInformation memory airdropInfo,
        bool withErc6551Account
    ) external returns (address nft, address proxy) {
        if (withErc6551Account) {
            nft = createERC721WithAccount(
                nftInfo.name,
                nftInfo.symbol,
                nftInfo.baseURI,
                royaltyInfo.royaltyReceiver_,
                royaltyInfo.royaltyRate_,
                royaltyInfo.derivativeRoyaltyRate,
                royaltyInfo.isDerivativeAllowed,
                address(0)
            );
        } else {
            nft = createERC721(
                nftInfo.name,
                nftInfo.symbol,
                nftInfo.baseURI,
                royaltyInfo.royaltyReceiver_,
                royaltyInfo.royaltyRate_,
                royaltyInfo.derivativeRoyaltyRate,
                royaltyInfo.isDerivativeAllowed,
                address(0)
            );
        }

        bytes memory data = abi.encode(
            nft,
            originalNFT,
            airdropInfo.beginTime,
            airdropInfo.endTime,
            airdropInfo.paymentToken,
            airdropInfo.fee,
            address(factory),
            airdropInfo.isPhysical,
            airdropInfo.specifyId
        );

        proxy = factory.deploy(airdropImpl, data, false);
        factory.exec(
            proxy,
            abi.encodeCall(
                Airdrop.setMerkleRoot,
                (
                    merkleInformation.merkleRoot_,
                    merkleInformation.externalURI_,
                    merkleInformation.maxNonWhitelistedPerUser
                )
            ),
            0
        );
        factory.exec(
            proxy,
            abi.encodeCall(
                Airdrop.setMaxRedemption,
                (
                    airdropInfo.maxRedemption
                )
            ),
            0
        );

        factory.transferOwnership(proxy, msg.sender);

        factory.exec(
            nft,
            abi.encodeCall(VibeERC721.setMinter, (proxy, true)),
            0
        );
        factory.transferOwnership(nft, msg.sender);
        emit LogAirdrop(msg.sender, proxy, data);
    }
}

