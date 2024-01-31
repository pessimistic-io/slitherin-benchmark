// SPDX-License-Identifier: None
pragma solidity ^0.8.7;
import "./Initializable.sol";
import "./IERC721ReceiverUpgradeable.sol";
import "./IERC721Upgradeable.sol";
import "./IERC20.sol";
import "./Strings.sol";
import "./SafeERC20Upgradeable.sol";
import "./ContextUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";

import "./IVaultBuilder.sol";
import "./IAssetVault.sol";
import "./IMetaWealthModerator.sol";
import "./IMetaWealthFundraiser.sol";
import "./console.sol";

contract MetaWealthFundraiser is
    Initializable,
    ContextUpgradeable,
    IERC721ReceiverUpgradeable,
    ReentrancyGuardUpgradeable,
    IMetaWealthFundraiser
{
    IVaultBuilder vaultBuilder;
    IMetaWealthModerator metawealthMod;

    // Collection => Token ID => Campaign instance
    mapping(address => mapping(uint256 => CampaignInstance))
        public activeCampaigns;

    // Collection => Token ID => Investors[] array
    mapping(address => mapping(uint256 => address[])) public investors;

    // User => Collection => Token ID => Bought shares amount
    mapping(address => mapping(address => mapping(uint256 => uint64)))
        public boughtShares;

    function initialize(
        IVaultBuilder vault,
        IMetaWealthModerator _metawealthMod
    ) public initializer {
        __ReentrancyGuard_init();
        vaultBuilder = vault;
        metawealthMod = _metawealthMod;
    }

    function investments(
        address wallet,
        address collection,
        uint256 tokenId
    ) external view returns (uint256 investment) {
        return getWalletInvestment(wallet, collection, tokenId);
    }

    function getWalletInvestment(
        address wallet,
        address collection,
        uint256 tokenId
    ) public view override returns (uint256 investment) {
        CampaignInstance memory campaign = activeCampaigns[collection][tokenId];
        uint64 _boughtShares = boughtShares[wallet][collection][tokenId];
        return campaign.sharePrice * _boughtShares;
    }

    function getWalletBoughtShares(
        address wallet,
        address collection,
        uint256 tokenId
    ) public view returns (uint64 investment) {
        return boughtShares[wallet][collection][tokenId];
    }

    function getCampaign(
        address collection,
        uint256 tokenId
    ) external view override returns (CampaignInstance memory) {
        return activeCampaigns[collection][tokenId];
    }

    function getInvestors(
        address collection,
        uint256 tokenId
    ) external view override returns (address[] memory) {
        return investors[collection][tokenId];
    }

    function startCampaign(
        address collection,
        uint256 tokenId,
        uint64 sharesToSell,
        uint64 reservedShares,
        uint256 sharePrice,
        address receiverWallet,
        address raiseCurrency,
        uint64 campaignDuration,
        bytes32[] memory _merkleProof
    ) external override nonReentrant {
        require(sharesToSell > 0, "MetaWealthFundraiser: Too few shares");
        require(
            sharePrice > 0,
            "MetaWealthFundraiser: Raise goal not accepted"
        );
        require(
            raiseCurrency != address(0),
            "MetaWealthFundraiser: invalid receiver wallet"
        );
        require(
            activeCampaigns[collection][tokenId].owner == address(0),
            "MetaWealthFundraiser: campaign for this token already exists"
        );
        require(
            metawealthMod.checkVendorWhitelist(_merkleProof, _msgSender()),
            "MetaWealthFundraiser: Not whitelisted"
        );
        require(
            metawealthMod.isSupportedCurrency(raiseCurrency),
            "MetaWealthFundraiser: Raise currency not supported"
        );
        require(
            IERC721Upgradeable(collection).ownerOf(tokenId) == _msgSender(),
            "MetaWealthFundraiser: Caller not asset owner"
        );

        IERC721Upgradeable(collection).safeTransferFrom(
            _msgSender(),
            address(this),
            tokenId,
            ""
        );
        if (reservedShares > 0) {
            investors[collection][tokenId].push(receiverWallet);
        }

        uint32 investFee = metawealthMod.fundraiseInvestorFee();
        uint64 _expirationTimestamp = uint64(
            block.timestamp + campaignDuration
        );
        if (campaignDuration == 0) {
            _expirationTimestamp = uint64(
                block.timestamp + metawealthMod.defaultUnlockPeriod()
            );
        } else {
            require(
                campaignDuration >= 1 weeks,
                "MetaWealthFundraiser: campaignDuration should be at least 1 week"
            );
        }
        activeCampaigns[collection][tokenId] = CampaignInstance(
            _msgSender(),
            sharesToSell,
            investFee,
            receiverWallet,
            reservedShares,
            raiseCurrency,
            sharesToSell,
            sharePrice,
            _expirationTimestamp
        );

        emit CampaignStarted(
            _msgSender(),
            collection,
            tokenId,
            sharesToSell,
            sharePrice,
            raiseCurrency,
            receiverWallet,
            reservedShares,
            _expirationTimestamp
        );
    }

    function invest(
        address collection,
        uint256 tokenId,
        uint64 numberShares,
        bytes32[] memory _userMerkleProof
    ) external override nonReentrant {
        CampaignInstance memory campaign = activeCampaigns[collection][tokenId];

        require(
            metawealthMod.checkWhitelist(_userMerkleProof, _msgSender()),
            "MetaWealthFundraiser: Not whitelisted"
        );
        require(
            campaign.remainingShares >= numberShares,
            "MetaWealthFundraiser: Not enough shares left"
        );
        require(
            campaign.expirationTimestamp >= block.timestamp,
            "MetaWealthFundraiser: campaign expired"
        );
        require(
            numberShares > 0,
            "MetaWealthFundraiser: Should invest for at least 1 share"
        );

        uint256 amount = numberShares * campaign.sharePrice;
        uint256 fee = _calculateFee(amount, campaign.investFee);
        activeCampaigns[collection][tokenId].remainingShares -= numberShares;
        SafeERC20Upgradeable.safeTransferFrom(
            IERC20Upgradeable(campaign.raiseCurrency),
            _msgSender(),
            address(this),
            amount + fee
        );
        bool isReceiver = _msgSender() == campaign.receiverWallet;
        if (
            (boughtShares[_msgSender()][collection][tokenId] == 0 &&
                !isReceiver) || (isReceiver && campaign.reservedShares == 0)
        ) {
            investors[collection][tokenId].push(_msgSender());
        }
        boughtShares[_msgSender()][collection][tokenId] += numberShares;

        emit InvestmentReceived(
            _msgSender(),
            collection,
            tokenId,
            amount,
            campaign.remainingShares == numberShares
        );
    }

    function completeRaise(
        address collection,
        uint256 tokenId,
        string memory assetVaultName,
        string memory assetVaultSymbol,
        bytes32[] memory _fundraiserMerkleProof
    ) external nonReentrant {
        require(
            metawealthMod.isAdmin(_msgSender()),
            "AccessControl: restricted to admins"
        );
        CampaignInstance memory campaign = activeCampaigns[collection][tokenId];
        require(
            campaign.owner != address(0),
            "MetaWealthFundraiser: raise does not exist or already completed"
        );
        require(
            campaign.remainingShares == 0,
            "MetaWealthFundraiser: raise not finished"
        );
        _completeRaise(
            collection,
            tokenId,
            assetVaultName,
            assetVaultSymbol,
            _fundraiserMerkleProof
        );
    }

    function setCampaignExpirationTimestamp(
        address collection,
        uint256 tokenId,
        uint64 _expirationTimestamp
    ) external {
        require(
            metawealthMod.isAdmin(_msgSender()),
            "AccessControl: restricted to admins"
        );
        CampaignInstance memory campaign = activeCampaigns[collection][tokenId];
        require(
            campaign.owner != address(0),
            "MetaWealthFundraiser: raise does not exist or already completed"
        );
        uint64 _old = campaign.expirationTimestamp;
        activeCampaigns[collection][tokenId]
            .expirationTimestamp = _expirationTimestamp;

        emit CampaignExpirationChanged(
            _msgSender(),
            collection,
            tokenId,
            _expirationTimestamp,
            _old
        );
    }

    function cancelRaise(
        address collection,
        uint256 tokenId,
        bytes32[] memory _merkleProof
    ) external override nonReentrant {
        CampaignInstance memory campaign = activeCampaigns[collection][tokenId];

        require(
            campaign.remainingShares > 0,
            "MetaWealthFundraiser: raise does not exist or completed"
        );
        require(
            metawealthMod.checkVendorWhitelist(_merkleProof, _msgSender()),
            "MetaWealthFundraiser: Not whitelisted"
        );
        require(
            campaign.owner == _msgSender() ||
                metawealthMod.isAdmin(_msgSender()),
            "MetaWealthFundraiser: Access forbidden"
        );
        address[] memory activeInvestors = investors[collection][tokenId];

        delete activeCampaigns[collection][tokenId];
        delete investors[collection][tokenId];

        for (uint256 i = 0; i < activeInvestors.length; i++) {
            uint256 _boughtShares = boughtShares[activeInvestors[i]][
                collection
            ][tokenId];
            if (_boughtShares == 0) continue;
            uint256 amount = _boughtShares * campaign.sharePrice;
            uint256 fee = _calculateFee(amount, campaign.investFee);
            delete boughtShares[activeInvestors[i]][collection][tokenId];
            SafeERC20Upgradeable.safeTransfer(
                IERC20Upgradeable(campaign.raiseCurrency),
                activeInvestors[i],
                amount + fee
            );
        }

        IERC721Upgradeable(collection).safeTransferFrom(
            address(this),
            campaign.owner,
            tokenId,
            ""
        );

        emit CampaignCancelled(_msgSender(), collection, tokenId);
    }

    /// @notice make sure campaigns are finished or there are enough funds
    function release(
        IERC20Upgradeable token,
        address account,
        uint256 amount
    ) external {
        require(
            metawealthMod.isSuperAdmin(_msgSender()),
            "MetaWealthFundraiser: Access forbidden"
        );
        SafeERC20Upgradeable.safeTransfer(token, account, amount);

        emit ERC20Released(_msgSender(), account, address(token), amount);
    }

    function _completeRaise(
        address collection,
        uint256 tokenId,
        string memory assetVaultName,
        string memory assetVaulSymbol,
        bytes32[] memory _fundraiserMerkleProof
    ) internal {
        CampaignInstance memory campaign = activeCampaigns[collection][tokenId];
        address[] memory activeInvestors = investors[collection][tokenId];
        delete activeCampaigns[collection][tokenId];
        delete investors[collection][tokenId];

        uint256[] memory _shares = new uint256[](activeInvestors.length);
        uint256 i = 0;
        for (; i < activeInvestors.length; i++) {
            uint256 _boughtShares = boughtShares[activeInvestors[i]][
                collection
            ][tokenId];
            if (activeInvestors[i] == campaign.receiverWallet) {
                _shares[i] = campaign.reservedShares + _boughtShares;
            } else {
                _shares[i] = _boughtShares;
            }

            delete boughtShares[activeInvestors[i]][collection][tokenId];
        }

        IERC721Upgradeable(collection).approve(address(vaultBuilder), tokenId);
        vaultBuilder.fractionalize(
            collection,
            tokenId,
            activeInvestors,
            _shares,
            assetVaultName,
            assetVaulSymbol,
            _fundraiserMerkleProof
        );
        uint256 raised = campaign.sharesToSell * campaign.sharePrice;
        uint256 fee = metawealthMod.calculateFundraiseVendorFee(raised);
        SafeERC20Upgradeable.safeTransfer(
            IERC20Upgradeable(campaign.raiseCurrency),
            campaign.receiverWallet,
            raised - fee
        );

        emit CampaignCompleted(campaign.owner, collection, tokenId);
    }

    function _calculateFee(
        uint256 value,
        uint32 _fee
    ) private pure returns (uint256) {
        return (value * _fee) / 10_000;
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return IERC721ReceiverUpgradeable.onERC721Received.selector;
    }

    uint256[45] private __gap;
}

