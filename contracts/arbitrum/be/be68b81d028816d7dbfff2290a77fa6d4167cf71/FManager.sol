// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.0;

import "./IUniswapV2Router02.sol";
import "./Ownable.sol";
import "./NimbusToken.sol";
import "./IERC20.sol";

contract FManager is Ownable {
    enum Type {
        ETH,
        TOKEN
    }

    NimbusToken public token;
    IUniswapV2Router02 uniV2router02;

    mapping(address => bool) restrictedList;

    modifier onlyRestrictedList() {
        require(
            restrictedList[msg.sender],
            "ERR: Action forbidden"
        );
        _;
    }

    constructor(NimbusToken _token, IUniswapV2Router02 _uniV2router02) {
        token = _token;
        uniV2router02 = _uniV2router02;
        restrictedList[address(_token)] = true;
        restrictedList[address(this)] = true;
        restrictedList[owner()] = true;
    }

    function swap() external onlyRestrictedList {
        address[] memory path = new address[](2);
        path[0] = address(token);
        path[1] = uniV2router02.WETH();
        uint256 amountIn = token.balanceOf(address(this));
        if (amountIn > 0) {
            token.approve(address(this), amountIn);
            token.approve(address(uniV2router02), amountIn);
            uniV2router02.swapExactTokensForETHSupportingFeeOnTransferTokens(
                amountIn,
                0,
                path,
                address(this),
                block.timestamp
            );
        }
    }

    function withdraw(
        Type _t,
        address _token,
        uint256 _amount
    ) external onlyOwner {
        if (_t == Type.ETH) {
            (bool sent, ) = (msg.sender).call{value: _amount}("");
            require(sent, "Failed to send Ether");
        } else {
            IERC20(_token).approve(address(this), _amount);
            IERC20(_token).transferFrom(address(this), msg.sender, _amount);
        }
    }

    function setRouter(IUniswapV2Router02 _value) external onlyOwner {
        uniV2router02 = _value;
    }

    function setToken(NimbusToken _value) external onlyOwner {
        token = _value;
    }

    function setRestrictedList(address _address, bool _value) external onlyOwner {
        restrictedList[_address] = _value;
    }

    receive() external payable {}
}

