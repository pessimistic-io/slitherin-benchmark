// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./IPAllAction.sol";
import "./IPMarket.sol";
import "./TokenHelper.sol";

contract LiquiditySeedingHelper is TokenHelper {
    address public immutable router;

    constructor(address _router) {
        router = _router;
    }

    function _approveRouter(IStandardizedYield SY) internal {
        IPAllAction.MultiApproval[] memory data = new IPAllAction.MultiApproval[](1);
        data[0].tokens = SY.getTokensIn();
        data[0].spender = address(SY);
        IPAllAction(router).approveInf(data);
    }

    function seedLiquidity(address market, address token, uint256 amount) external payable {
        require(IPMarket(market).totalSupply() == 0, "Liquidity already seeded");

        (IStandardizedYield SY, IPPrincipalToken PT, IPYieldToken YT) = IPMarket(market)
            .readTokens();

        _transferIn(token, msg.sender, amount);

        // Approval
        _approveRouter(SY);
        _safeApproveInf(token, router);
        _safeApproveInf(address(SY), router);
        _safeApproveInf(address(PT), router);

        // Mint SY

        uint256 netNative = (token == NATIVE ? amount : 0);
        IPAllAction(router).mintSyFromToken{ value: netNative }(
            address(this),
            address(SY),
            0,
            TokenInput({
                tokenIn: token,
                netTokenIn: amount,
                tokenMintSy: token,
                bulk: address(0),
                pendleSwap: address(0),
                swapData: SwapData({
                    swapType: SwapType.NONE,
                    extRouter: address(0),
                    extCalldata: abi.encode(),
                    needScale: false
                })
            })
        );

        // mint PY
        IPAllAction(router).mintPyFromSy(address(this), address(YT), _selfBalance(SY) / 2, 0);

        // mint LP
        IPAllAction(router).addLiquidityDualSyAndPt(
            msg.sender,
            market,
            _selfBalance(SY),
            _selfBalance(PT),
            0
        );

        _transferOut(address(YT), msg.sender, _selfBalance(YT));
    }

    receive() external payable {}
}

