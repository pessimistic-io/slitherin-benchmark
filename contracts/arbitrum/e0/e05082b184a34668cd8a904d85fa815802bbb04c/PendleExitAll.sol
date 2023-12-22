// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "./IPAllAction.sol";
import "./IPMarket.sol";
import "./BoringOwnableUpgradeable.sol";
import "./Pausable.sol";

contract PendleExitAll is TokenHelper, BoringOwnableUpgradeable {
    using SafeERC20 for IERC20;

    IPAllAction internal immutable router;
    bool public isDeprecated;

    modifier notDeprecated() {
        require(!isDeprecated, "deprecated");
        _;
    }

    constructor(IPAllAction _router) initializer {
        router = _router;
        __BoringOwnable_init();
    }

    function setDeprecated(bool _isDeprecated) external onlyOwner {
        isDeprecated = _isDeprecated;
    }

    function getPossibleTokenOut(address market) external view returns (address[] memory) {
        (IStandardizedYield SY,,) = IPMarket(market).readTokens();
        return SY.getTokensOut();
    }

    function exitYield(address market) external notDeprecated {
        (IStandardizedYield SY,, IPYieldToken YT) = IPMarket(market).readTokens();
        SY.claimRewards(msg.sender);
        YT.redeemDueInterestAndRewards(msg.sender, true, true);
        IPMarket(market).redeemRewards(msg.sender);
    }

    // To call only after exitYield.
    function exitAll(address market, address tokenOut, uint256 minTokenOut)
        external
        notDeprecated
        returns (uint256 totalTokenOut)
    {
        (IStandardizedYield SY, IPPrincipalToken PT, IPYieldToken YT) = IPMarket(market).readTokens();

        {
            IPMarket LP = IPMarket(market);
            uint256 netLp = LP.balanceOf(msg.sender);
            _pullApprove(LP, netLp);

            if (netLp > 0) {
                // EXIT LP
                router.removeLiquidityDualSyAndPt(msg.sender, market, netLp, 0, 0);
            }
        }

        // ----------------------------

        {
            uint256 netPt = PT.balanceOf(msg.sender);
            _pullApprove(PT, netPt);

            uint256 netYt = YT.balanceOf(msg.sender);
            _pullApprove(YT, netYt);

            uint256 netRedeem = PMath.min(netPt, netYt);

            if (netRedeem > 0) {
                // REDEEM PT + YT
                router.redeemPyToSy(msg.sender, address(YT), netRedeem, 0);
                netPt -= netRedeem;
                netYt -= netRedeem;
            }

            if (netPt > 0) {
                // EXIT PT
                router.swapExactPtForSy(msg.sender, market, netPt, 0);
            }

            if (netYt > 0) {
                // EXIT YT
                router.swapExactYtForSy(msg.sender, market, netYt, 0);
            }
        }

        // ----------------------------

        // EXIT SY
        uint256 netSy = SY.balanceOf(msg.sender);
        _pullApprove(SY, netSy);
        totalTokenOut = router.redeemSyToToken(msg.sender, address(SY), netSy, _newTokenOutput(tokenOut, minTokenOut));
    }

    function _pullApprove(IERC20 token, uint256 netToken) internal {
        if (netToken == 0) return;
        _transferIn(address(token), msg.sender, netToken);
        IERC20(token).safeApprove(address(router), type(uint256).max);
    }

    function _newTokenOutput(address tokenOut, uint256 minTokenOut) internal pure returns (TokenOutput memory out) {
        out.tokenOut = tokenOut;
        out.tokenRedeemSy = tokenOut;
        out.minTokenOut = minTokenOut;
    }
}

