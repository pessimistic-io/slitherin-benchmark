// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {     LPVault,     FixedPointMath,     OneInchZapLib,     I1inchAggregationRouterV4,     SafeERC20,     IERC20,     IUniswapV2Pair } from "./LPVault.sol";
import {IUniswapV2Router01} from "./IUniswapV2Router01.sol";

contract BullLPVault is LPVault {
    using OneInchZapLib for I1inchAggregationRouterV4;
    using FixedPointMath for uint256;

    IUniswapV2Router01 private _sushiSwap;

    constructor(
        address _depositToken,
        address _storage,
        string memory _name,
        uint256 _riskPercentage,
        uint256 _feePercentage,
        address _feeReceiver,
        address payable _router,
        uint256 _cap,
        address _farm
    ) LPVault(_depositToken, _storage, _name, _riskPercentage, _feePercentage, _feeReceiver, _router, _cap, _farm) {
        vaultType = VaultType.BULL;
        _sushiSwap = OneInchZapLib.sushiSwapRouter;
    }

    /**
     * @notice Used for the strategy contract to borrow from the vault. Only a % of the vault tokens
     * can be borrowed. The borrowed amount is split and the underlying tokens are transferred to
     * the strategy
     * @param _minTokenOutputs The minimum amount of underlying tokens to receive when removing
     * liquidity
     */
    function borrow(uint256[2] calldata _minTokenOutputs) external onlyRole(STRATEGY) returns (uint256) {
        if (paused) {
            revert VAULT_PAUSED();
        }
        // Can only borrow once per epoch
        if (borrowed) {
            revert ALREADY_BORROWED();
        }

        IUniswapV2Pair pair = IUniswapV2Pair(address(depositToken));

        uint256 tokenBalance = pair.balanceOf(address(this));

        uint256 amount = (tokenBalance + _getStakedAmount()).mulDivDown(riskPercentage, ACCURACY);

        if (tokenBalance < amount) {
            _unstake(amount - tokenBalance);
        }

        borrowed = true;

        address[2] memory tokens = [pair.token0(), pair.token1()];

        pair.approve(address(_sushiSwap), amount);
        _sushiSwap.removeLiquidity(
            tokens[0], tokens[1], amount, _minTokenOutputs[0], _minTokenOutputs[1], address(this), block.timestamp
        );

        for (uint256 i; i < tokens.length; i++) {
            IERC20(tokens[i]).transfer(msg.sender, IERC20(tokens[i]).balanceOf(address(this)));
        }

        emit Borrowed(msg.sender, amount);

        return amount;
    }

    /**
     * @notice Used for the strategy contract to repay the LP tokens that were borrowed. The
     * underlying pair tokens get trasnferred to the vault contract and then zapped in
     */
    function repay(
        uint256 _minPairTokens,
        address[] calldata _inTokens,
        uint256[] calldata _inTokenAmounts,
        OneInchZapLib.SwapParams[] calldata _swapParams
    ) external onlyRole(STRATEGY) returns (uint256) {
        IUniswapV2Pair pair = IUniswapV2Pair(address(depositToken));

        // Get all input tokens
        for (uint256 i; i < _inTokens.length; i++) {
            IERC20(_inTokens[i]).transferFrom(msg.sender, address(this), _inTokenAmounts[i]);
        }

        // Perform all the swaps
        for (uint256 i; i < _swapParams.length; i++) {
            OneInchZapLib.SwapParams memory swap = _swapParams[i];
            if (swap.desc.dstReceiver != address(this)) {
                revert FORBIDDEN_SWAP_RECEIVER();
            }
            if (swap.desc.dstToken != pair.token0() && swap.desc.dstToken != pair.token1()) {
                revert FORBIDDEN_SWAP_DESTINATION();
            }
            router.perform1InchSwap(swap);
        }

        // Deposit as LP tokens
        uint256 actualLpTokens = OneInchZapLib.uniDeposit(
            pair.token0(),
            pair.token1(),
            IERC20(pair.token0()).balanceOf(address(this)),
            IERC20(pair.token1()).balanceOf(address(this))
        );

        if (actualLpTokens < _minPairTokens) {
            revert HIGH_SLIPPAGE();
        }

        emit Repayed(msg.sender, actualLpTokens);

        return actualLpTokens;
    }
}

