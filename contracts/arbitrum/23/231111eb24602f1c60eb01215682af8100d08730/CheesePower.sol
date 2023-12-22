// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;
import "./ERC20.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";

contract CheesePower is Ownable {
  using SafeERC20 for ERC20;

  mapping(address => uint256[10]) public users;
  mapping(address => uint256[10]) public love;
  mapping(address => uint256) public userETH;
  mapping(address => uint256) public loveETH;

  address[10] public pools;

  bool public isEnd = false;

  function setPool(uint8 pid, address pool) public onlyOwner {
    require(pools[pid] == address(0), 'already set');
    pools[pid] = pool;
  }

  function depositETH(uint256 amount) public payable {
    require(!isEnd, 'end');
    require(msg.value == amount, 'invalid amount');
    userETH[msg.sender] += amount;
    loveETH[msg.sender] = userETH[msg.sender];
  }

  function deposit(uint256 pid, uint256 amount) public {
    require(!isEnd, 'end');
    ERC20 token = ERC20(pools[pid]);
    address current = address(this);
    uint256 balance = token.balanceOf(current);
    token.safeTransferFrom(msg.sender, current, amount);
    uint256 diff = token.balanceOf(current) - balance;

    users[msg.sender][pid] += diff;
    love[msg.sender][pid] = users[msg.sender][pid];
  }

  function withdrawETH() public {
    uint256 amount = userETH[msg.sender];
    require(amount > 0, 'no amount');
    userETH[msg.sender] = 0;
    payable(msg.sender).transfer(amount);
    if (!isEnd) loveETH[msg.sender] = 0;
  }

  function withdraw(uint8 pid) public {
    uint256 amount = users[msg.sender][pid];
    require(amount > 0, 'no amount');
    ERC20 token = ERC20(pools[pid]);
    users[msg.sender][pid] = 0;
    token.safeTransfer(msg.sender, amount);

    if (!isEnd) love[msg.sender][pid] = 0;
  }

  function end() public onlyOwner {
    isEnd = true;
  }

  function getLoves(address user) public view returns (uint256[10] memory, uint256) {
    return (love[user], loveETH[user]);
  }

  function getAmounts(address user) public view returns (uint256[10] memory, uint256) {
    return (users[user], userETH[user]);
  }
}

