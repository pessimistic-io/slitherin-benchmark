// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.10;

import {ParaVersionedInitializable} from "./ParaVersionedInitializable.sol";
import {Errors} from "./Errors.sol";
import {ReserveConfiguration} from "./ReserveConfiguration.sol";
import {PoolLogic} from "./PoolLogic.sol";
import {ReserveLogic} from "./ReserveLogic.sol";
import {SupplyLogic} from "./SupplyLogic.sol";
import {MarketplaceLogic} from "./MarketplaceLogic.sol";
import {BorrowLogic} from "./BorrowLogic.sol";
import {LiquidationLogic} from "./LiquidationLogic.sol";
import {DataTypes} from "./DataTypes.sol";
import {IERC20WithPermit} from "./IERC20WithPermit.sol";
import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {IWETH} from "./IWETH.sol";
import {ItemType} from "./ConsiderationEnums.sol";
import {IPoolAddressesProvider} from "./IPoolAddressesProvider.sol";
import {IPoolMarketplace} from "./IPoolMarketplace.sol";
import {INToken} from "./INToken.sol";
import {IACLManager} from "./IACLManager.sol";
import {PoolStorage} from "./PoolStorage.sol";
import {FlashClaimLogic} from "./FlashClaimLogic.sol";
import {Address} from "./Address.sol";
import {IERC721Receiver} from "./IERC721Receiver.sol";
import {IMarketplace} from "./IMarketplace.sol";
import {Errors} from "./Errors.sol";
import {ParaReentrancyGuard} from "./ParaReentrancyGuard.sol";
import {IAuctionableERC721} from "./IAuctionableERC721.sol";
import {IReserveAuctionStrategy} from "./IReserveAuctionStrategy.sol";

/**
 * @title Pool Marketplace contract
 *
 * @notice Main point of interaction with an ParaSpace protocol's market
 * - Users can:
 *   - buyWithCredit
 *   - acceptBidWithCredit
 *   - batchBuyWithCredit
 *   - batchAcceptBidWithCredit
 * @dev To be covered by a proxy contract, owned by the PoolAddressesProvider of the specific market
 * @dev All admin functions are callable by the PoolConfigurator contract defined also in the
 *   PoolAddressesProvider
 **/
contract PoolMarketplace is
    ParaVersionedInitializable,
    ParaReentrancyGuard,
    PoolStorage,
    IPoolMarketplace
{
    using ReserveLogic for DataTypes.ReserveData;
    using SafeERC20 for IERC20;

    IPoolAddressesProvider internal immutable ADDRESSES_PROVIDER;
    uint256 internal constant POOL_REVISION = 149;

    /**
     * @dev Constructor.
     * @param provider The address of the PoolAddressesProvider contract
     */
    constructor(IPoolAddressesProvider provider) {
        ADDRESSES_PROVIDER = provider;
    }

    function getRevision() internal pure virtual override returns (uint256) {
        return POOL_REVISION;
    }

    /// @inheritdoc IPoolMarketplace
    function buyWithCredit(
        bytes32 marketplaceId,
        bytes calldata payload,
        DataTypes.Credit calldata credit,
        uint16 referralCode
    ) external payable virtual override nonReentrant {
        DataTypes.PoolStorage storage ps = poolStorage();

        MarketplaceLogic.executeBuyWithCredit(
            ps,
            marketplaceId,
            payload,
            credit,
            ADDRESSES_PROVIDER,
            referralCode
        );
    }

    /// @inheritdoc IPoolMarketplace
    function batchBuyWithCredit(
        bytes32[] calldata marketplaceIds,
        bytes[] calldata payloads,
        DataTypes.Credit[] calldata credits,
        uint16 referralCode
    ) external payable virtual override nonReentrant {
        DataTypes.PoolStorage storage ps = poolStorage();

        MarketplaceLogic.executeBatchBuyWithCredit(
            ps,
            marketplaceIds,
            payloads,
            credits,
            ADDRESSES_PROVIDER,
            referralCode
        );
    }

    /// @inheritdoc IPoolMarketplace
    function acceptBidWithCredit(
        bytes32 marketplaceId,
        bytes calldata payload,
        DataTypes.Credit calldata credit,
        address onBehalfOf,
        uint16 referralCode
    ) external virtual override nonReentrant {
        DataTypes.PoolStorage storage ps = poolStorage();

        MarketplaceLogic.executeAcceptBidWithCredit(
            ps,
            marketplaceId,
            payload,
            credit,
            onBehalfOf,
            ADDRESSES_PROVIDER,
            referralCode
        );
    }

    /// @inheritdoc IPoolMarketplace
    function batchAcceptBidWithCredit(
        bytes32[] calldata marketplaceIds,
        bytes[] calldata payloads,
        DataTypes.Credit[] calldata credits,
        address onBehalfOf,
        uint16 referralCode
    ) external virtual override nonReentrant {
        DataTypes.PoolStorage storage ps = poolStorage();

        MarketplaceLogic.executeBatchAcceptBidWithCredit(
            ps,
            marketplaceIds,
            payloads,
            credits,
            onBehalfOf,
            ADDRESSES_PROVIDER,
            referralCode
        );
    }

    // function movePositionFromBendDAO(uint256[] calldata loanIds) external nonReentrant {
    //     DataTypes.PoolStorage storage ps = poolStorage();

    //     PositionMoverLogic.executeMovePositionFromBendDAO(
    //         ps,
    //         ADDRESSES_PROVIDER
    //     );
    // }
}

