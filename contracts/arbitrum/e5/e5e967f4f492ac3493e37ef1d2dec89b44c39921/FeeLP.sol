// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./Address.sol";

contract FeeLP {
    using Address for address;

    address public owner;
    mapping(address => uint256) public balanceOf;
    //user=>router or orderbook=>increase or decrease=>amount
    mapping(address => mapping(address => mapping(bool => uint256)))
        public locked;

    mapping(address => bool) private keeperMap;
    uint256 public totalSupply;

    string public name = "LionDEX feeLP";
    string public symbol = "feeLP";

    event Lock(address user, address lockTo, uint256 amount, bool isIncrease);
    event Unlock(address user, address lockTo, uint256 amount, bool isIncrease);
    event BurnLocked(
        address user,
        address lockTo,
        uint256 amount,
        bool isIncrease
    );
    event Transfer(address indexed from, address indexed to, uint256 value);
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );
    event SetKeeper(address sender,address addr,bool active);
    constructor() {
        owner = msg.sender;
    }

    modifier onlyKeeper() {
        require(isKeeper(msg.sender), "FeeLP: not keeper");
        _;
    }

    modifier onlyOwner() {
        require(owner == msg.sender, "FeeLP: not owner");
        _;
    }

    function lock(
        address user,
        address lockTo,
        uint256 amount,
        bool isIncrease
    ) public onlyKeeper {
        require(balanceOf[user] >= amount, "FeeLP: amount invalid");
        balanceOf[user] = balanceOf[user] - amount;
        locked[user][lockTo][isIncrease] =
            locked[user][lockTo][isIncrease] +
            amount;

        emit Lock(user, lockTo, amount, isIncrease);
    }

    function unlock(
        address user,
        address lockTo,
        uint256 amount,
        bool isIncrease
    ) public onlyKeeper {
        require(
            locked[user][lockTo][isIncrease] >= amount,
            "FeeLP: locked amount invalid"
        );
        locked[user][lockTo][isIncrease] =
            locked[user][lockTo][isIncrease] -
            amount;
        balanceOf[user] = balanceOf[user] + amount;

        emit Unlock(user, lockTo, amount, isIncrease);
    }

    function burnLocked(
        address user,
        address lockTo,
        uint256 amount,
        bool isIncrease
    ) public onlyKeeper {
        require(
            locked[user][lockTo][isIncrease] >= amount,
            "FeeLP: locked amount invalid"
        );
        locked[user][lockTo][isIncrease] =
            locked[user][lockTo][isIncrease] -
            amount;
        totalSupply -= amount;

        emit BurnLocked(user, lockTo, amount, isIncrease);
        emit Transfer(user,address(0),amount);
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public onlyKeeper {
        _transfer(sender, recipient, amount);
    }

    function transfer(address recipient, uint256 amount) public onlyKeeper {
        _transfer(msg.sender, recipient, amount);
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) private {
        require(balanceOf[sender] >= amount, "FeeLP: amount invalid");
        balanceOf[sender] = balanceOf[sender] - amount;
        balanceOf[recipient] = balanceOf[recipient] + amount;

        emit Transfer(sender, recipient, amount);
    }

    function setKeeper(address addr, bool active) public onlyOwner {
        require(addr.isContract(), "FeeLP: address must be FeeLP contract");
        keeperMap[addr] = active;
        emit SetKeeper(msg.sender,addr,active);
    }

    function isKeeper(address addr) public view returns (bool) {
        return keeperMap[addr];
    }

    function decimals() public pure returns (uint8) {
        return 18;
    }

    function transferOwnership(address newOwner) public onlyOwner {
        address oldOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }

    function mintTo(address user, uint256 amount) public onlyKeeper {
        totalSupply = totalSupply + amount;
        balanceOf[user] = balanceOf[user] + amount;

        emit Transfer(address(0), user, amount);
    }

    function burn(address user, uint256 amount) public onlyKeeper {
        require(totalSupply >= amount, "FeeLP: amount>totalSupply");
        totalSupply = totalSupply - amount;
        require(balanceOf[user] >= amount, "FeeLP: amount invalid");
        balanceOf[user] = balanceOf[user] - amount;

        emit Transfer(user, address(0), amount);
    }
}

