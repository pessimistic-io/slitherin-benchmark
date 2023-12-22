// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./ReentrancyGuard.sol";
import "./SafeERC20.sol";
import "./ERC20.sol";
import "./IRewardPool.sol";

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

/// @notice A receipt token for an ERC20 stake in the RewardPool.
contract StakedErc20 is ERC20, ReentrancyGuard {
    using SafeERC20 for ERC20;

    ERC20 public immutable depositToken;
    IRewardPool public immutable rewardPool;
    bytes32 public immutable rewardPoolAlias;

    modifier onlyRewardPool() {
        require(msg.sender == address(rewardPool), "StakedErc20: unauthorised");
        _;
    }

    constructor(
        string memory name_,
        string memory symbol_,
        address depositToken_,
        address rewardPool_,
        bytes32 rewardPoolAlias_
    ) ERC20(name_, symbol_) {
        require(
            depositToken_ != address(0) && rewardPool_ != address(0),
            "StakedErc20: invalid address"
        );
        require(depositToken_ != rewardPool_);
        require(depositToken_ != address(this));
        depositToken = ERC20(depositToken_);
        rewardPool = IRewardPool(rewardPool_);
        rewardPoolAlias = rewardPoolAlias_;
    }

    function decimals() public view override returns (uint8) {
        return depositToken.decimals();
    }

    /**
     * @dev Allows the RewardPool contract to mint tokens for stakers.
     * @param account The address to mint to.
     * @param amount The token amount to mint.
     */
    function mint(address account, uint256 amount) external onlyRewardPool {
        _validateMint(account, amount);
        _mint(account, amount);
    }

    /**
     * @dev Allows the RewardPool contract to burn tokens for stakers.
     * @param account The address to burn from.
     * @param amount The token amount to burn.
     */
    function burn(address account, uint256 amount) external onlyRewardPool {
        _validateBurn(account, amount);
        _burn(account, amount);
    }

    /**
     * @dev Overrides the _transfer function, unstaking the underlying
     *      assets from the sender and staking for the recipient.
     *      This ensures that all holders have a balance equal to
     *      their stake amount of the RewardPool contract.
     *      Rather than transferring, tokens are burned from the sender
     *      and minted to the receiver via the RewardPool.
     * @param sender The address of the token sender.
     * @param recipient The address of the token recipient.
     * @param amount The token amount being transferred.
     */
    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal override nonReentrant {
        uint256 poolId = _getRewardPoolId();
        // Unstake for the sender. The underlying token is
        // transferred into this contract.
        uint256 unstakeError = rewardPool.unstake(sender, amount, poolId);
        require(unstakeError == 0, "StakedErc20: failed to unstake sender");
        // Approve RewardPool to spend the underlying token.
        depositToken.safeApprove(address(rewardPool), amount);
        // Stake the underlying token for the receiver.
        uint256 stakeError = rewardPool.stake(recipient, amount, poolId);
        require(stakeError == 0, "StakedErc20: failed to stake receiver");
    }

    /**
     * @dev Validates the mint by checking that the resulting token
     *      balance for the user matches their deposit in RewardPool.
     * @param account The address to mint to.
     * @param amount The token amount to mint.
     */
    function _validateMint(address account, uint256 amount) private view {
        uint256 deposit = _getDepositAmount(account);
        uint256 futureBalance = balanceOf(account) + amount;
        require(deposit == futureBalance, "StakedErc20: mint is invalid");
    }

    /**
     * @dev Validates the burn by checking that the resulting token
     *      balance for the user matches their deposit in RewardPool.
     * @param account The address to burn from.
     * @param amount The token amount to burn.
     */
    function _validateBurn(address account, uint256 amount) private view {
        uint256 deposit = _getDepositAmount(account);
        uint256 futureBalance = balanceOf(account) - amount;
        require(deposit == futureBalance, "StakedErc20: burn is invalid");
    }

    /**
     * @dev Gets the deposit amount from the specified RewardPool.
     * @param account The user address to get the deposit for.
     */
    function _getDepositAmount(address account) private view returns (uint256) {
        uint256 poolId = _getRewardPoolId();
        return rewardPool.getDeposit(account, poolId).amount;
    }

    /**
     * @dev Gets the reward pool ID from the alias.
     */
    function _getRewardPoolId() private view returns (uint256) {
        (bool found, uint256 poolId) =
            rewardPool.getPoolIdByAlias(rewardPoolAlias);
        require(found, "StakedErc20: reward pool not found");
        return poolId;
    }
}

