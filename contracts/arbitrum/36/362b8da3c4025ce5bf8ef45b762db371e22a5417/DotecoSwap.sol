// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./IERC20.sol";

contract DotecoSwap {
    address private swapFactory;
    address public owner1;
    address public owner2;
    IERC20 public token1;
    IERC20 public token2;
    uint256 public amount1;
    uint256 public amount2;
    uint256 public swapFee;
    bool public isFinished = false;

    constructor(
        address _swapFactory,
        address _token1,
        address _owner1,
        uint256 _amount1,
        address _token2,
        address _owner2,
        uint256 _amount2,
        uint256 _swapFee
    ) {
        swapFactory = _swapFactory;
        token1 = IERC20(_token1);
        owner1 = _owner1;
        amount1 = _amount1;
        token2 = IERC20(_token2);
        owner2 = _owner2;
        amount2 = _amount2;
        swapFee = _swapFee;
    }

    function swap() external payable {
        require(
            !isFinished, 
            "DotecoSwap::Already finished"
        );
        require(
            msg.value >= swapFee,
            "DotecoSwap::Insufficient swap fee"
        );
        (bool feeSent, ) = swapFactory.call{value: msg.value}("");
        require(
            feeSent,
            "DotecoSwap::Fee transfer unsuccesful"
        );
        require(
            msg.sender == owner1 || msg.sender == owner2,
            "DotecoSwap::Unauthorized sender");
        require(
            token1.allowance(owner1, address(this)) >= amount1,
            "DotecoSwap::Token 1 allowance too low"
        );
        require(
            token2.allowance(owner2, address(this)) >= amount2,
            "DotecoSwap::Token 2 allowance too low"
        );

        isFinished = true;

        _safeTransferFrom(token1, owner1, owner2, amount1);
        _safeTransferFrom(token2, owner2, owner1, amount2);    
    }

    function _safeTransferFrom(
        IERC20 token,
        address sender,
        address recipient,
        uint256 amount
    ) 
        private 
    {
        bool sent = token.transferFrom(sender, recipient, amount);
        require(sent, "DotecoSwap::ERC20 transfer failed");
    }
}

