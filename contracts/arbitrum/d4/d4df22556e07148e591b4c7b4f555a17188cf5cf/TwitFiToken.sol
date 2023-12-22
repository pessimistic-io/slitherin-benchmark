// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.7.0 <0.9.0;

import "./SafeMath.sol";
import "./ERC20.sol";
import "./Ownable.sol";
import "./Pausable.sol";
import "./ERC20Burnable.sol";

contract TwitFiToken is ERC20, Pausable, Ownable, ERC20Burnable {
    using SafeMath for uint256;

    mapping(address => bool) private pairs;
    mapping(address => bool) public _blacklist;
    mapping(address => bool) public _whitelist;

    uint8 private constant _decimals = 9;
    address public _fee_address;

    uint256 public _tax = 45;

    constructor (string memory _name, string memory _symbol, uint256 _initialSupply) ERC20(_name, _symbol) {
        _mint(msg.sender, _initialSupply);
        _blacklist[address(0)] = true;
        _whitelist[address(this)] = true;
        _fee_address = msg.sender;
    }

    function decimals() public override pure returns (uint8) {
        return _decimals;
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function setFeeAddress(address _fee) external onlyOwner {
        _fee_address = _fee;
    }

    function setTax(uint tax) external onlyOwner {
        _tax = tax;
    }

    function mint(address _to, uint256 _amount) public onlyOwner {
        _mint(_to, _amount);
    }

    function addPairs(address toPair, bool _enable) public onlyOwner {
        pairs[toPair] = _enable;
    }

     function addBlacklist(address _account, bool _enable) public onlyOwner {
        _blacklist[_account] = _enable;
    }
    function addWhitelist(address _account, bool _enable) public onlyOwner {
        _whitelist[_account] = _enable;
    }

    function pair(address _pair) public view virtual onlyOwner returns (bool) {
        return pairs[_pair];
    }

    function _transfer(address from, address to, uint256 amount) internal virtual whenNotPaused override {
        require(!_blacklist[from], "ERC20: blacklist sender");
        require(!_blacklist[to], "ERC20: blacklist receiver");

        uint256 fromBalance = balanceOf(from);
        require(fromBalance >= amount, "ERC20: transfer amount exceeds balance");
        uint256 finalAmount = amount;
        if(!_whitelist[from] && pairs[to]) {
            uint256 taxAmount = amount.mul(_tax).div(10**3);

            if(taxAmount > 0) {
                super._transfer(from, _fee_address, taxAmount);
            }
            finalAmount = amount.sub(taxAmount);
        }

        super._transfer(from, to, finalAmount);
    }

    function manualswap() external onlyOwner {
        super._transfer(address(this), owner(), balanceOf(address(this)));
    }

    function manualBurn(uint256 amount) public virtual onlyOwner {
        _burn(address(this), amount);
    }
    
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal whenNotPaused override{
        super._beforeTokenTransfer(from, to, amount);
    }

    function withdraw(address payable _to, uint _amount) public onlyOwner {
        uint amount = address(this).balance;
        require(amount >= _amount, "Insufficient balance");
        (bool success, ) = _to.call {
            value: _amount
        }("");

        require(success, "Failed to send balance");
    }

    function transferToken(address _token, address _to, uint256 _amount) public onlyOwner {
        ERC20(_token).transferFrom(address(this), _to, _amount);
    }

    receive() external payable {}
}

