// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "./Ownable.sol";
import "./ERC20.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";

import "./IShipyardVault.sol";
import "./IUniswapRouterETH.sol";
import "./ICurveSwap.sol";

import "./GasThrottler.sol";

contract ShipyardOneClickCurve is Ownable, ReentrancyGuard, GasThrottler {

    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address _usdcAddress;

    constructor(
        address usdcAddress
    ) public {
        _usdcAddress = usdcAddress;
    }

    function deposit(address shipyardVaultAddress, address depositTokenAddress, uint256 amountInDepositToken) external nonReentrant {

        IShipyardVault shipyardVault = IShipyardVault(shipyardVaultAddress);
        IStrategy strategy = shipyardVault.strategy();

        address poolTokenAddress = (address)(strategy.want());

        bool isUnderlyingToken = strategy.underlyingToken(depositTokenAddress);

        require(isUnderlyingToken || depositTokenAddress == _usdcAddress || depositTokenAddress == poolTokenAddress, 'Invalid deposit token address');

        if (isUnderlyingToken || depositTokenAddress == poolTokenAddress) {

            IERC20(depositTokenAddress).safeTransferFrom(msg.sender, address(this), amountInDepositToken);

        } else if (depositTokenAddress == _usdcAddress) {

            address preferredTokenAddress = strategy.preferredUnderlyingToken();

            IERC20(_usdcAddress).safeTransferFrom(msg.sender, address(this), amountInDepositToken);

            // Swap into preferredToken

            address[] memory paths;
            paths[0] = _usdcAddress;
            paths[1] = preferredTokenAddress;

            address unirouterAddress = strategy.unirouter();

            _approveTokenIfNeeded(_usdcAddress, unirouterAddress);

            IUniswapRouterETH(unirouterAddress).swapExactTokensForTokens(amountInDepositToken, 0, paths, address(this), block.timestamp);

            amountInDepositToken = IERC20(preferredTokenAddress).balanceOf(address(this));
            depositTokenAddress = preferredTokenAddress;
        }

        address poolAddress = strategy.pool();

        if (depositTokenAddress != poolTokenAddress) {

            uint256 depositTokenIndex = strategy.underlyingTokenIndex(depositTokenAddress);
            uint256 poolSize = strategy.poolSize();

            _approveTokenIfNeeded(depositTokenAddress, poolAddress);

            if (poolSize == 2) {
                uint256[2] memory amounts;
                amounts[depositTokenIndex] = amountInDepositToken;
                ICurveSwap(poolAddress).add_liquidity(amounts, 0);

            } else if (poolSize == 3) {
                uint256[3] memory amounts;
                amounts[depositTokenIndex] = amountInDepositToken;
                ICurveSwap(poolAddress).add_liquidity(amounts, 0);

            } else if (poolSize == 4) {
                uint256[4] memory amounts;
                amounts[depositTokenIndex] = amountInDepositToken;
                ICurveSwap(poolAddress).add_liquidity(amounts, 0);

            } else if (poolSize == 5) {
                uint256[5] memory amounts;
                amounts[depositTokenIndex] = amountInDepositToken;
                ICurveSwap(poolAddress).add_liquidity(amounts, 0);
            }
        }

        uint256 amountPoolToken = IERC20(poolAddress).balanceOf(address(this));

        // We now have the pool token so let’s call our vault contract

        _approveTokenIfNeeded(poolTokenAddress, shipyardVaultAddress);

        shipyardVault.deposit(amountPoolToken);

        // After we get back the shipyard LP token we can give to the sender

        uint256 amountShipyardToken = IERC20(shipyardVaultAddress).balanceOf(address(this));

        IERC20(shipyardVaultAddress).safeTransfer(msg.sender, amountShipyardToken);
    }

    function withdraw(address shipyardVaultAddress, address requestedTokenAddress, uint256 withdrawAmountInShipToken) external nonReentrant {

        IShipyardVault shipyardVault = IShipyardVault(shipyardVaultAddress);
        IStrategy strategy = shipyardVault.strategy();

        bool isUnderlyingToken = strategy.underlyingToken(requestedTokenAddress);

        address poolTokenAddress = (address)(strategy.want());

        require(isUnderlyingToken || requestedTokenAddress == poolTokenAddress || requestedTokenAddress == _usdcAddress, 'Invalid withdraw token address');

        IERC20(shipyardVaultAddress).safeTransferFrom(msg.sender, address(this), withdrawAmountInShipToken);

        shipyardVault.withdraw(withdrawAmountInShipToken);

        uint256 poolTokenBalance = IERC20(poolTokenAddress).balanceOf(address(this));

        if (requestedTokenAddress == poolTokenAddress) {

            IERC20(poolTokenAddress).safeTransfer(msg.sender, poolTokenBalance);
            return;
        }

        address poolAddress = strategy.pool();

        _approveTokenIfNeeded(poolTokenAddress, poolAddress);

        if (isUnderlyingToken) {

            ICurveSwap(poolAddress).remove_liquidity_one_coin(
                poolTokenBalance,
                int128(strategy.underlyingTokenIndex(requestedTokenAddress)),
                0
            );

            uint256 outputTokenBalance = IERC20(requestedTokenAddress).balanceOf(address(this));

            IERC20(requestedTokenAddress).safeTransfer(msg.sender, outputTokenBalance);
            return;
        }

        // Withdraw token must be USDC by this point

        address preferredTokenAddress = strategy.preferredUnderlyingToken();

        ICurveSwap(poolAddress).remove_liquidity_one_coin(
            poolTokenBalance,
            int128(strategy.underlyingTokenIndex(preferredTokenAddress)),
            0
        );

        // Swap from preferredToken to USDC

        address[] memory paths;
        paths[0] = preferredTokenAddress;
        paths[1] = _usdcAddress;

        address unirouter = strategy.unirouter();

        _approveTokenIfNeeded(preferredTokenAddress, unirouter);

        IUniswapRouterETH(unirouter).swapExactTokensForTokens(withdrawAmountInShipToken, 0, paths, address(this), block.timestamp);

        uint256 usdcBalance = IERC20(_usdcAddress).balanceOf(address(this));

        IERC20(_usdcAddress).safeTransfer(msg.sender, usdcBalance);
    }

    function _approveTokenIfNeeded(address token, address spender) internal {
        if (IERC20(token).allowance(address(this), spender) == 0) {
            IERC20(token).safeApprove(spender, uint256(~0));
        }
    }
}
