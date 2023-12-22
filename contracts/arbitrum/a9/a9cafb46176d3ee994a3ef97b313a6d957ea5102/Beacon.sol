// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./SafeERC20.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./IBeaconEvents.sol";
import "./AccessControlRolesUpgradeable.sol";
import "./AccountRoles.sol";
import "./AccountRoleVerifier.sol";
import "./Account.sol";

/*                                                *\
 *                ,.-"""-.,                       *
 *               /   ===   \                      *
 *              /  =======  \                     *
 *           __|  (o)   (0)  |__                  *
 *          / _|    .---.    |_ \                 *
 *         | /.----/ O O \----.\ |                *
 *          \/     |     |     \/                 *
 *          |                   |                 *
 *          |                   |                 *
 *          |                   |                 *
 *          _\   -.,_____,.-   /_                 *
 *      ,.-"  "-.,_________,.-"  "-.,             *
 *     /          |       |  ╭-╮     \            *
 *    |           l.     .l  ┃ ┃      |           *
 *    |            |     |   ┃ ╰━━╮   |           *
 *    l.           |     |   ┃ ╭╮ ┃  .l           *
 *     |           l.   .l   ┃ ┃┃ ┃  | \,         *
 *     l.           |   |    ╰-╯╰-╯ .l   \,       *
 *      |           |   |           |      \,     *
 *      l.          |   |          .l        |    *
 *       |          |   |          |         |    *
 *       |          |---|          |         |    *
 *       |          |   |          |         |    *
 *       /"-.,__,.-"\   /"-.,__,.-"\"-.,_,.-"\    *
 *      |            \ /            |         |   *
 *      |             |             |         |   *
 *       \__|__|__|__/ \__|__|__|__/ \_|__|__/    *
\*                                                 */

/**
 * @notice The Beacon contract is the bridge between the trade compute servers
 *         and the on-chain state.
 *
 *         This contract's operator, a trade server node, calls this contract
 *         to emit events for all system actions.
 *         Until the contract call is finalised on-chain, the action is not
 *         canonical and therefore not final.
 *
 *         Events emitted by this contract may be indexed, in sequence, to
 *         build the canonical state of the trade application.
 */
contract Beacon is
    Initializable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    AccessControlRolesUpgradeable,
    AccountRoleVerifier,
    IBeaconEvents
{
    using SafeERC20 for IERC20;

    /// @dev Proxy initialisation function.
    function initialize(address _account) public initializer {
        __ReentrancyGuard_init();
        _setupRoles();
        account = Account(_account);
    }

    function pause() external onlyAdmin {
        _pause();
    }

    function unpause() external onlyAdmin {
        _unpause();
    }

    function liquidate(TradeRequest[] calldata tradeRequest)
        external
        onlyOperator
        whenNotPaused
    {
        for (uint256 i = 0; i < tradeRequest.length; i++) {
            _trade(tradeRequest[i], TradeType.Liquidation);
        }
    }

    function _trade(TradeRequest calldata tradeRequest, TradeType tradeType)
        private
    {
        emit Trade(
            tradeRequest.pair,
            tradeRequest.accountId,
            tradeRequest.liquidityPool,
            tradeRequest.accountUser,
            tradeRequest.price,
            tradeRequest.size,
            tradeRequest.marginFee,
            tradeType
        );
    }

    function trade(TradeRequest calldata tradeRequest, bytes calldata signature)
        external
        whenNotPaused
        onlyOperator
        onlyAccountRole(
            AccountRole.Trader,
            tradeRequest.accountId,
            tradeRequest.accountUser,
            signature
        )
    {
        _trade(tradeRequest, TradeType.Trade);
    }

    /**
     * Emits borrow fee events. This should be extensible, so upgrading the
     * contract won't break the subgraph.
     * @param borrowFees - an array of borrow fees to be collected
     * @param fundingFees - an array of funding fees to be collected/paid
     */
    function collectFees(
        PositionFee[] calldata borrowFees,
        PositionFee[] calldata fundingFees
    ) external onlyOperator whenNotPaused {
        emit CollectBorrowFees(borrowFees);
        emit CollectFundingFees(fundingFees);
    }

    /// @dev Protected UUPS upgrade authorization function.
    function _authorizeUpgrade(address) internal override onlyOwner {}
}

struct TradeRequest {
    bytes32 pair;
    uint256 accountId;
    uint256 liquidityPool;
    int256 price;
    int256 size;
    uint256 marginFee;
    address accountUser;
}

