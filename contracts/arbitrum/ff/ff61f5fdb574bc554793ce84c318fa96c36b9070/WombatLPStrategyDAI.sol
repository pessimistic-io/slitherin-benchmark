// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

/**
 * @title QuickSwap Strategy
 * @notice Investment strategy for investing stablecoins via QuickSwap Strategy
 */
import {SafeERC20} from "./SafeERC20.sol";
import {IERC20Metadata} from "./IERC20Metadata.sol";
import {IERC20, InitializableAbstractStrategy} from "./InitializableAbstractStrategy.sol";
import {IPool} from "./IPool.sol";
import {IDripper} from "./IDripper.sol";
import {IWombatRouter} from "./IWombatRouter.sol";
import {IMasterWombatV3} from "./IMasterWombatV3.sol";
import {IAsset} from "./IAsset.sol";
import "./ICamelotRouter.sol";
import "./console.sol";

contract WombatLPStrategyDAI is InitializableAbstractStrategy {
    using SafeERC20 for IERC20;

    //  Asset=>array of pool paths
    mapping(address => address[]) public assetsPoolPaths;
    // Wombat pool for deposit to
    address public pool;
    address[] public rewardToBaseToken;
    address[] public fromBaseToUnderlying;
    address[] public fromUnderlyingToBase;

    // Wombat DAI Asset(LP-DAI) 0x0Fa7b744F18D8E8c3D61B64b110F25CC27E73055
    // Wom token 0x7B5EB3940021Ec0e8e463D5dBB4B7B09a89DDF96;
    // Wombat router 0x9da4edBed6068666ea8EF6505C909e1ff8eA5725 0xc4B2F992496376C6127e73F1211450322E580668
    // Wombat pool 0xc6bc781E20f9323012F6e422bdf552Ff06bA6CD1

    /**
     * Initializer for setting up strategy internal state. This overrides the
     * InitializableAbstractStrategy initializer as QuickSwap strategies don't fit
     * well within that abstraction.
     */
    function initialize(
        address _primaryStableAddress, // USDC
        address _platformAddress, // master Wombat contract 0x62a83c6791a3d7950d823bb71a38e47252b6b6f4
        address _vaultAddress, //VaultCore
        address _router, // 0xc873fecbd354f5a56e00e710b90ef4201db2448d Camellot
        address[] calldata _rewardTokenAddresses, // Wom
        address[] calldata _assets, // DAI
        address[] calldata _pTokens, //  0x0Fa7b744F18D8E8c3D61B64b110F25CC27E73055
        address[] memory _assetsPoolPaths, // 0xc6bc781E20f9323012F6e422bdf552Ff06bA6CD1
        address _pool // 0xc6bc781E20f9323012F6e422bdf552Ff06bA6CD1
    ) external initializer {
        require(
            _primaryStableAddress != address(0),
            "Zero address not allowed"
        );
        require(_pool != address(0), "Zero address not allowed");
        require(_pTokens.length > 0, "pToken addresses should not be empty");
        require(_platformAddress != address(0), "Zero address not allowed");
        require(_router != address(0), "Zero address not allowed");
        require(_assets.length > 0, "assets addresses should not be empty");
        require(
            _rewardTokenAddresses.length > 0,
            "reward token addresses should not be empty"
        );
        require(
            _assetsPoolPaths.length > 0,
            "assets pool paths addresses should not be empty"
        );
        _setAssetsPoolPaths(_assets[0], _assetsPoolPaths);
        _setAssetsPoolPaths(_assets[1], _assetsPoolPaths);
        pool = _pool;

        rewardToBaseToken = [
        0x7B5EB3940021Ec0e8e463D5dBB4B7B09a89DDF96,
        0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9,
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
     * @dev Deposit asset into Wombat
     * @param _asset Address of asset to deposit
     * @param _amount Amount of asset to deposit
     */
    function deposit(
        address _asset,
        uint256 _amount
    ) external override onlyVault nonReentrant {
        _deposit(_asset, _amount);
    }

    function _deposit(address _asset, uint256 _amount) internal {
        require(assetToPToken[_asset] != address(0), "asset does not exist.");
        require(_amount > 0, "You can't deposit 0.");
        _swapAsset(_asset, assetsMapped[0]);
        uint256 amountOut = IERC20(assetsMapped[0]).balanceOf(address(this));
        IERC20(assetsMapped[0]).approve(pool, amountOut);
        IPool(pool).deposit(
            assetsMapped[0],
            amountOut,
            0,
            address(this),
            block.timestamp,
            true
        );
        emit Deposit(_asset, assetToPToken[_asset], _amount);
    }

    /**
     * @dev Withdraw asset from strategy to _recipient(maybe vault)
     * @param _recipient         Address to which the asset should be sent(harvester)
     * @param _asset             Address of the asset
     * @param _amount            Units of asset to withdraw
     */
    function withdraw(
        address _recipient,
        address _asset,
        uint256 _amount
    ) public override onlyVaultOrOwner nonReentrant {
        require(
            _recipient != address(0),
            "Recipient address should not be empty."
        );
        require(_asset != address(0), "Asset address should not be empty.");
        require(_amount > 0, "Amount should be more than 0.");
        uint256 pid = getAssetPid(_getPToken(assetsMapped[0]));
        // return amount of lp tokens
        (uint256 amountLpTokensAtStrategy, , , ) = IMasterWombatV3(
            platformAddress
        ).userInfo(pid, address(this));
        require(
            amountLpTokensAtStrategy > 0,
            "There are no lp tokens in the strategy."
        );
        // get address of lpDAI
        address pToken = _getPToken(assetsMapped[0]);

        uint exchangeRate = IPool(pool).exchangeRate(assetsMapped[0]);
        uint underlyingAmount = 0;

        (underlyingAmount, ) = IPool(pool).quoteAmountIn(
            assetsMapped[0],
            _asset,
            int256(_amount)
        );
        //TODO should be other calculation
        uint amountToWithdraw = (underlyingAmount * 1e18) / exchangeRate;
        // you can't withdraw more lp tokens that have in the strategy
        require(
            amountLpTokensAtStrategy >= amountToWithdraw,
            "You can't withdraw more lp tokens that have in the strategy."
        );
        // send lp tokens to this contract
        IMasterWombatV3(platformAddress).withdraw(pid, amountToWithdraw);
        // send money to this contract and burn lp tokens
        IERC20(pToken).approve(pool, amountToWithdraw);
        uint256 amount = IPool(pool).withdraw(
            assetsMapped[0],
            amountToWithdraw,
            0,
            address(this),
            block.timestamp
        );

        if (amount > 0) {
            //DAI to USDC
            _swapAsset(assetsMapped[0], _asset);
            uint256 amountOut = IERC20(primaryStableAddress).balanceOf(
                address(this)
            );
            IERC20(_asset).safeTransfer(_recipient, amountOut);
            emit RewardTokenCollected(
                _recipient,
                rewardTokenAddresses[0],
                amountOut
            );
        } else {
            revert("Incuficient withdrawal");
        }
    }

    /**
     * @dev Withdraw all assets from strategy to vault
     */
    function withdrawAll() external override onlyVaultOrOwner nonReentrant {
        address pToken = _getPToken(assetsMapped[0]);
        uint256 pid = getAssetPid(pToken);
        (uint256 lpBalance, , , ) = IMasterWombatV3(platformAddress).userInfo(
            pid,
            address(this)
        );
        // send lp tokens to this contract
        IMasterWombatV3(platformAddress).withdraw(pid, lpBalance);
        // send money to this contract and burn lp tokens
        IERC20(pToken).approve(pool, IERC20(pToken).balanceOf(address(this)));
        uint256 amount = IPool(pool).withdraw(
            assetsMapped[0],
            lpBalance,
            0,
            address(this),
            block.timestamp
        );
        //TODO revert is not needed
        if (amount > 0) {
            //DAI to USDC
            _swapAsset(assetsMapped[0], primaryStableAddress);
            uint256 amountOut = IERC20(primaryStableAddress).balanceOf(
                address(this)
            );
            IERC20(primaryStableAddress).safeTransfer(msg.sender, amountOut);
        } else {
            revert("Incuficient withdrawal");
        }
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
     * @dev Collect accumulated Wom and send to Harvester.
     */
    function collectRewardTokens()
    external
    override
    onlyHarvester
    nonReentrant
    {
        uint256[] memory _pids = new uint256[](1);
        _pids[0] = getAssetPid(_getPToken(assetsMapped[0]));
        // get all assets pid
        IMasterWombatV3(platformAddress).multiClaim(_pids);
        _swapReward(
            rewardTokenAddresses[0],
            primaryStableAddress,
            rewardToBaseToken
        );
        IERC20(primaryStableAddress).safeTransfer(
            harvesterAddress,
            IERC20(primaryStableAddress).balanceOf(address(this))
        );
        emit RewardTokenCollected(
            harvesterAddress,
            rewardTokenAddresses[0],
            IERC20(primaryStableAddress).balanceOf(address(this))
        );
    }

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

    // @notice View function to see pending WOMs on frontend.(check this!)
    function checkWomBalance() external view returns (uint256) {
        uint256 pid = getAssetPid(_getPToken(assetsMapped[0]));
        (uint256 pendingRewards, , , ) = IMasterWombatV3(platformAddress)
        .pendingTokens(pid, address(this));
        return pendingRewards;
    }

    /// @notice View function to see USDС amount in strategy on frontend.
    function checkBalance() external view override returns (uint256 balance) {
        uint256 pid = getAssetPid(_getPToken(assetsMapped[0]));
        (uint lpBalance, , , ) = IMasterWombatV3(platformAddress).userInfo(
            pid,
            address(this)
        );
        if (lpBalance > 0) {
            address pToken = _getPToken(assetsMapped[0]);
            uint withdrewAmount = 0;
            // TODO not right varible returns->fixed
            (balance, withdrewAmount) = IPool(pool)
            .quotePotentialWithdrawFromOtherAsset(
                assetsMapped[0],
                primaryStableAddress,
                lpBalance
            );
        } else {
            balance = 0;
        }
    }

    /**
     * @dev Approve the spending of all assets by their corresponding cToken,
     *      if for some reason is it necessary.
     */
    function safeApproveAllTokens() external override {
        uint256 assetCount = assetsMapped.length;
        for (uint256 i; i < assetCount; ++i) {
            address asset = assetsMapped[i];
            address cToken = assetToPToken[asset];
            // Safe approval
            IERC20(asset).safeApprove(cToken, 0);
            IERC20(asset).safeApprove(cToken, type(uint256).max);
        }
    }

    /**
     * @dev Retuns bool indicating whether asset is supported by strategy
     * @param _asset Address of the asset
     */
    function supportsAsset(address _asset) public view override returns (bool) {
        return assetToPToken[_asset] != address(0);
    }

    function getAssetPid(address _asset) public view returns (uint256 pid) {
        pid = IMasterWombatV3(platformAddress).getAssetPid(_asset);
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
     * @dev Set the platform address. (Master wombat contract).
     * @param _platform Address of the router
     */
    function setPlatformAddress(address _platform) external onlyOwner {
        require(
            _platform != address(0),
            "Platform address should not be empty."
        );
        platformAddress = _platform;
    }

    /**
     * @dev Set the main pool address. (Wombat pool for deposit to)
     * @param _pool Address of the router
     */
    function setMainPool(address _pool) external onlyOwner {
        require(_pool != address(0), "Main pool address should not be empty.");
        pool = _pool;
    }

    function setAssetsPoolPaths(
        address _asset,
        address[] memory _assetsPoolPaths
    ) external onlyOwner {
        _setAssetsPoolPaths(_asset, _assetsPoolPaths);
    }

    /**
     * @dev Set assets pool paths
     * @param _asset Address of the asset
     * @param _assetsPoolPaths array of pool paths
     */
    function _setAssetsPoolPaths(
        address _asset,
        address[] memory _assetsPoolPaths
    ) internal {
        require(
            _asset != address(0),
            "Asset pool address should not be empty."
        );
        require(
            _assetsPoolPaths.length > 0,
            "There must be at least 1 address."
        );
        assetsPoolPaths[_asset] = _assetsPoolPaths;
    }

    function getAssetPoolPaths(
        address _asset
    ) public view returns (address[] memory) {
        return assetsPoolPaths[_asset];
    }
}

