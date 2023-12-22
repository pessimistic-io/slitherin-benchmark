// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "./Ownable.sol";

interface IERC20 {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function decimals() external returns (uint);
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);
}

contract Anchor is Ownable {
    IERC20 public volt;
    mapping(address => bool) public allowedTokens;
    address public treasury;
    uint public mintFees = 5;
    uint public redeemFees = 5;


    constructor(address _volt, address _treasury) {
        treasury = _treasury;
        volt = IERC20(_volt);
    }

    function mint(uint256 amount, address input) external {
        require(allowedTokens[input], "!allowed");
        IERC20(input).transferFrom(msg.sender, address(this), amount);
        uint256 fee = amount * mintFees / 1000;
        uint256 amountAfterFee = amount - fee;
        uint256 decimals = IERC20(input).decimals();
        uint256 voltAmount = amountAfterFee * 10 ** uint256(volt.decimals()) / 10 ** decimals;
        volt.transfer(msg.sender, voltAmount);
        IERC20(input).transfer(treasury, fee);
    }

    function redeem(uint256 amount, address output) external {
        require(allowedTokens[output], "!allowed");
        uint256 decimals = IERC20(output).decimals();
        uint256 voltAmount = amount * 10 ** uint256(volt.decimals()) / 10 ** decimals;
        volt.transferFrom(msg.sender, address(this), voltAmount);
        uint256 fee = amount * redeemFees / 1000;
        uint256 amountAfterFee = amount - fee;
        IERC20(output).transfer(msg.sender, amountAfterFee);
        IERC20(output).transfer(treasury, fee);
    }

    function changeTreasury(address _new) external onlyOwner {
        treasury = _new;
    }

    function changeFees(uint _mint, uint _redeem) external onlyOwner {
        mintFees = _mint;
        redeemFees = _redeem;
    }

    function allowToken(address _token, bool _isAllowed) external onlyOwner {
        allowedTokens[_token] = _isAllowed;
    }
}
