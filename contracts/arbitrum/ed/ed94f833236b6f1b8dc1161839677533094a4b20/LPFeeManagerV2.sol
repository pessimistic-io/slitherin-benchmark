// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.13;

/*
  ______                     ______                                 
 /      \                   /      \                                
|  ▓▓▓▓▓▓\ ______   ______ |  ▓▓▓▓▓▓\__   __   __  ______   ______  
| ▓▓__| ▓▓/      \ /      \| ▓▓___\▓▓  \ |  \ |  \|      \ /      \ 
| ▓▓    ▓▓  ▓▓▓▓▓▓\  ▓▓▓▓▓▓\\▓▓    \| ▓▓ | ▓▓ | ▓▓ \▓▓▓▓▓▓\  ▓▓▓▓▓▓\
| ▓▓▓▓▓▓▓▓ ▓▓  | ▓▓ ▓▓    ▓▓_\▓▓▓▓▓▓\ ▓▓ | ▓▓ | ▓▓/      ▓▓ ▓▓  | ▓▓
| ▓▓  | ▓▓ ▓▓__/ ▓▓ ▓▓▓▓▓▓▓▓  \__| ▓▓ ▓▓_/ ▓▓_/ ▓▓  ▓▓▓▓▓▓▓ ▓▓__/ ▓▓
| ▓▓  | ▓▓ ▓▓    ▓▓\▓▓     \\▓▓    ▓▓\▓▓   ▓▓   ▓▓\▓▓    ▓▓ ▓▓    ▓▓
 \▓▓   \▓▓ ▓▓▓▓▓▓▓  \▓▓▓▓▓▓▓ \▓▓▓▓▓▓  \▓▓▓▓▓\▓▓▓▓  \▓▓▓▓▓▓▓ ▓▓▓▓▓▓▓ 
         | ▓▓                                             | ▓▓      
         | ▓▓                                             | ▓▓      
          \▓▓                                              \▓▓         

 * App:             https://apeswap.finance
 * Medium:          https://ape-swap.medium.com
 * Twitter:         https://twitter.com/ape_swap
 * Discord:         https://discord.com/invite/apeswap
 * Telegram:        https://t.me/ape_swap
 * Announcements:   https://t.me/ape_swap_news
 * GitHub:          https://github.com/ApeSwapFinance
 */

import "./IApeRouter02.sol";
import "./IApeFactory.sol";
import "./IApePair.sol";
import "./SweeperUpgradeable.sol";

/// @title LP fee manager
/// @author ApeSwap.finance
/// @notice Swap LP token fees collected to different token
contract LPFeeManagerV2 is SweeperUpgradeable {
    IApeRouter02 public router;
    IApeFactory public factory;

    event LiquidityRemoved(
        address indexed pairAddress,
        uint256 amountA,
        uint256 amountB
    );
    event LiquidityRemovalFailed(address indexed pairAddress);
    event Swap(uint256 amountIn, uint256 amountOut, address[] path);
    event SwapFailed(uint256 amountIn, uint256 amountOut, address[] path);

    function initialize(address _router) external initializer {
        __Ownable_init();
        router = IApeRouter02(_router);
        factory = IApeFactory(router.factory());
        // Setup Sweeper to allow native withdraws
        allowNativeSweep = true;
    }

    // @notice Allow this contract to receive native tokens
    receive() external payable {}

    /// @notice Remove LP and unwrap to base tokens
    /// @param _lpTokens address list of LP tokens to unwrap
    /// @param _amounts Amount of each LP token to sell
    /// @param _token0Outs Minimum token 0 output requested.
    /// @param _token1Outs Minimum token 1 output requested.
    /// @param _to address the tokens need to be transferred to.
    /// @param _revertOnFailure If false, the tx will not revert on liquidity removal failures
    function removeLiquidityTokens(
        address[] calldata _lpTokens,
        uint256[] calldata _amounts,
        uint256[] calldata _token0Outs,
        uint256[] calldata _token1Outs,
        address _to,
        bool _revertOnFailure
    ) external onlyOwner {
        address toAddress = _to == address(0) ? address(this) : _to;

        for (uint256 i = 0; i < _lpTokens.length; i++) {
            IApePair pair = IApePair(_lpTokens[i]);
            pair.approve(address(router), _amounts[i]);
            try
                router.removeLiquidity(
                    pair.token0(),
                    pair.token1(),
                    _amounts[i],
                    _token0Outs[i],
                    _token1Outs[i],
                    toAddress,
                    block.timestamp + 600
                )
            returns (uint256 amountA, uint256 amountB) {
                emit LiquidityRemoved(address(pair), amountA, amountB);
            } catch {
                if (_revertOnFailure) {
                    revert("failed to remove liquidity");
                } else {
                    emit LiquidityRemovalFailed(address(pair));
                }
            }
        }
    }

    /// @notice Swap amount in vs amount out
    /// @param _amountIns Array of amount ins
    /// @param _amountOuts Array of amount outs
    /// @param _paths path to follow for swapping
    /// @param _to address the tokens need to be transferred to.
    /// @param _revertOnFailure If false, the tx will not revert on swap failures
    function swapTokens(
        uint256[] calldata _amountIns,
        uint256[] calldata _amountOuts,
        address[][] calldata _paths,
        address _to,
        bool _revertOnFailure
    ) external onlyOwner {
        address toAddress = _to == address(0) ? address(this) : _to;

        for (uint256 i = 0; i < _amountIns.length; i++) {
            IERC20 token = IERC20(_paths[i][0]);
            token.approve(address(router), _amountIns[i]);
            try
                router.swapExactTokensForTokens(
                    _amountIns[i],
                    _amountOuts[i],
                    _paths[i],
                    toAddress,
                    block.timestamp + 600
                )
            {
                emit Swap(_amountIns[i], _amountOuts[i], _paths[i]);
            } catch {
                if (_revertOnFailure) {
                    revert("failed to swap tokens");
                } else {
                    emit SwapFailed(_amountIns[i], _amountOuts[i], _paths[i]);
                }
            }
        }
    }
}

