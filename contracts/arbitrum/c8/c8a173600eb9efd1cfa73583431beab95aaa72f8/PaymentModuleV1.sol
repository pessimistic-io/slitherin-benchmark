// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./AccessControlEnumerable.sol";
import "./IERC1155.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./IERC721.sol";
import "./IERC721Receiver.sol";
import "./IUniswapV2Pair.sol";
import "./IUniswapV2Router01.sol";

import "./console.sol";

import "./IDepositHandler.sol";
import "./ILPTokenProcessor.sol";
import "./IPaymentModule.sol";
import "./IPricingModule.sol";
import "./INonfungiblePositionManager.sol";
import "./IUniswapPair.sol";

contract PaymentModuleV1 is IDepositHandler, IPaymentModule, AccessControlEnumerable, IERC721Receiver {
    using SafeERC20 for IERC20;

    address public constant burnAddress = 0x000000000000000000000000000000000000dEaD;
    address public immutable FLOKI;
    bytes32 public constant PAYMENT_ADMIN_ROLE = keccak256("PAYMENT_ADMIN_ROLE");

    ILPTokenProcessor public lpTokenProcessor;
    IPricingModule public pricingModule;
    IUniswapV2Router01 public routerForFloki;
    address public treasury;
    IERC20 public USDT;

    uint256 public constant referrerBasisPoints = 2500;
    uint256 public constant burnBasisPoints = 2500;

    event LPTokenProcessorUpdated(address indexed oldProcessor, address indexed newProcessor);
    event PricingModuleUpdated(address indexed oldModule, address indexed newModule);
    event TreasuryAddressUpdated(address indexed oldTreasury, address indexed newTreasury);

    constructor(
        address flokiAddress,
        address lpTokenProcessorAddress,
        address pricingModuleAddress,
        address treasuryAddress,
        address uniswapV2RouterAddress,
        address usdtAddress
    ) {
        require(
            pricingModuleAddress != address(0),
            "PaymentModuleV1::constructor::ZERO: Pricing module cannot be zero address."
        );
        require(
            uniswapV2RouterAddress != address(0),
            "PaymentModuleV1::constructor::ZERO: Router cannot be zero address."
        );
        require(usdtAddress != address(0), "PaymentModuleV1::constructor::ZERO: USDT cannot be zero address.");

        FLOKI = flokiAddress;
        pricingModule = IPricingModule(pricingModuleAddress);
        lpTokenProcessor = ILPTokenProcessor(lpTokenProcessorAddress);
        routerForFloki = IUniswapV2Router01(uniswapV2RouterAddress);
        treasury = treasuryAddress;
        USDT = IERC20(usdtAddress);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function processPayment(ProcessPaymentParams memory params) external payable override onlyRole(PAYMENT_ADMIN_ROLE) {
        IPricingModule.PriceInfo memory price = pricingModule.getPrice(
            params.user,
            params.fungibleTokenDeposits,
            params.nonFungibleTokenDeposits,
            params.multiTokenDeposits,
            params.isVesting
        );

        // Process token payments first.
        for (uint256 i = 0; i < params.fungibleTokenDeposits.length; i++) {
            // First transfer the full sum of the tokens to the payment processor.
            IERC20(params.fungibleTokenDeposits[i].tokenAddress).safeTransferFrom(
                params.user,
                address(this),
                params.fungibleTokenDeposits[i].amount
            );
            // Then transfer tokens that are to be locked to the vault (lpV2Tokens[i] is zero for non-LP tokens).
            IERC20(params.fungibleTokenDeposits[i].tokenAddress).safeTransfer(
                params.vault,
                params.fungibleTokenDeposits[i].amount - price.v2LpAmounts[i]
            );
            if (params.fungibleTokenDeposits[i].tokenAddress == price.v2LpTokens[i]) {
                // In case of no referrer the LP share is zero. Setting it
                // at this level allows for easier subtraction later on.
                uint256 referrerLPShare = 0;
                if (params.referrer != address(0)) {
                    referrerLPShare = (price.v2LpAmounts[i] * referrerBasisPoints) / 10000;
                }

                // Send LP tokens to the Keepers-powered LP token processor.
                // The LP token processor will take care of liquidating, swapping for USDT and paying referrers.
                lpTokenProcessor.addTokenForSwapping(
                    params.fungibleTokenDeposits[i].tokenAddress,
                    IUniswapPair(params.fungibleTokenDeposits[i].tokenAddress).factory(),
                    true,
                    params.referrer,
                    referrerLPShare
                );
                // It's important to know that these subtractions never
                // cause an underflow. The number in `lpV2Amounts[i]` is
                // non-zero after the transfer to the vault.
                IERC20(params.fungibleTokenDeposits[i].tokenAddress).safeTransfer(
                    address(lpTokenProcessor),
                    price.v2LpAmounts[i]
                );
            }
        }

        // Process NFT
        for (uint256 i = 0; i < params.nonFungibleTokenDeposits.length; i++) {
            // First, transfer the tokens to the payment processor.
            IERC721(params.nonFungibleTokenDeposits[i].tokenAddress).safeTransferFrom(
                params.user,
                address(this),
                params.nonFungibleTokenDeposits[i].tokenId
            );
            if (params.nonFungibleTokenDeposits[i].tokenAddress == price.v3LpTokens[i].tokenAddress) {
                // For V3 LP positions, we need to remove our share of the liquidity
                // amount0Min and amount1Min are price slippage checks
                // if the amount received after burning is not greater than these minimums, transaction will fail
                require(
                    price.v3LpTokens[i].liquidityToRemove > 0,
                    "PaymentModuleV1::processPayment::ZERO: Liquidity to remove cannot be zero."
                );
                (uint256 amount0, uint256 amount1) = INonfungiblePositionManager(price.v3LpTokens[i].tokenAddress)
                    .decreaseLiquidity(
                        INonfungiblePositionManager.DecreaseLiquidityParams({
                            tokenId: params.nonFungibleTokenDeposits[i].tokenId,
                            liquidity: price.v3LpTokens[i].liquidityToRemove,
                            amount0Min: 0,
                            amount1Min: 0,
                            deadline: block.timestamp
                        })
                    );
                (amount0, amount1) = INonfungiblePositionManager(price.v3LpTokens[i].tokenAddress).collect(
                    INonfungiblePositionManager.CollectParams({
                        tokenId: params.nonFungibleTokenDeposits[i].tokenId,
                        recipient: address(this),
                        amount0Max: type(uint128).max,
                        amount1Max: type(uint128).max
                    })
                );
                // Send unpaired tokens to the Keepers-powered LP token processor.
                // The LP token processor will take care of liquidating, swapping for USDT and paying referrers.
                uint256 referrerShare0 = 0;
                uint256 referrerShare1 = 0;
                uint256 balance0 = IERC20(price.v3LpTokens[i].token0).balanceOf(address(this));
                uint256 balance1 = IERC20(price.v3LpTokens[i].token1).balanceOf(address(this));
                if (params.referrer != address(0)) {
                    referrerShare0 = (balance0 * referrerBasisPoints) / 10000;
                    referrerShare1 = (balance1 * referrerBasisPoints) / 10000;
                }
                address factory = routerForFloki.factory();
                // send tokens to LP Token Processor
                IERC20(price.v3LpTokens[i].token0).safeTransfer(address(lpTokenProcessor), balance0);
                IERC20(price.v3LpTokens[i].token1).safeTransfer(address(lpTokenProcessor), balance1);
                lpTokenProcessor.addTokenForSwapping(
                    price.v3LpTokens[i].token0,
                    factory,
                    false,
                    params.referrer,
                    referrerShare0
                );
                lpTokenProcessor.addTokenForSwapping(
                    price.v3LpTokens[i].token1,
                    factory,
                    false,
                    params.referrer,
                    referrerShare1
                );
            }
            IERC721(params.nonFungibleTokenDeposits[i].tokenAddress).safeTransferFrom(
                address(this),
                params.vault,
                params.nonFungibleTokenDeposits[i].tokenId
            );
        }

        // Process Multi Token
        for (uint256 i = 0; i < params.multiTokenDeposits.length; i++) {
            IERC1155(params.multiTokenDeposits[i].tokenAddress).safeTransferFrom(
                params.user,
                params.vault,
                params.multiTokenDeposits[i].tokenId,
                params.multiTokenDeposits[i].amount,
                ""
            );
        }

        // Process USDT payment if needed.
        uint256 toBeRefunded = _processFee(price.usdtAmount, params.user, params.referrer);
        (bool success, ) = payable(params.user).call{ value: toBeRefunded }("");
        require(success, "Failed to refund leftover eth");
    }

    function _processFee(
        uint256 usdtAmount,
        address user,
        address referrer
    ) private returns (uint256 toBeRefunded) {
        if (usdtAmount > 0) {
            uint256 usdBalance = usdtAmount;
            if (msg.value > 0) {
                // if user is paying with native token, we swap it by USDT
                address[] memory path = new address[](2);
                path[0] = routerForFloki.WETH();
                path[1] = address(USDT);
                uint256 oldEthBalance = address(this).balance;
                routerForFloki.swapETHForExactTokens{ value: msg.value }(
                    usdtAmount,
                    path,
                    address(this),
                    block.timestamp
                );
                usdBalance = USDT.balanceOf(address(this));
                require(usdBalance == usdtAmount, "Not enough ETH to cover fees");
                // refund any extra ETH sent
                toBeRefunded = msg.value - (oldEthBalance - address(this).balance);
            } else {
                USDT.safeTransferFrom(user, address(this), usdtAmount);
            }

            uint256 referrerUSDTShare = 0;
            if (referrer != address(0)) {
                referrerUSDTShare = (usdtAmount * referrerBasisPoints) / 10000;

                USDT.safeTransfer(referrer, referrerUSDTShare);
            }

            uint256 burnShare = 0;
            if (FLOKI != address(0)) {
                burnShare = (usdtAmount * burnBasisPoints) / 10000;
                USDT.safeTransfer(address(lpTokenProcessor), burnShare);
                lpTokenProcessor.swapTokens(address(USDT), burnShare, FLOKI, burnAddress, address(routerForFloki));
            }

            USDT.safeTransfer(treasury, usdBalance - referrerUSDTShare - burnShare);
        }
    }

    function setLPTokenProcessor(address newProcessor) external onlyRole(DEFAULT_ADMIN_ROLE) {
        address oldProcessor = address(lpTokenProcessor);
        lpTokenProcessor = ILPTokenProcessor(newProcessor);

        emit LPTokenProcessorUpdated(oldProcessor, newProcessor);
    }

    function setPricingModule(address newModule) external onlyRole(DEFAULT_ADMIN_ROLE) {
        address oldModule = address(pricingModule);
        pricingModule = IPricingModule(newModule);

        emit PricingModuleUpdated(oldModule, newModule);
    }

    function setTreasury(address newTreasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        address oldTreasury = treasury;
        treasury = newTreasury;

        emit TreasuryAddressUpdated(oldTreasury, newTreasury);
    }

    function adminWithdraw(address tokenAddress, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (tokenAddress == address(0)) {
            // We specifically ignore this return value.
            payable(treasury).call{ value: amount }("");
        } else {
            IERC20(tokenAddress).safeTransfer(treasury, amount);
        }
    }

    receive() external payable {}

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }
}

