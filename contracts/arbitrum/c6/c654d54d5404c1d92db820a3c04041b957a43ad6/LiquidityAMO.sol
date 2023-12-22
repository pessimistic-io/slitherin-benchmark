// Be name Khoda
// Bime Abolfazl
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./AccessControlEnumerableUpgradeable.sol";
import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./IDEI.sol";
import "./IGauge.sol";
import "./ILiquidityAMO.sol";
import "./ISolidly.sol";

contract LiquidityAMO is ILiquidityAMO, AccessControlEnumerableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /* ========== CONSTANTS ========== */
    address public router;
    address public gauge;
    address public dei;
    address public usdc;
    address public usdc_dei;

    /* ========== VARIABLES ========== */
    address public rewardVault;
    address public buybackVault;
    uint256 public deiAmountMinted;
    uint256 public deusValueToSell;
    uint256 public amoProfits;
    uint256 public totalMintLimit;
    uint256 public deiAmountLimit;
    uint256 public lpAmountLimit;
    uint256 public collateralRatio; // decimals 6
    uint256 public validRangeRatio; // decimals 6

    mapping(address => bool) public whitelistedRewardTokens;

    /* ========== ROLES ========== */
    bytes32 public constant WITHDRAWER_ROLE = keccak256("WITHDRAWER_ROLE");
    bytes32 public constant SETTER_ROLE = keccak256("SETTER_ROLE");
    bytes32 public constant AMO_ROLE = keccak256("AMO_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    /* ========== FUNCTIONS ========== */
    function initialize(
        address rewardVault_,
        address buybackVault_,
        uint256 collateralRatio_,
        uint256 validRangeRatio_,
        address admin
    ) public initializer {
        __AccessControlEnumerable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);

        rewardVault = rewardVault_;
        buybackVault = buybackVault_;
        collateralRatio = collateralRatio_;
        validRangeRatio = validRangeRatio_;
    }

    ////////////////////////// SETTER_ROLE ACTIONS //////////////////////////

    function setTokenAddresses(
        address router_,
        address gauge_,
        address dei_,
        address usdc_,
        address usdc_dei_
    ) external onlyRole(SETTER_ROLE) {
        router = router_;
        gauge = gauge_;
        dei = dei_;
        usdc = usdc_;
        usdc_dei = usdc_dei_;
    }

    function setRewardVault(
        address rewardVault_
    ) external onlyRole(SETTER_ROLE) {
        rewardVault = rewardVault_;
        emit SetRewardVault(rewardVault);
    }

    function setBuybackVault(
        address buybackVault_
    ) external onlyRole(SETTER_ROLE) {
        buybackVault = buybackVault_;
        emit SetBuybackVault(buybackVault);
    }

    function setTotalMintLimit(
        uint256 totalMintLimit_
    ) external onlyRole(SETTER_ROLE) {
        totalMintLimit = totalMintLimit_;
        emit SetTotalMintLimit(totalMintLimit);
    }

    function setDeiAmountLimit(
        uint256 deiAmountLimit_
    ) external onlyRole(SETTER_ROLE) {
        deiAmountLimit = deiAmountLimit_;
        emit SetDeiAmountLimit(deiAmountLimit);
    }

    function setLpAmountLimit(
        uint256 lpAmountLimit_
    ) external onlyRole(SETTER_ROLE) {
        lpAmountLimit = lpAmountLimit_;
        emit SetLpAmountLimit(lpAmountLimit);
    }

    function setCollateralRatio(
        uint256 collateralRatio_
    ) external onlyRole(SETTER_ROLE) {
        require(collateralRatio_ <= 1e6, "LiquidityAMO: INVALID_RATIO_VALUE");
        collateralRatio = collateralRatio_;
        emit SetCollateralRatio(collateralRatio);
    }

    function setValidRangeRatio(
        uint256 validRangeRatio_
    ) external onlyRole(SETTER_ROLE) {
        require(validRangeRatio_ <= 1e6, "LiquidityAMO: INVALID_RATIO_VALUE");
        validRangeRatio = validRangeRatio_;
        emit SetValidRangeRatio(validRangeRatio);
    }

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

    function addLiquidityAndDeposit(
        uint256 tokenId,
        uint256 deiAmount,
        uint256 usdcAmount,
        uint256 deiMinAmount,
        uint256 usdcMinAmount,
        uint256 minLiquidity,
        uint256 deadline
    ) external onlyRole(AMO_ROLE) {
        IERC20Upgradeable(dei).safeApprove(router, deiAmount);
        IERC20Upgradeable(usdc).safeApprove(router, usdcAmount);
        (uint256 deiSpent, uint256 usdcSpent, uint256 lpAmount) = ISolidly(
            router
        ).addLiquidity(
                dei,
                usdc,
                true,
                deiAmount,
                usdcAmount,
                deiMinAmount,
                usdcMinAmount,
                address(this),
                deadline
            );
        require(
            lpAmount >= minLiquidity,
            "LiquidityAMO: INSUFFICIENT_OUTPUT_LIQUIDITY"
        );
        uint256 validRange = (deiSpent * validRangeRatio) / 1e6;
        require(
            usdcSpent * 1e12 > deiSpent - validRange &&
                usdcSpent * 1e12 < deiSpent + validRange,
            "LiquidityAMO: INVALID_RANGE_TO_ADD_LIQUIDITY"
        );
        IERC20Upgradeable(usdc_dei).safeApprove(gauge, lpAmount);
        IGauge(gauge).deposit(lpAmount, tokenId);
        emit AddLiquidity(usdcAmount, deiAmount, usdcSpent, deiSpent, lpAmount);
        emit DepositLP(lpAmount, tokenId);
    }

    function mintAndSellDei(
        uint256 deiAmount,
        uint256 deadline
    ) external onlyRole(AMO_ROLE) {
        require(
            deiAmount <= deiAmountLimit,
            "LiquidityAMO: DEI_AMOUNT_LIMIT_EXCEEDED"
        );
        IDEI(dei).mint(address(this), deiAmount);

        IERC20Upgradeable(dei).safeApprove(router, deiAmount);
        ISolidly.route[] memory routes = new ISolidly.route[](1);
        routes[0] = ISolidly.route(dei, usdc, true);
        uint256[] memory amounts = ISolidly(router).swapExactTokensForTokens(
            deiAmount,
            deiAmount / 1e12,
            routes,
            address(this),
            deadline
        );
        amoProfits += deiAmount - amounts[1] * 1e12;
        IERC20Upgradeable(usdc).safeTransfer(
            buybackVault,
            (deiAmount * (1e6 - collateralRatio)) / 1e18
        );
        emit MintDei(deiAmount);
        emit Swap(dei, usdc, deiAmount, amounts[1]);
    }

    function getReward(address[] memory tokens) external onlyRole(AMO_ROLE) {
        uint256[] memory rewardsAmountsBalanceBefore = new uint256[](
            tokens.length
        );
        uint256[] memory rewardsAmounts = new uint256[](tokens.length);
        for (uint i = 0; i < tokens.length; i++) {
            require(
                whitelistedRewardTokens[tokens[i]],
                "LiquidityAMO: NOT_WHITELISTED_REWARD_TOKEN"
            );
            rewardsAmountsBalanceBefore[i] = IERC20Upgradeable(tokens[i])
                .balanceOf(address(this));
        }
        uint256 rewardAmount;
        IGauge(gauge).getReward(address(this), tokens);
        for (uint i = 0; i < tokens.length; i++) {
            rewardAmount =
                IERC20Upgradeable(tokens[i]).balanceOf(address(this)) -
                rewardsAmountsBalanceBefore[i];
            rewardsAmounts[i] = rewardAmount;
            IERC20Upgradeable(tokens[i]).safeTransfer(
                rewardVault,
                rewardAmount
            );
        }
        emit GetReward(tokens, rewardsAmounts);
    }

    function rebalance(
        uint256 lpAmount,
        uint256 deiMinAmount,
        uint256 usdcMinAmount,
        uint256 deadline
    ) external onlyRole(AMO_ROLE) {
        require(
            lpAmount <= lpAmountLimit,
            "LiquidityAMO: LP_AMOUNT_LIMIT_EXCEEDED"
        );
        // unstake LP
        IGauge(gauge).withdraw(lpAmount);

        // remove liquidity
        IERC20Upgradeable(usdc_dei).safeApprove(router, lpAmount);
        (uint256 usdcAmount, uint256 deiAmount) = ISolidly(router)
            .removeLiquidity(
                dei,
                usdc,
                true,
                lpAmount,
                deiMinAmount,
                usdcMinAmount,
                address(this),
                deadline
            );
        require(
            deiAmount >= usdcAmount * 1e12,
            "LiquidityAMO: REBALANCE_WITH_WRONG_PRICE"
        );
        IDEI(dei).burn(deiAmount);

        ISolidly.route[] memory routes = new ISolidly.route[](1);
        routes[0] = ISolidly.route(usdc, dei, true);
        uint256[] memory amounts = ISolidly(router).swapExactTokensForTokens(
            usdcAmount,
            usdcAmount * 1e12,
            routes,
            address(this),
            deadline
        );
        uint256 deiAmountOut = amounts[1];
        IDEI(dei).burn(deiAmountOut);

        deusValueToSell += (deiAmountOut * (1e6 - collateralRatio)) / 1e6;

        emit WithdrawLP(lpAmount);
        emit RemoveLiquidity(
            usdcMinAmount,
            deiMinAmount,
            usdcAmount,
            deiAmount,
            lpAmount
        );
        emit BurnDei(deiAmount);
        emit Swap(usdc, dei, usdcAmount, deiAmountOut);
        emit BurnDei(deiAmountOut);
    }

    ////////////////////////// OPERATOR_ROLE ACTIONS //////////////////////////

    function optInTokens(
        address[] memory tokens
    ) external onlyRole(OPERATOR_ROLE) {
        IGauge(gauge).optIn(tokens);
        emit OptInTokens(tokens);
    }

    function optOutTokens(
        address[] memory tokens
    ) external onlyRole(OPERATOR_ROLE) {
        IGauge(gauge).optOut(tokens);
        emit OptOutTokens(tokens);
    }

    function decreaseDeusValueToSell(
        uint256 value
    ) external onlyRole(OPERATOR_ROLE) {
        emit DecreaseDeusValueToSell(deusValueToSell, value);
        deusValueToSell -= value;
    }

    function stakeLp(
        uint256 amount,
        uint256 tokenId
    ) external onlyRole(OPERATOR_ROLE) {
        IERC20Upgradeable(usdc_dei).safeApprove(gauge, amount);
        IGauge(gauge).deposit(amount, tokenId);
        emit DepositLP(amount, tokenId);
    }

    function mintDei(uint256 deiAmount) external onlyRole(OPERATOR_ROLE) {
        require(
            deiAmountMinted + deiAmount <= totalMintLimit,
            "LiquidityAMO: DEI_MINT_LIMIT_EXCEEDED"
        );
        IDEI(dei).mint(address(this), deiAmount);
        deiAmountMinted += deiAmount;
        emit MintDei(deiAmount);
    }

    ////////////////////////// WITHDRAWER_ROLE ACTIONS //////////////////////////

    function withdrawERC20(
        address token,
        address to,
        uint256 amount
    ) external onlyRole(WITHDRAWER_ROLE) {
        IERC20Upgradeable(token).safeTransfer(to, amount);
    }

    function withdrawAmoProfits(
        address to,
        uint256 amount // in 18 decimals
    ) external onlyRole(WITHDRAWER_ROLE) {
        require(amount <= amoProfits, "LiquidityAMO: HIGH_AMOUNT");
        amoProfits -= amount;
        IERC20Upgradeable(usdc).safeTransfer(to, amount / 1e12);
    }
}

// Dar panahe Khoda

