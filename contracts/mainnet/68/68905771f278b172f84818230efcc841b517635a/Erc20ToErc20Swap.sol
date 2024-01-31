//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./BaseRelayRecipient.sol";
import "./IERC20.sol";
import "./AccessControl.sol";

import "./IUniswapV2Router02.sol";

import "./TokenPaymasteTokenOnToken.sol";

contract TokenOnTokenSwap is BaseRelayRecipient {
    event Received(uint256 value, address sender);

    IUniswapV2Router02 internal immutable _router;
    TokenPaymasterForTokenOnTokenSwap internal _paymaster;

    address private _sender;

    bool public onSwap;

    modifier updateSender() {
        require(!onSwap, "On swap");
        onSwap = true;
        // require(isTrustedForwarder(msg.sender), "Not forwarder");
        _sender = BaseRelayRecipient._msgSender();
        _;
    }

    constructor(
        address _forwarder,
        address uniswapRouter,
        address payable tokenPaymaster
    ) {
        _setTrustedForwarder(_forwarder);
        _router = IUniswapV2Router02(uniswapRouter);
        _paymaster = TokenPaymasterForTokenOnTokenSwap(tokenPaymaster);
    }

    function _getPath(address token1, address token2)
        private
        pure
        returns (address[] memory path)
    {
        path = new address[](2);
        path[0] = token1;
        path[1] = token2;
    }

    function swapTokensForTokens(
        address tokenToSwap,
        address tokenToGet,
        uint256 amountIn
    ) external updateSender {
        IERC20 erc20 = IERC20(tokenToSwap);
        erc20.transferFrom(_sender, address(this), amountIn);
        erc20.approve(address(_router), amountIn);

        _router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn,
            0,
            _getPath(tokenToSwap, tokenToGet),
            address(_paymaster),
            block.timestamp  + 60 * 15
        );

        (address paymentToken, uint256 fee) = _paymaster.getPaymentData();
        IERC20(paymentToken).transferFrom(_sender, address(0xdead), fee);
    }

    function versionRecipient() external pure override returns (string memory) {
        return "2.2.0+opengsn.swap.irelayrecipient";
    }

    receive() external payable {
        uint256 value = msg.value;
        (bool sent, ) = address(_paymaster).call{value: value}("");
        require(sent, "Failed to send Ether");
        emit Received(msg.value, _sender);
        onSwap = false;
    }
}

