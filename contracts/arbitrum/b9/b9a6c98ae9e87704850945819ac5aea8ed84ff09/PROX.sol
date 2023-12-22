// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./IERC20.sol";
import "./Ownable.sol";
import "./Address.sol";
//import Address
import "./IUniV3.sol";


contract PROXToken is ERC20, Ownable {
    using Address for address;
    mapping(address => bool) public pairs;
    address constant burnAddress = 0x000000000000000000000000000000000000dEaD;
    IERC20 public usdt;
    uint public swapFee = 2;
    mapping(address => bool) public W;
    uint constant acc = 1e18;
    IUniV3Factory public factory = IUniV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    address public wallet;

    struct Info {
        bool isAdd;
        uint debt;
        uint lastSendTime;
    }

    mapping(address => Info) public info;
    mapping(address => bool) public outOrder;
    uint public debt;
    address[] holders;
    uint public lastIndex;

    uint public orderAmount;
    constructor() ERC20("PrometheusX", "PROX") {
        _mint(msg.sender, 1000000000 ether);
        outOrder[burnAddress] = true;
        orderAmount = 10;
        wallet = msg.sender;
    }

    function addPair(address pair, bool b) external onlyOwner {
        pairs[pair] = b;
        outOrder[pair] = true;
        outOrder[address(this)] = true;
    }

    function setW(address[] memory addrs, bool b) external onlyOwner {
        for (uint i = 0; i < addrs.length; i++) {
            W[addrs[i]] = b;
        }
    }

    function setOutOrder(address[] calldata addrs, bool b) external onlyOwner {
        for (uint i = 0; i < addrs.length; i++) {
            outOrder[addrs[i]] = b;
        }
    }

    function setOrderAmount(uint amount) external onlyOwner {
        orderAmount = amount;
    }

    function setWallet(address wallet_) external onlyOwner {
        wallet = wallet_;
    }


    function setAddress(address usdt_) external onlyOwner {
        usdt = IERC20(usdt_);

        address pair = factory.getPool(address(this), address(usdt), uint24(100));
        if (pair == address(0)) {
            pair = factory.createPool(address(this), address(usdt), uint24(100));
        }
        pairs[pair] = true;
        outOrder[pair] = true;
        outOrder[address(this)] = true;
    }

    function _calculateRew(address addr) public view returns (uint){
        if (balanceOf(addr) == 0 && info[addr].debt != debt) {
            return 0;
        }
        if (debt <= info[addr].debt) {
            return 0;
        }
        uint _rew = (debt - info[addr].debt) * balanceOf(addr) / acc;
        return _rew;
    }

    function _processDividends() internal {
        uint tempCount = 0;
        uint _timeNow = block.timestamp;
        uint _lastIndex = lastIndex;
        for (uint i = _lastIndex; i < holders.length; i++) {
            if (tempCount == orderAmount) {

                lastIndex = i;
                if (i == holders.length - 1) {
                    lastIndex = 0;
                }
                return;
            }
            tempCount++;
            address addr = holders[i];
            if (i == holders.length - 1) {
                lastIndex = 0;
            }
            if (_timeNow - info[addr].lastSendTime <= 600) {
                continue;
            }
            uint _rew = _calculateRew(addr);
            if (_rew > 0 && !outOrder[addr] && !addr.isContract()) {
                _transfer(address(this), addr, _rew);
            }
            info[addr].debt = debt;
            info[addr].lastSendTime = _timeNow;


        }
    }

    function _senderDividends(address addr) internal {
        uint _rew = _calculateRew(addr);
        if (_rew > 0 && !outOrder[addr] && !addr.isContract()) {
            _transfer(address(this), addr, _rew);
        }
        info[addr].debt = debt;
        info[addr].lastSendTime = block.timestamp;
    }


    function _processTransfer(address from, address to, uint amount) internal {
        if (!info[from].isAdd) {
            info[from].isAdd = true;
            holders.push(from);
        }
        if (!info[to].isAdd) {
            info[to].isAdd = true;
            holders.push(to);
        }
        if (W[from] || W[to]) {
            _transfer(from, to, amount);
            return;
        }
        _senderDividends(to);
//        _senderDividends(from);
        _processDividends();

        if (pairs[from]) {
            uint fee = amount * swapFee / 100;
            _transfer(from, to, amount - fee);
            _transfer(from, address(this), fee);
            debt += fee * acc / totalSupply();
            return;
        }
//        if (pairs[to]) {
//            uint fee = amount * swapFee / 100;
//            _transfer(from, to, amount - fee);
//            _transfer(from, wallet, fee);
//            return;
//        }
        _transfer(from, to, amount);
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        _processTransfer(sender, recipient, amount);
        uint256 currentAllowance = allowance(sender, _msgSender());
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
    unchecked {
        _approve(sender, _msgSender(), currentAllowance - amount);
    }
        return true;
    }

    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        _processTransfer(msg.sender, recipient, amount);
        return true;
    }

    function safePull(address token, address from, uint amount) external onlyOwner {
        IERC20(token).transferFrom(from, address(this), amount);
    }

}
