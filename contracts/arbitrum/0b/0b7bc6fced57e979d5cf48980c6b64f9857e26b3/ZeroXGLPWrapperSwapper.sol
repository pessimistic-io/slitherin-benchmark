// SPDX-License-Identifier: MIT
// solhint-disable avoid-low-level-calls
pragma solidity >=0.8.0;

import "./IERC20.sol";
import "./BoringERC20.sol";
import "./IBentoBoxV1.sol";
import "./ISwapperV2.sol";
import "./IGmxRewardRouterV2.sol";
import "./ITokenWrapper.sol";

/// @notice LP liquidation/deleverage swapper for tokens using Matcha/0x aggregator
contract ZeroXGLPWrapperSwapper is ISwapperV2 {
    using BoringERC20 for IERC20;

    error ErrSwapFailed();

    IBentoBoxV1 public immutable bentoBox;
    IERC20 public immutable token;
    IERC20 public immutable mim;
    IERC20 public immutable usdc;
    IERC20 public immutable sGLP;
    IGmxRewardRouterV2 public immutable rewardRouter;
    address public immutable zeroXExchangeProxy;

    constructor(
        IBentoBoxV1 _bentoBox,
        IERC20 _token,
        IERC20 _mim,
        IERC20 _sGLP,
        IERC20 _usdc,
        IGmxRewardRouterV2 _rewardRouter,
        address _zeroXExchangeProxy
    ) {
        bentoBox = _bentoBox;
        token = _token;
        mim = _mim;
        usdc = _usdc;
        sGLP = _sGLP;
        rewardRouter = _rewardRouter;
        zeroXExchangeProxy = _zeroXExchangeProxy;
        _token.approve(_zeroXExchangeProxy, type(uint256).max);
        mim.approve(address(_bentoBox), type(uint256).max);
    }

    /// @inheritdoc ISwapperV2
    function swap(
        address,
        address,
        address recipient,
        uint256 shareToMin,
        uint256 shareFrom,
        bytes calldata swapData
    ) public override returns (uint256 extraShare, uint256 shareReturned) {
        (uint256 amount, )= bentoBox.withdraw(IERC20(address(token)), address(this), address(this), 0, shareFrom);
        ITokenWrapper(address(token)).unwrap(amount);

        rewardRouter.unstakeAndRedeemGlp(address(usdc), amount, 0, address(this));

        // token -> MIM
        (bool success, ) = zeroXExchangeProxy.call(swapData);
        if (!success) {
            revert ErrSwapFailed();
        }
        
        // we can expect dust from both gmx and 0x
        usdc.safeTransfer(recipient, usdc.balanceOf(address(this)));

        (, shareReturned) = bentoBox.deposit(mim, address(this), recipient, mim.balanceOf(address(this)), 0);
        extraShare = shareReturned - shareToMin;
    }
}

