// SPDX-License-Identifier: MIT
// solhint-disable avoid-low-level-calls
pragma solidity >=0.8.0;

import "./IERC20.sol";
import "./BoringERC20.sol";
import "./SafeApprove.sol";
import "./IBentoBoxV1.sol";
import "./ISwapperV2.sol";
import "./IGmxGlpRewardRouter.sol";
import "./IERC4626.sol";
import "./IGmxVault.sol";

contract GlpSwapper is ISwapperV2 {
    using BoringERC20 for IERC20;
    using SafeApprove for IERC20;

    error ErrSwapFailed();
    error ErrTokenNotSupported(IERC20);

    IBentoBoxV1 public immutable bentoBox;
    IERC20 public immutable _in;
    IERC20 public immutable sGLP;
    IGmxGlpRewardRouter public immutable glpRewardRouter;
    address public immutable zeroXExchangeProxy;
    IGmxVault public immutable gmxVault;

    constructor(
        IBentoBoxV1 _bentoBox,
        IGmxVault _gmxVault,
        IERC20 __in,
        IERC20 _sGLP,
        IGmxGlpRewardRouter _glpRewardRouter,
        address _zeroXExchangeProxy
    ) {
        bentoBox = _bentoBox;
        gmxVault = _gmxVault;
        _in = __in;
        sGLP = _sGLP;
        glpRewardRouter = _glpRewardRouter;
        zeroXExchangeProxy = _zeroXExchangeProxy;

        uint256 len = _gmxVault.allWhitelistedTokensLength();
        for (uint256 i = 0; i < len; i++) {
            IERC20 token = IERC20(_gmxVault.allWhitelistedTokens(i));
            if (token == _in) continue;
            token.safeApprove(_zeroXExchangeProxy, type(uint256).max);
        }

        _in.approve(address(_bentoBox), type(uint256).max);
    }

    /// @inheritdoc ISwapperV2
    function swap(
        address,
        address,
        address recipient,
        uint256 shareToMin,
        uint256 shareFrom,
        bytes calldata data
    ) public override returns (uint256 extraShare, uint256 shareReturned) {
        (bytes memory swapData, IERC20 token) = abi.decode(data, (bytes, IERC20));

        (uint256 amount, ) = bentoBox.withdraw(IERC20(address(sGLP)), address(this), address(this), 0, shareFrom);

        glpRewardRouter.unstakeAndRedeemGlp(address(token), amount, 0, address(this));

        // Token -> IN
        (bool success, ) = zeroXExchangeProxy.call(swapData);
        if (!success) {
            revert ErrSwapFailed();
        }

        // we can expect dust from both gmx and 0x
        token.safeTransfer(recipient, token.balanceOf(address(this)));

        (, shareReturned) = bentoBox.deposit(_in, address(this), recipient, _in.balanceOf(address(this)), 0);
        extraShare = shareReturned - shareToMin;
    }
}

