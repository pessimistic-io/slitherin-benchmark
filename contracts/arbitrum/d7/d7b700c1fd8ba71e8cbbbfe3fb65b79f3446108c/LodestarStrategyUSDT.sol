// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

/**
 * @title Lodestart USDC strategy
 */

import {SafeERC20} from "./SafeERC20.sol";
import "./ICamelotRouter.sol";
import "./ICERC20.sol";
import "./IComptroller.sol";
import {IERC20, InitializableAbstractStrategy} from "./InitializableAbstractStrategy.sol";
import {IPool} from "./IPool.sol";
import {IWombatRouter} from "./IWombatRouter.sol";
import "./console.sol";

contract LodestarStrategyUSDT is InitializableAbstractStrategy {
    using SafeERC20 for IERC20;
    // USDT 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9

    event SkippedWithdrawal(address asset, uint256 amount);

    // Wombat pool 0xc6bc781E20f9323012F6e422bdf552Ff06bA6CD1
    address public pool;
    // Wombat router 0xc4B2F992496376C6127e73F1211450322E580668
    address public wombatRouter;

    address[] public rewardToBaseToken;
    address[] public fromBaseToUnderlying;
    address[] public fromUnderlyingToBase;

    function initialize(
        address _primaryStableAddress, // USDC
        address _platformAddress, // 0x0
        address _vaultAddress, //VoultCore
        address _router, //0xc873fecbd354f5a56e00e710b90ef4201db2448d Camellot
        address[] calldata _rewardTokenAddresses, // LODE
        address[] calldata _assets, // USDT
        address[] calldata _pTokens, // lUSDT
        address _pool, // Wombat 0xc6bc781E20f9323012F6e422bdf552Ff06bA6CD1
        address _wombatRouter // 0xc4B2F992496376C6127e73F1211450322E580668
    ) external initializer {
        require(
            _primaryStableAddress != address(0),
            "Zero address not allowed"
        );
        require(_pTokens.length > 0, "pToken addresses should not be empty");
//        require(_platformAddress != address(0), "Zero address not allowed");
        require(_router != address(0), "Zero address not allowed");
        require(_assets.length > 0, "assets addresses should not be empty");
        require(
            _rewardTokenAddresses.length > 0,
            "reward token addresses should not be empty"
        );
        pool = _pool;
        wombatRouter = _wombatRouter;
        rewardToBaseToken = [
            0xF19547f9ED24aA66b03c3a552D181Ae334FBb8DB,
            0x82aF49447D8a07e3bd95BD0d56f35241523fBab1,
            0x1A5B0aaF478bf1FDA7b934c76E7692D722982a6D,
            0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8
        ];

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
     * @dev Collect accumulated COMP and send to Harvester.
     */
    function collectRewardTokens()
        external
        override
        onlyHarvester
        nonReentrant
    {
        // Claim COMP from Comptroller
        ICERC20 cToken = _getCTokenFor(assetsMapped[0]);
        IComptroller comptroller = IComptroller(cToken.comptroller());

        // Claim COMP from Comptroller. Only collect for supply, saves gas
        comptroller.claimComp(address(this));

        // Swap to base and send to harvester
        IERC20 rewardToken = IERC20(rewardTokenAddresses[0]);
        uint256 balance = rewardToken.balanceOf(address(this));
        emit RewardTokenCollected(
            harvesterAddress,
            rewardTokenAddresses[0],
            balance
        );

        _swapReward(
            address(rewardToken),
            primaryStableAddress,
            rewardToBaseToken
        );

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
        _swapAsset(_asset, assetsMapped[0]);
        uint256 amountAfterSwap = IERC20(assetsMapped[0]).balanceOf(
            address(this)
        );
        _deposit(assetsMapped[0], amountAfterSwap);
    }

    /**
     * @dev Deposit asset into Compound
     * @param _asset Address of asset to deposit
     * @param _amount Amount of asset to deposit
     */
    function _deposit(address _asset, uint256 _amount) internal {
        require(_amount > 0, "Must deposit something");
        ICERC20 cToken = _getCTokenFor(_asset);
        //return 0 if the mint is allowed, otherwise a semi-opaque error code
        require(cToken.mint(_amount) == 0, "cToken mint failed");
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
     * @dev Withdraw asset from Compound
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
        // If redeeming 0 cTokens, just skip, else COMP will revert
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
        emit Withdrawal(_asset, address(cToken), _amount);
        require(
            cToken.redeemUnderlying(usdtAmountToWithdraw) == 0,
            "Redeem failed"
        );
        uint256 usdcSwappedOut = _swapAsset(
            assetsMapped[0],
            primaryStableAddress
        );
        require(
            IERC20(_asset).balanceOf(address(this)) > 0,
            "Insufficient primary stable to withdraw."
        );
        IERC20(_asset).safeTransfer(
            _recipient,
            IERC20(_asset).balanceOf(address(this))
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
                cToken.redeem(cToken.balanceOf(address(this))) == 0,
                "Redeem failed"
            );
            //USDT to USDC
            _swapAsset(assetsMapped[0], primaryStableAddress);
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
     * @return returnBalance    Total value of the asset in the platform
     */
    function _checkBalance(
        ICERC20 _cToken
    ) internal view returns (uint256 returnBalance) {
        require(pool != address(0), "Pool address should not be empty");
        uint256 cTokenBalance = _cToken.balanceOf(address(this));
        uint256 exchangeRate = _cToken.exchangeRateStored();
        // e.g. 50e8*205316390724364402565641705 / 1e18 = 1.0265..e18
        uint256 balance = (cTokenBalance * exchangeRate) / 1e18;
        if (balance > 0) {
            (returnBalance, ) = IPool(pool).quotePotentialSwap(
                assetsMapped[0],
                primaryStableAddress,
                int256(balance)
            );
        } else {
            returnBalance = 0;
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
        uint256 exchangeRate = _cToken.exchangeRateStored();
        // e.g. 1e18*1e18 / 205316390724364402565641705 = 50e8
        // e.g. 1e8*1e18 / 205316390724364402565641705 = 0.45 or 0
        amount = (_underlying * 1e18) / exchangeRate;
    }

    /********************************
               Swapping
   *********************************/
    /**
     * @dev Swapping one asset to another using the Swapper present inside Vault
     * @param tokenFrom address of token to swap from
     * @param tokenTo address of token to swap to
     */
    function _swapAsset(
        address tokenFrom,
        address tokenTo
    ) internal returns (uint256) {
        //        require(dex != address(0), "Empty Swapper Address");
        if (
            (tokenFrom != tokenTo) &&
            (IERC20(tokenFrom).balanceOf(address(this)) > 0)
        ) {
            uint amount = IERC20(tokenFrom).balanceOf(address(this));
            IERC20(tokenFrom).approve(
                0xc4B2F992496376C6127e73F1211450322E580668,
                amount
            );
            address[] memory tokenPath = new address[](2);
            tokenPath[0] = tokenFrom;
            tokenPath[1] = tokenTo;
            address[] memory poolPath = new address[](1);
            poolPath[0] = pool;
            //        (uint _amountOut, ) = IWombatRouter(swapRouter).getAmountOut(
            //          tokenPath,
            //          poolPath,
            //          int256(amount)
            //        );
            //        uint minAmount = _amountOut - (_amountOut * 5) / 1000;
            // TODO create wombat router variable 0xc4B2F992496376C6127e73F1211450322E580668
            uint amountOut = IWombatRouter(
                0xc4B2F992496376C6127e73F1211450322E580668
            ).swapExactTokensForTokens(
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

    /**
     * @dev Swapping reward token to primary stable
     * @param tokenFrom address of token to swap from
     * @param tokenTo address of token to swap to
     */
    function _swapReward(
        address tokenFrom,
        address tokenTo,
        address[] memory path
    ) internal {
        require(router != address(0), "Empty Swapper Address");
        if (
            (tokenFrom != tokenTo) &&
            (IERC20(tokenFrom).balanceOf(address(this)) > 0)
        ) {
            uint amount = IERC20(tokenFrom).balanceOf(address(this));
            if (IERC20(tokenFrom).allowance(address(this), router) == 0) {
                IERC20(tokenFrom).approve(router, MAX_UINT);
            }
            ICamelotRouter(router)
                .swapExactTokensForTokensSupportingFeeOnTransferTokens(
                    amount,
                    0,
                    path,
                    address(this),
                    address(0),
                    block.timestamp
                );
        }
    }

    function setPool(address _pool) external onlyOwner {
        require(_pool != address(0), "Pool address should not be empty");
        pool = _pool;
    }

    function setWombatRouter(address _wombatRouter) external {
        require(
            _wombatRouter != address(0),
            "Wombat router address should not be empty"
        );
        wombatRouter = _wombatRouter;
    }
}

