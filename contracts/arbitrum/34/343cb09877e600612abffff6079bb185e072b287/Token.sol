// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

import "./Ownable.sol";
import "./SafeMath.sol";
import "./ERC20.sol";

contract Token is ERC20, Ownable {
    using SafeMath for uint256;

    address public pair;
    address public buyFeeRecipient;
    address public sellFeeRecipient;
    address public pool;
    address public platform;

    mapping(address => bool) fromBlackList;
    mapping(address => bool) toBlackList;

    mapping(address => bool) public notFromFee;
    mapping(address => bool) public notToFee;

    uint256 public _startTime;
    uint256 public buyRate = 3;
    uint256 public sellRate = 3;

    uint256 public maxTotalSupply = 200000000 * 1e18;

    constructor(
        string memory name_,
        string memory symbol_
    ) ERC20(name_, symbol_, 18) {
        uint256 initSupply = 1000000000 * 10 ** uint256(decimals());
        _mint(address(this), initSupply);
    }

    function setRecipients(
        address _buyFeeRecipient,
        address _sellFeeRecipient
    ) public onlyOwner {
        buyFeeRecipient = _buyFeeRecipient;
        sellFeeRecipient = _sellFeeRecipient;
    }

    function setPool(address _pool) public onlyOwner {
        pool = _pool;
        super._transfer(address(this), pool, _totalSupply.mul(999).div(1000));
    }

    function setPlatform(address _platform) public onlyOwner {
        platform = _platform;
        super._transfer(address(this), platform, _totalSupply.div(1000));
    }

    function setBlackList(
        address _addr,
        bool _setForm,
        bool _setTo
    ) public onlyOwner {
        fromBlackList[_addr] = _setForm;
        toBlackList[_addr] = _setTo;
    }

    function isFromBlackList(address _addr) public view returns (bool) {
        return fromBlackList[_addr];
    }

    function isToBlackList(address _addr) public view returns (bool) {
        return toBlackList[_addr];
    }

    function setBuyRate(uint256 _rate) public onlyOwner {
        buyRate = _rate;
    }

    function setSellRate(uint256 _rate) public onlyOwner {
        sellRate = _rate;
    }

    function setPair(address _pair) public onlyOwner {
        pair = _pair;
    }

    function setNotFee(address account, bool from, bool to) public onlyOwner {
        notFromFee[account] = from;
        notToFee[account] = to;
    }

    function setStartTime(uint256 startTime) public onlyOwner {
        _startTime = startTime;
    }

    function _burn(address account, uint256 value) internal virtual override {
        if (totalSupply() <= maxTotalSupply) {
            return;
        }
        uint256 canBurn = totalSupply().sub(maxTotalSupply);
        uint256 burnAmount = value > canBurn ? canBurn : value;
        super._burn(account, burnAmount);
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual override {
        require(!isFromBlackList(sender), "sender error");
        require(!isToBlackList(recipient), "recipient error");
        if (notFromFee[tx.origin] || notToFee[tx.origin]) {
            super._transfer(sender, recipient, amount);
            return;
        }
        if (pair == sender || pair == recipient) {

            require(
                _startTime > 0 && block.timestamp > _startTime,
                "can not trade before start time"
            );
            _feeTransfer(sender, recipient, amount);
        } else {
            super._transfer(sender, recipient, amount);
        }
    }

    function _feeTransfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");
        uint256 recipientAmount = _recipientAmountSubFee(sender, amount);
        _balances[sender] = _balances[sender].sub(amount);
        _balances[recipient] = _balances[recipient].add(recipientAmount);
        emit Transfer(sender, recipient, recipientAmount);
    }

    function _recipientAmountSubFee(
        address sender,
        uint256 amount
    ) internal returns (uint256) {
        uint256 recipientAmount;
        if (pair == sender) {
            if (buyFeeRecipient != address(0)) {
                recipientAmount = amount.mul(buyRate).div(100);
                _balances[buyFeeRecipient] = _balances[buyFeeRecipient].add(
                    recipientAmount
                );
                emit Transfer(sender, buyFeeRecipient, recipientAmount);
            }
        } else {
            if (sellFeeRecipient != address(0)) {
                recipientAmount = amount.mul(sellRate).div(100);
                _balances[sellFeeRecipient] = _balances[sellFeeRecipient].add(
                    recipientAmount
                );
                emit Transfer(sender, sellFeeRecipient, recipientAmount);
            }
        }
        return amount.sub(recipientAmount);
    }
}

