// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./SafeERC20.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./AccessControlRolesUpgradeable.sol";
import "./AccountRoleVerifier.sol";
import "./AccountRoles.sol";
import "./Account.sol";
import "./LiquidityPool.sol";

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

error InvalidRecipientAddressZero();
error ArgumentLengthMismatch();

/**
 * @notice The Treasury contract holds all the funds.
 */
contract Treasury is
    Initializable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    AccessControlRolesUpgradeable,
    AccountRoleVerifier
{
    using SafeERC20 for IERC20;

    /// @dev Reference to the liquidity pool NFT contract.
    LiquidityPool public liquidityPool;

    event AccountWithdraw(
        uint256 indexed accountId,
        address indexed accountUser,
        address indexed token,
        address recipient,
        uint256 amount,
        uint256[] lpProfitsAmount,
        address[] lpProfitsId
    );

    event EmergencyWithdraw(
        address indexed token,
        address indexed recipient,
        uint256 amount
    );

    event PoolFeeWithdraw(
        uint256 indexed poolId,
        address indexed recipient,
        uint256 amount
    );

    /// @dev Proxy initialisation function.
    function initialize(address _account, address _liquidityPool)
        public
        initializer
    {
        __ReentrancyGuard_init();
        _setupRoles();
        account = Account(_account);
        liquidityPool = LiquidityPool(_liquidityPool);
    }

    /**
     * @dev Processes a withdrawal for an account.
     * @param request The withdraw request struct containing the withdraw data.
     */
    function accountWithdraw(WithdrawRequest calldata request)
        external
        nonReentrant
        onlyOperator
        onlyAccountRole(
            AccountRole.Withdraw,
            request.accountId,
            request.accountUser,
            request.signature
        )
    {
        withdrawToken(request.token, request.recipient, request.amount);
        emit AccountWithdraw(
            request.accountId,
            request.accountUser,
            request.token,
            request.recipient,
            request.amount,
            request.lpProfitsAmount,
            request.lpProfitsId
        );
    }

    function emergencyWithdraw(address token, uint256 amount)
        external
        nonReentrant
        onlyOwner
    {
        withdrawToken(token, msg.sender, amount);
        emit EmergencyWithdraw(token, msg.sender, amount);
    }

    function withdrawToken(
        address token,
        address recipient,
        uint256 amount
    ) private {
        if (recipient == address(0)) {
            revert InvalidRecipientAddressZero();
        }
        IERC20(token).safeTransfer(recipient, amount);
    }

    function withdrawPoolFees(
        uint256[] calldata poolIds,
        address recipient,
        uint256[] calldata amounts
    ) external nonReentrant onlyOperator {
        if (poolIds.length != amounts.length) {
            revert ArgumentLengthMismatch();
        }
        for (uint256 i = 0; i < poolIds.length; i++) {
            withdrawSinglePoolFees(poolIds[i], recipient, amounts[i]);
        }
    }

    function withdrawSinglePoolFees(
        uint256 poolId,
        address recipient,
        uint256 amount
    ) private {
        PoolData memory pool = liquidityPool.getPoolData(poolId);
        withdrawToken(pool.underlyingToken, recipient, amount);
        emit PoolFeeWithdraw(poolId, recipient, amount);
    }

    /// @dev Protected UUPS upgrade authorization function.
    function _authorizeUpgrade(address) internal override onlyOwner {}
}

struct WithdrawRequest {
    /// The trade account ID that is withdrawing.
    uint256 accountId;
    /// The address of the user performing the account action.
    address accountUser;
    /// The token being withdrawn.
    address token;
    /// The address of the recipient of the withdraw.
    address recipient;
    /// The amount being withdrawn.
    uint256 amount;
    /// Amounts of profits withdrawn from LPs.
    uint256[] lpProfitsAmount;
    /// IDs of LPs for which a profit was withdrawn.
    address[] lpProfitsId;
    /// The signature of the account user.
    bytes signature;
}

