// SPDX-License-Identifier: MIT
// solhint-disable avoid-low-level-calls
pragma solidity >=0.8.0;

import "./IERC20.sol";
import "./BoringERC20.sol";
import "./IBentoBoxV1.sol";
import "./ILevSwapperV2.sol";
import "./IERC4626.sol";
import "./IGmxGlpRewardRouter.sol";

contract GLPVaultLevSwapper is ILevSwapperV2 {
    using BoringERC20 for IERC20;

    error ErrSwapFailed();

    IBentoBoxV1 public immutable bentoBox;
    IERC20 public immutable mim;
    IERC20 public immutable glpVault;
    IERC20 public immutable usdc;
    IGmxGlpRewardRouter public immutable glpRewardRouter;
    IERC20 public immutable sGLP;
    address public immutable zeroXExchangeProxy;

    constructor(
        IBentoBoxV1 _bentoBox,
        IERC20 _glpVault,
        IERC20 _mim,
        IERC20 _sGLP,
        IERC20 _usdc,
        address glpManager,
        IGmxGlpRewardRouter _glpRewardRouter,
        address _zeroXExchangeProxy
    ) {
        bentoBox = _bentoBox;
        glpVault = _glpVault;
        mim = _mim;
        usdc = _usdc;
        zeroXExchangeProxy = _zeroXExchangeProxy;
        glpRewardRouter = _glpRewardRouter;
        sGLP = _sGLP;
        usdc.approve(glpManager, type(uint256).max);
        _sGLP.approve(address(glpVault), type(uint256).max);
        _glpVault.approve(address(_bentoBox), type(uint256).max);
        _mim.approve(_zeroXExchangeProxy, type(uint256).max);
    }

    /// @inheritdoc ILevSwapperV2
    function swap(
        address recipient,
        uint256 shareToMin,
        uint256 shareFrom,
        bytes calldata swapData
    ) external override returns (uint256 extraShare, uint256 shareReturned) {
        bentoBox.withdraw(mim, address(this), address(this), 0, shareFrom);

        // MIM -> USDC
        (bool success, ) = zeroXExchangeProxy.call(swapData);
        if (!success) {
            revert ErrSwapFailed();
        }

        uint256 _amount = usdc.balanceOf(address(this));

        _amount = glpRewardRouter.mintAndStakeGlp(address(usdc), _amount, 0, 0);

        IERC4626(address(glpVault)).deposit(_amount, address(this));

        _amount = glpVault.balanceOf(address(this));

        (, shareReturned) = bentoBox.deposit(glpVault, address(this), recipient, _amount, 0);
        extraShare = shareReturned - shareToMin;
    }
}

