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

    address usdc;

    constructor(
        address _usdc
    ) public {
        usdc = _usdc;
    }

    function deposit(address _shipyardVault, string memory _depositToken, uint256 _amount) external nonReentrant {

        IShipyardVault shipyardVault = IShipyardVault(_shipyardVault);
        IStrategy strategy = shipyardVault.strategy();

        address depositTokenAddress = strategy.underlyingTokenAddress(_depositToken);

        if (depositTokenAddress != address(0)) {

            IERC20(depositTokenAddress).safeTransfer(msg.sender, _amount);

        } else if (stringEquals(_depositToken, 'USDC')) {

            string memory preferredToken = strategy.preferredUnderlyingToken();
            address preferredTokenAddress = strategy.underlyingTokenAddress(preferredToken);

            IERC20(usdc).safeTransfer(msg.sender, _amount);

            // Swap into preferredToken

            address[] memory paths;
            paths[0] = usdc;
            paths[1] = preferredTokenAddress;

            address unirouter = strategy.unirouter();

            approveTokenIfNeeded(usdc, unirouter);

            IUniswapRouterETH(unirouter).swapExactTokensForTokens(_amount, 0, paths, address(this), block.timestamp);

            _depositToken = preferredToken;
            _amount = IERC20(preferredTokenAddress).balanceOf(address(this));
            depositTokenAddress = preferredTokenAddress;

        } else {
            require(false, 'Invalid deposit token');
        }

        address pool = shipyardVault.strategy().pool();
        address poolToken = (address)(shipyardVault.strategy().want());

        if (depositTokenAddress != poolToken) {

            uint256 depositTokenIndex = strategy.underlyingTokenIndex(_depositToken);
            uint256 poolSize = shipyardVault.strategy().poolSize();

            approveTokenIfNeeded(depositTokenAddress, pool);

            if (poolSize == 2) {
                uint256[2] memory amounts;
                amounts[depositTokenIndex] = _amount;
                ICurveSwap(pool).add_liquidity{value : _amount}(amounts, 0);

            } else if (poolSize == 3) {
                uint256[3] memory amounts;
                amounts[depositTokenIndex] = _amount;
                ICurveSwap(pool).add_liquidity{value : _amount}(amounts, 0);

            } else if (poolSize == 4) {
                uint256[4] memory amounts;
                amounts[depositTokenIndex] = _amount;
                ICurveSwap(pool).add_liquidity{value : _amount}(amounts, 0);

            } else if (poolSize == 5) {
                uint256[5] memory amounts;
                amounts[depositTokenIndex] = _amount;
                ICurveSwap(pool).add_liquidity{value : _amount}(amounts, 0);
            }
        }

        uint256 amountPoolToken = IERC20(pool).balanceOf(address(this));

        // We now have the pool token so let’s call our vault contract

        approveTokenIfNeeded(poolToken, _shipyardVault);

        shipyardVault.deposit(amountPoolToken);

        // After we get back the shipyard LP token we can give to the sender

        uint256 amountShipyardToken = IERC20(_shipyardVault).balanceOf(address(this));

        IERC20((address)(shipyardVault)).safeTransfer(msg.sender, amountShipyardToken);
    }

    function withdraw(address _shipyardVault, string memory _withdrawToken, uint256 _amount) external nonReentrant {

        IShipyardVault shipyardVault = IShipyardVault(_shipyardVault);
        IStrategy strategy = shipyardVault.strategy();

        address withdrawTokenAddress = strategy.underlyingTokenAddress(_withdrawToken);

        require(withdrawTokenAddress != address(0) || stringEquals(_withdrawToken, 'USDC'), 'Invalid withdraw token');

        IERC20((address)(shipyardVault)).safeTransfer(msg.sender, _amount);

        shipyardVault.withdraw(_amount);

        address poolToken = (address)(shipyardVault.strategy().want());
        uint256 poolTokenBalance = IERC20(poolToken).balanceOf(address(this));

        if (withdrawTokenAddress == poolToken) {

            IERC20(poolToken).safeTransfer(msg.sender, poolTokenBalance);
            return;
        }

        address pool = shipyardVault.strategy().pool();

        approveTokenIfNeeded(poolToken, pool);

        if (withdrawTokenAddress != address(0)) {

            ICurveSwap(pool).remove_liquidity_one_coin(
                poolTokenBalance,
                int128(strategy.underlyingTokenIndex(_withdrawToken)),
                0
            );

            uint256 outputTokenBalance = IERC20(withdrawTokenAddress).balanceOf(address(this));

            IERC20(withdrawTokenAddress).safeTransfer(msg.sender, outputTokenBalance);
            return;
        }

        // Withdraw token must be USDC by this point

        string memory preferredToken = strategy.preferredUnderlyingToken();
        address preferredTokenAddress = strategy.underlyingTokenAddress(preferredToken);

        ICurveSwap(pool).remove_liquidity_one_coin(
            poolTokenBalance,
            int128(strategy.underlyingTokenIndex(preferredToken)),
            0
        );


        // Swap from preferredToken to USDC

        address[] memory paths;
        paths[0] = preferredTokenAddress;
        paths[1] = usdc;

        address unirouter = strategy.unirouter();

        approveTokenIfNeeded(preferredTokenAddress, unirouter);

        IUniswapRouterETH(unirouter).swapExactTokensForTokens(_amount, 0, paths, address(this), block.timestamp);

        uint256 usdcBalance = IERC20(usdc).balanceOf(address(this));

        IERC20(usdc).safeTransfer(msg.sender, usdcBalance);
    }

    //
    // internal

    function stringEquals(string memory _value1, string memory _value2) internal pure returns (bool) {
        return keccak256(bytes(_value1)) == keccak256(bytes(_value2));
    }

    function approveTokenIfNeeded(address _token, address _spender) internal {
        if (IERC20(_token).allowance(address(this), _spender) == 0) {
            IERC20(_token).safeApprove(_spender, uint256(~0));
        }
    }
}
