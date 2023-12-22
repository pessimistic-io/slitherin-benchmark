// SPDX-License-Identifier: MIT

import "./ReentrancyGuard.sol";
import "./IWETH.sol";
import "./ERC20.sol";
import "./IHlpManager.sol";

pragma solidity 0.6.12;

contract HlpManagerRouter is ReentrancyGuard {
    address public weth;
    address public hlpManager;

    constructor(address _weth, address _hlpManager) public {
        weth = _weth;
        hlpManager = _hlpManager;
        ERC20(weth).approve(hlpManager, 2**256 - 1);
    }

    function _wrapETH() private {
        IWETH(weth).deposit{value: msg.value}();
    }

    function _unwrapETH(uint256 _amount, address payable receiver) private {
        IWETH(weth).withdraw(_amount);
        (bool success, ) = receiver.call{value: _amount}("");
        require(success, "Failed to send Ether");
    }

    receive() external payable {
        require(msg.sender == weth, "Router: invalid sender");
    }

    function addLiquidityETH(uint256 _minUsdg, uint256 _minGlp)
        external
        payable
        nonReentrant
        returns (uint256)
    {
        if (msg.value > 0) {
            _wrapETH();
        }
        return
            IHlpManager(hlpManager).addLiquidityForAccount(
                address(this),
                msg.sender,
                weth,
                msg.value,
                _minUsdg,
                _minGlp
            );
    }

    function removeLiquidityETH(
        uint256 _glpAmount,
        uint256 _minOut,
        address payable _receiver
    ) external nonReentrant returns (uint256) {
        uint256 amountOut = IHlpManager(hlpManager).removeLiquidityForAccount(
            msg.sender,
            weth,
            _glpAmount,
            _minOut,
            address(this)
        );
        _unwrapETH(amountOut, _receiver);
        return amountOut;
    }
}

