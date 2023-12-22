// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;
pragma abicoder v2;

/**
 * @title Whitehole USDC strategy
 */

import {SafeERC20} from "./SafeERC20.sol";
import "./ICamelotRouter.sol";
import "./ICERC20.sol";
import {ICore} from "./ICore.sol";
import {IGToken} from "./IGToken.sol";
import {IERC20, InitializableAbstractStrategy} from "./InitializableAbstractStrategy.sol";
import {IPool} from "./IPool.sol";
import {IWombatRouter} from "./IWombatRouter.sol";
import "./ISwapRouter.sol";
import "./TransferHelper.sol";
import "./console.sol";

contract WhiteHoleUSDTStrategy is InitializableAbstractStrategy {
    using SafeERC20 for IERC20;

    event SkippedWithdrawal(address asset, uint256 amount);

    uint24 public constant poolFee = 3000;

    address public wombatRouter;
    address  public pool;

    function initialize(
        address _primaryStableAddress, // USDC
        address _platformAddress, // WhiteHole Core 0x1D019f2d14bdB81bAb7BA4eC7e20868e669C32b1
        address _vaultAddress, //VoultCore
        address _router, //0xE592427A0AEce92De3Edee1F18E0157C05861564 UniswapV3
        address[] calldata _rewardTokenAddresses, // GRV token 0x10031e7CFf689de64f1A5a8ECF4fBBc7Aa068927
        address[] calldata _assets, // USDT
        address[] calldata _pTokens, // gUSDT 0xAaC9cB4b34B002279955Df9CF2e637Bc66128d61
        address _wombatRouter, // 0xc4B2F992496376C6127e73F1211450322E580668
        address _pool // Wombat pool 0xc6bc781E20f9323012F6e422bdf552Ff06bA6CD1
    ) external initializer {
        require(
            _primaryStableAddress != address(0),
            "Zero address not allowed"
        );
        require(_pTokens.length > 0, "pToken addresses should not be empty");
        require(_platformAddress != address(0), "Zero address not allowed");
        require(_router != address(0), "Zero address not allowed");
        require(_assets.length > 0, "assets addresses should not be empty");
        require(
            _rewardTokenAddresses.length > 0,
            "reward token addresses should not be empty"
        );
        require(
            _wombatRouter != address(0),
            "wombat router address should not be empty"
        );

        wombatRouter = _wombatRouter;
        pool = _pool;

        InitializableAbstractStrategy._initialize(
            _primaryStableAddress,
            _platformAddress,
            _vaultAddress,
            _router,
            _rewardTokenAddresses,
            _assets,
            _pTokens
        );
    }

    /**
     * @dev Collect accumulated GRV and send to Harvester.
     */
    function collectRewardTokens()
        external
        override
        onlyHarvester
        nonReentrant
    {
        ICERC20 cToken = _getCTokenFor(assetsMapped[0]);
        ICore(platformAddress).claimGRV();

        // Swap to base and send to harvester
        IERC20 rewardToken = IERC20(rewardTokenAddresses[0]);
        uint256 balance = rewardToken.balanceOf(address(this));
        emit RewardTokenCollected(
            harvesterAddress,
            rewardTokenAddresses[0],
            balance
        );
        _swapReward(address(rewardToken), primaryStableAddress);

        IERC20(primaryStableAddress).safeTransfer(
            harvesterAddress,
            IERC20(primaryStableAddress).balanceOf(address(this))
        );
    }

    /**
     * @dev Deposit asset into Compound
     * @param _asset Address of asset to deposit
     * @param _amount Amount of asset to deposit
     */
    function deposit(
        address _asset,
        uint256 _amount
    ) external override onlyVault nonReentrant {
        _deposit(_asset, _amount);
    }

    /**
     * @dev Deposit asset into Compound
     * @param _asset Address of asset to deposit
     * @param _amount Amount of asset to deposit
     */
    function _deposit(address _asset, uint256 _amount) internal {
        require(_amount > 0, "Must deposit something");
        uint256 amountUsdt = _swapAsset(_asset, assetsMapped[0]);
        require(amountUsdt > 0, "the swap was not successful");
        ICERC20 cToken = _getCTokenFor(assetsMapped[0]);
        uint256 bal = ICore(platformAddress).supply(
            address(cToken),
            amountUsdt
        );
        emit Deposit(_asset, address(cToken), _amount);
    }

    /**
     * @dev Deposit the entire balance of any supported asset into Compound
     */
    function depositAll() external override onlyVault nonReentrant {
        for (uint256 i = 0; i < assetsMapped.length; i++) {
            uint256 balance = IERC20(assetsMapped[i]).balanceOf(address(this));
            if (balance > 0) {
                _deposit(assetsMapped[i], balance);
            }
        }
    }

    /**
     * @dev Withdraw asset from WhiteHole
     * @param _recipient Address to receive withdrawn asset
     * @param _asset Address of asset to withdraw
     * @param _amount Amount of asset to withdraw
     */
    function withdraw(
        address _recipient,
        address _asset,
        uint256 _amount
    ) external override onlyVault nonReentrant {
        require(_amount > 0, "Must withdraw something");
        require(_recipient != address(0), "Must specify recipient");
        ICERC20 cToken = _getCTokenFor(assetsMapped[0]);
        uint256 cTokensToRedeem = _convertUnderlyingToCToken(cToken, _amount);
        if (cTokensToRedeem == 0) {
            emit SkippedWithdrawal(_asset, _amount);
            return;
        }
        address[] memory tokenPath = new address[](2);
        tokenPath[0] = assetsMapped[0];
        tokenPath[1] = _asset;
        address[] memory poolPath = new address[](1);
        poolPath[0] = pool;
        (uint256 usdtAmountToWithdraw, ) = IWombatRouter(wombatRouter)
            .getAmountIn(tokenPath, poolPath, _amount);
        ICore(platformAddress).redeemUnderlying(address(cToken), usdtAmountToWithdraw); 
        emit Withdrawal(_asset, address(cToken), _amount);
        uint256 amountUsdc = _swapAsset(assetsMapped[0], _asset);
        require(amountUsdc > 0, "the swap was not successful");
        IERC20(_asset).safeTransfer(
            _recipient,
            IERC20(primaryStableAddress).balanceOf(address(this))
        );
    }

    /**
     * @dev Remove all assets from platform and send them to Vault contract.
     */
    function withdrawAll() external override onlyVaultOrOwner nonReentrant {
        // Redeem entire balance of cToken
        ICERC20 cToken = _getCTokenFor(assetsMapped[0]);
        if (cToken.balanceOf(address(this)) > 0) {
            require(
                ICore(platformAddress).redeemToken(
                    address(cToken),
                    cToken.balanceOf(address(this))
                ) > 0,
                "Redeem failed"
            );
            uint256 amountUsdc = _swapAsset(
                assetsMapped[0],
                primaryStableAddress
            );
            require(amountUsdc > 0, "the swap was not successful");
            // Transfer entire balance of USDC to Vault
            IERC20 asset = IERC20(primaryStableAddress);
            asset.safeTransfer(vaultAddress, asset.balanceOf(address(this)));
        }
    }

    /**
     * @dev Get the total asset value held in the platform
     *      This includes any interest that was generated since depositing
     *      Compound exchange rate between the cToken and asset gradually increases,
     *      causing the cToken to be worth more corresponding asset.
     * @return balance    Total value of the asset in the platform
     */
    function checkBalance() external view override returns (uint256 balance) {
        // Balance is always with token cToken decimals
        ICERC20 cToken = _getCTokenFor(assetsMapped[0]);
        balance = _checkBalance(cToken);
    }

    /**
     * @dev Get the total asset value held in the platform
     *      underlying = (cTokenAmt * exchangeRate) / 1e18
     * @param _cToken     cToken for which to check balance
     * @return balance    Total value of the asset in the platform
     */
    function _checkBalance(
        ICERC20 _cToken
    ) internal view returns (uint256 balance) {
        uint256 balanceUsdt = IGToken(address(_cToken)).underlyingBalanceOf(
            address(this)
        );
        if (balanceUsdt > 0) {
            uint withdrewAmount = 0;
            (balance, withdrewAmount) = IPool(pool)
                .quotePotentialSwap(
                    assetsMapped[0],
                    primaryStableAddress,
                    int256(balanceUsdt)
                );
        } else {
            balance = 0;
        }
    }

    /**
     * @dev Retuns bool indicating whether asset is supported by strategy
     * @param _asset Address of the asset
     */
    function supportsAsset(
        address _asset
    ) external view override returns (bool) {
        return assetToPToken[_asset] != address(0);
    }

    /**
     * @dev Approve the spending of all assets by their corresponding cToken,
     *      if for some reason is it necessary.
     */
    function safeApproveAllTokens() external override {
        uint256 assetCount = assetsMapped.length;
        for (uint256 i = 0; i < assetCount; i++) {
            address asset = assetsMapped[i];
            address cToken = assetToPToken[asset];
            // Safe approval
            IERC20(asset).safeApprove(cToken, 0);
            IERC20(asset).safeApprove(cToken, type(uint256).max);
        }
    }

    /**
     * @dev Internal method to respond to the addition of new asset / cTokens
     *      We need to approve the cToken and give it permission to spend the asset
     * @param _asset Address of the asset to approve
     * @param _cToken The cToken for the approval
     */
    function _abstractSetPToken(
        address _asset,
        address _cToken
    ) internal override {
        // Safe approval
        IERC20(_asset).safeApprove(_cToken, 0);
        IERC20(_asset).safeApprove(_cToken, type(uint256).max);
    }

    /**
     * @dev Get the cToken wrapped in the ICERC20 interface for this asset.
     *      Fails if the pToken doesn't exist in our mappings.
     * @param _asset Address of the asset
     * @return Corresponding cToken to this asset
     */
    function _getCTokenFor(address _asset) internal view returns (ICERC20) {
        address cToken = assetToPToken[_asset];
        require(cToken != address(0), "cToken does not exist");
        return ICERC20(cToken);
    }

    /**
     * @dev Converts an underlying amount into cToken amount
     *      cTokenAmt = (underlying * 1e18) / exchangeRate
     * @param _cToken     cToken for which to change
     * @param _underlying Amount of underlying to convert
     * @return amount     Equivalent amount of cTokens
     */
    function _convertUnderlyingToCToken(
        ICERC20 _cToken,
        uint256 _underlying
    ) internal view returns (uint256 amount) {
        uint256 exchangeRate = IGToken(address(_cToken)).exchangeRate();
        // e.g. 1e18*1e18 / 205316390724364402565641705 = 50e8
        // e.g. 1e8*1e18 / 205316390724364402565641705 = 0.45 or 0
        amount = (_underlying * 1e18) / exchangeRate;
    }

    function _swapAsset(
        address tokenFrom,
        address tokenTo
    ) internal returns (uint256) {
        if (
            (tokenFrom != tokenTo) &&
            (IERC20(tokenFrom).balanceOf(address(this)) > 0)
        ) {
            uint amount = IERC20(tokenFrom).balanceOf(address(this));
            IERC20(tokenFrom).approve(wombatRouter, amount);
            address[] memory tokenPath = new address[](2);
            tokenPath[0] = tokenFrom;
            tokenPath[1] = tokenTo;
            address[] memory poolPath = new address[](1);
            poolPath[0] = pool;
            uint amountOut = IWombatRouter(wombatRouter)
                .swapExactTokensForTokens(
                    tokenPath,
                    poolPath,
                    amount,
                    0,
                    address(this),
                    block.timestamp
                );
            return amountOut;
        }
    }

    function _swapReward(address tokenIn, address tokenOut) internal {
        require(router != address(0), "Empty Swapper Address");
        if (
            (tokenIn != tokenOut) &&
            (IERC20(tokenIn).balanceOf(address(this)) > 0)
        ) {
            if (tokenIn != primaryStableAddress) {
                uint amount = IERC20(tokenIn).balanceOf(address(this));

                if (IERC20(tokenIn).allowance(address(this), router) == 0) {
                    TransferHelper.safeApprove(tokenIn, router, MAX_UINT);
                }

                ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
                    .ExactInputSingleParams({
                        tokenIn: tokenIn,
                        tokenOut: tokenOut,
                        fee: poolFee,
                        recipient: address(this),
                        deadline: block.timestamp,
                        amountIn: amount,
                        amountOutMinimum: 0,
                        sqrtPriceLimitX96: 0
                    });
                uint256 amountOut = ISwapRouter(router).exactInputSingle(
                    params
                );
            }
        }
    }
}

