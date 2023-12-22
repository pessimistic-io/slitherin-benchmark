// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./Initializable.sol";
import "./AccessControlEnumerableUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./IDEI.sol";
import "./IGauge.sol";
import "./ILiquidityAMO.sol";
import "./ISolidly.sol";

/// @title Liquidity AMO for DEI-USD Solidly pair
/// @author DEUS Finance
/// @notice The LiquidityAMO contract is responsible for maintaining the DEI-USD peg in Solidly pairs. It achieves this through minting and burning DEI tokens, as well as adding and removing liquidity from the DEI-USD pair.
contract LiquidityAMO is
    ILiquidityAMO,
    Initializable,
    AccessControlEnumerableUpgradeable,
    PausableUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /* ========== ROLES ========== */
    bytes32 public constant SETTER_ROLE = keccak256("SETTER_ROLE");
    bytes32 public constant AMO_ROLE = keccak256("AMO_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant REWARD_COLLECTOR_ROLE =
        keccak256("REWARD_COLLECTOR_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");

    /* ========== VARIABLES ========== */
    address public router;
    address public gauge;
    address public dei;
    address public usd;
    address public usd_dei;
    uint256 public usdDecimals;
    address public rewardVault;
    address public buybackVault;
    uint256 public deiAmountMinted;
    uint256 public deusValueToSell;
    uint256 public deiAmountLimit;
    uint256 public lpAmountLimit;
    uint256 public collateralRatio; // decimals 6
    uint256 public validRangeRatio; // decimals 6
    mapping(address => bool) public whitelistedRewardTokens;

    /* ========== FUNCTIONS ========== */
    function initialize(
        address admin,
        address router_,
        address gauge_,
        address dei_,
        address usd_,
        address usd_dei_,
        uint256 usdDecimals_,
        address rewardVault_,
        address buybackVault_
    ) public initializer {
        __AccessControlEnumerable_init();
        __Pausable_init();
        require(
            admin != address(0) &&
                router_ != address(0) &&
                gauge_ != address(0) &&
                dei_ != address(0) &&
                usd_ != address(0) &&
                usd_dei_ != address(0) &&
                rewardVault_ != address(0) &&
                buybackVault_ != address(0),
            "LiquidityAMO: ZERO_ADDRESS"
        );
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        router = router_;
        gauge = gauge_;
        dei = dei_;
        usd = usd_;
        usd_dei = usd_dei_;
        usdDecimals = usdDecimals_;
        rewardVault = rewardVault_;
        buybackVault = buybackVault_;
    }

    ////////////////////////// PAUSE ACTIONS //////////////////////////

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(UNPAUSER_ROLE) {
        _unpause();
    }

    ////////////////////////// SETTER_ROLE ACTIONS //////////////////////////

    /**
     * @notice This function sets the reward and buyback vault addresses
     * @dev Can only be called by an account with the SETTER_ROLE
     * @param rewardVault_ The address of the reward vault
     * @param buybackVault_ The address of the buyback vault
     */
    function setVaults(
        address rewardVault_,
        address buybackVault_
    ) external onlyRole(SETTER_ROLE) {
        require(
            rewardVault_ != address(0) && buybackVault_ != address(0),
            "LiquidityAMO: ZERO_ADDRESS"
        );
        rewardVault = rewardVault_;
        buybackVault = buybackVault_;
    }

    /**
     * @notice This function sets various limits for the contract
     * @dev Can only be called by an account with the SETTER_ROLE
     * @param deiAmountLimit_ The maximum amount of DEI for mintAndSellDei() and rebalance()
     * @param lpAmountLimit_ The maximum amount of LP tokens for rebalance()
     * @param validRangeRatio_ The valid range ratio for addLiquidityAndDeposit()
     */
    function setLimits(
        uint256 deiAmountLimit_,
        uint256 lpAmountLimit_,
        uint256 validRangeRatio_
    ) external onlyRole(SETTER_ROLE) {
        require(validRangeRatio_ <= 1e6, "LiquidityAMO: INVALID_RATIO_VALUE");
        deiAmountLimit = deiAmountLimit_;
        lpAmountLimit = lpAmountLimit_;
        validRangeRatio = validRangeRatio_;
    }

    /**
     * @notice This function sets the collateral ratio for the contract
     * @dev Can only be called by an account with the SETTER_ROLE
     * @param collateralRatio_ The new collateral ratio value
     */
    function setCollateralRatio(
        uint256 collateralRatio_
    ) external onlyRole(SETTER_ROLE) {
        require(collateralRatio_ <= 1e6, "LiquidityAMO: INVALID_RATIO_VALUE");
        collateralRatio = collateralRatio_;
        emit SetCollateralRatio(collateralRatio);
    }

    /**
     * @notice This function sets the reward token whitelist status
     * @dev Can only be called by an account with the SETTER_ROLE
     * @param tokens An array of reward token addresses
     * @param isWhitelisted The new whitelist status for the tokens
     */
    function setRewardToken(
        address[] memory tokens,
        bool isWhitelisted
    ) external onlyRole(SETTER_ROLE) {
        for (uint i = 0; i < tokens.length; i++) {
            whitelistedRewardTokens[tokens[i]] = isWhitelisted;
        }
        emit SetRewardToken(tokens, isWhitelisted);
    }

    ////////////////////////// AMO_ROLE ACTIONS //////////////////////////

    /**
     * @notice This function adds liquidity to the DEI-USD pool and deposits the liquidity tokens to a gauge
     * @dev Can only be called by an account with the AMO_ROLE when the contract is not paused
     * @param tokenId The ID of the veNFT to boost deposited liquidity
     * @param useTokenId The boolean to determine if veNFT should be employed to boost the deposited liquidity
     * @param deiAmount The amount of DEI to be added as liquidity
     * @param usdAmount The amount of USD to be added as liquidity
     * @param deiMinAmount The minimum amount of DEI that must be added to the pool
     * @param usdMinAmount The minimum amount of USD that must be added to the pool
     * @param minLiquidity The minimum amount of liquidity tokens that must be minted from the operation
     * @param deadline Timestamp representing the deadline for the operation to be executed
     */
    function addLiquidityAndDeposit(
        uint256 tokenId,
        bool useTokenId,
        uint256 deiAmount,
        uint256 usdAmount,
        uint256 deiMinAmount,
        uint256 usdMinAmount,
        uint256 minLiquidity,
        uint256 deadline
    ) external onlyRole(AMO_ROLE) whenNotPaused {
        // Approve the transfer of DEI and USD tokens to the router
        IERC20Upgradeable(dei).approve(router, deiAmount);
        IERC20Upgradeable(usd).approve(router, usdAmount);

        // Add liquidity to the DEI-USD pool
        (uint256 deiSpent, uint256 usdSpent, uint256 lpAmount) = ISolidly(
            router
        ).addLiquidity(
                dei,
                usd,
                true,
                deiAmount,
                usdAmount,
                deiMinAmount,
                usdMinAmount,
                address(this),
                deadline
            );

        // Ensure the liquidity tokens minted are greater than or equal to the minimum required
        require(
            lpAmount >= minLiquidity,
            "LiquidityAMO: INSUFFICIENT_OUTPUT_LIQUIDITY"
        );

        // Calculate the valid range for USD spent based on the DEI spent and the validRangeRatio
        uint256 validRange = (deiSpent * validRangeRatio) / 1e6;
        require(
            usdSpent * (10 ** (18 - usdDecimals)) > deiSpent - validRange &&
                usdSpent * (10 ** (18 - usdDecimals)) < deiSpent + validRange,
            "LiquidityAMO: INVALID_RANGE_TO_ADD_LIQUIDITY"
        );

        // Approve the transfer of liquidity tokens to the gauge and deposit them
        IERC20Upgradeable(usd_dei).approve(gauge, lpAmount);
        if (useTokenId) {
            IGauge(gauge).deposit(lpAmount, tokenId);
        } else {
            IGauge(gauge).deposit(lpAmount);
        }
        // Emit events for adding liquidity and depositing liquidity tokens
        emit AddLiquidity(usdAmount, deiAmount, usdSpent, deiSpent, lpAmount);
        emit DepositLP(lpAmount, tokenId);
    }

    /**
     * @notice This function mints DEI tokens and sells them for USD
     * @dev Can only be called by an account with the AMO_ROLE when the contract is not paused
     * @param deiAmount The amount of DEI tokens to be minted and sold
     * @param minUsdAmount The minimum USD amount should be received following the swap
     * @param deadline Timestamp representing the deadline for the operation to be executed
     */
    function mintAndSellDei(
        uint256 deiAmount,
        uint256 minUsdAmount,
        uint256 deadline
    ) external onlyRole(AMO_ROLE) whenNotPaused {
        // Ensure the DEI amount does not exceed the allowed limit
        require(
            deiAmount <= deiAmountLimit,
            "LiquidityAMO: DEI_AMOUNT_LIMIT_EXCEEDED"
        );

        // Mint the specified amount of DEI tokens
        IDEI(dei).mint(address(this), deiAmount);

        // Approve the transfer of DEI tokens to the router
        IERC20Upgradeable(dei).approve(router, deiAmount);

        // Define the route to swap DEI tokens for USD tokens
        ISolidly.route[] memory routes = new ISolidly.route[](1);
        routes[0] = ISolidly.route(dei, usd, true);

        // Execute the swap and store the amounts of tokens involved
        uint256[] memory amounts = ISolidly(router).swapExactTokensForTokens(
            deiAmount,
            deiAmount / (10 ** (18 - usdDecimals)) > minUsdAmount
                ? deiAmount / (10 ** (18 - usdDecimals))
                : minUsdAmount,
            routes,
            address(this),
            deadline
        );

        // Transfer the appropriate amount of USD to the buyback vault
        IERC20Upgradeable(usd).safeTransfer(
            buybackVault,
            (deiAmount * (1e6 - collateralRatio)) /
                (10 ** (6 + 18 - usdDecimals))
        );

        // Emit events for minting DEI tokens and executing the swap
        emit MintDei(deiAmount);
        emit Swap(dei, usd, deiAmount, amounts[1]);
    }

    /**
     * @notice This function rebalances the DEI-USD pool by removing liquidity, burning DEI tokens, and updating the value of DEUS tokens to sell
     * @dev Can only be called by an account with the AMO_ROLE when the contract is not paused
     * @param lpAmount The amount of liquidity tokens to be withdrawn from the gauge
     * @param deiMinAmount The minimum amount of DEI tokens that must be removed from the pool
     * @param usdMinAmount The minimum amount of USD tokens that must be removed from the pool
     * @param deadline Timestamp representing the deadline for the operation to be executed
     */
    function rebalance(
        uint256 lpAmount,
        uint256 deiMinAmount,
        uint256 usdMinAmount,
        uint256 deadline
    ) external onlyRole(AMO_ROLE) whenNotPaused {
        // Ensure the LP amount does not exceed the allowed limit
        require(
            lpAmount <= lpAmountLimit,
            "LiquidityAMO: LP_AMOUNT_LIMIT_EXCEEDED"
        );

        // Withdraw the specified amount of liquidity tokens from the gauge
        IGauge(gauge).withdraw(lpAmount);

        // Approve the transfer of liquidity tokens to the router for removal
        IERC20Upgradeable(usd_dei).approve(router, lpAmount);

        // Remove liquidity and store the amounts of USD and DEI tokens received
        (uint256 usdAmount, uint256 deiAmount) = ISolidly(router)
            .removeLiquidity(
                dei,
                usd,
                true,
                lpAmount,
                deiMinAmount,
                usdMinAmount,
                address(this),
                deadline
            );

        // Ensure the DEI amount is greater than or equal to the USD amount times 1e12
        require(
            deiAmount >= usdAmount * (10 ** (18 - usdDecimals)),
            "LiquidityAMO: REBALANCE_WITH_WRONG_PRICE"
        );

        // Define the route to swap USD tokens for DEI tokens
        ISolidly.route[] memory routes = new ISolidly.route[](1);
        routes[0] = ISolidly.route(usd, dei, true);

        // Execute the swap and store the amounts of tokens involved
        uint256[] memory amounts = ISolidly(router).swapExactTokensForTokens(
            usdAmount,
            usdAmount * (10 ** (18 - usdDecimals)),
            routes,
            address(this),
            deadline
        );

        // Burn the DEI tokens received from the liquidity
        // Burn the DEI tokens received from the swap
        uint256 deiAmountOut = amounts[1];
        IDEI(dei).burn(deiAmount + deiAmountOut);

        // Update the value of DEUS tokens to sell
        deusValueToSell += (deiAmountOut * (1e6 - collateralRatio)) / 1e6;

        // Emit events for withdrawing liquidity tokens, removing liquidity, burning DEI tokens, and executing the swap
        emit WithdrawLP(lpAmount);
        emit RemoveLiquidity(
            usdMinAmount,
            deiMinAmount,
            usdAmount,
            deiAmount,
            lpAmount
        );
        emit Swap(usd, dei, usdAmount, deiAmountOut);
        emit BurnDei(deiAmount);
        emit BurnDei(deiAmountOut);
    }

    ////////////////////////// REWARD_COLLECTOR_ROLE ACTIONS //////////////////////////

    /**
     * @notice This function collects reward tokens from the gauge and transfers them to the reward vault
     * @dev Can only be called by an account with the REWARD_COLLECTOR_ROLE when the contract is not paused
     * @param tokens An array of reward token addresses to be collected
     * @param passTokens The boolean to determine whether tokens should be passed to getReward() function or not
     */
    function getReward(
        address[] memory tokens,
        bool passTokens
    ) external onlyRole(REWARD_COLLECTOR_ROLE) whenNotPaused {
        uint256[] memory rewardsAmounts = new uint256[](tokens.length);
        // Collect the rewards
        if (passTokens) {
            IGauge(gauge).getReward(address(this), tokens);
        } else {
            IGauge(gauge).getReward();
        }
        // Calculate the reward amounts and transfer them to the reward vault
        for (uint i = 0; i < tokens.length; i++) {
            require(
                whitelistedRewardTokens[tokens[i]],
                "LiquidityAMO: NOT_WHITELISTED_REWARD_TOKEN"
            );
            rewardsAmounts[i] = IERC20Upgradeable(tokens[i]).balanceOf(
                address(this)
            );
            IERC20Upgradeable(tokens[i]).safeTransfer(
                rewardVault,
                rewardsAmounts[i]
            );
        }
        // Emit an event for collecting rewards
        emit GetReward(tokens, rewardsAmounts);
    }

    ////////////////////////// OPERATOR_ROLE ACTIONS //////////////////////////

    /**
     * @notice This function allows to call arbitrary functions on external contracts
     * @dev Can only be called by an account with the OPERATOR_ROLE
     * @param _target The address of the external contract to call
     * @param _calldata The calldata to be passed to the external contract call
     * @return _success A boolean indicating whether the call was successful
     * @return _resultdata The data returned by the external contract call
     */
    function _call(
        address _target,
        bytes calldata _calldata
    )
        external
        payable
        onlyRole(OPERATOR_ROLE)
        returns (bool _success, bytes memory _resultdata)
    {
        return _target.call{value: msg.value}(_calldata);
    }

    /**
     * @notice This function decreases the value of DEUS tokens to sell
     * @dev Can only be called by an account with the OPERATOR_ROLE
     * @param value The amount to decrease the DEUS value to sell
     */
    function decreaseDeusValueToSell(
        uint256 value
    ) external onlyRole(OPERATOR_ROLE) {
        emit DecreaseDeusValueToSell(deusValueToSell, value);
        deusValueToSell -= value;
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public virtual returns (bytes4) {
        return this.onERC721Received.selector;
    }
}

