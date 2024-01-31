// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./ILauncher.sol";
import "./IUniswapV2Factory.sol";
import "./IUniswapV2Router02.sol";
import "./ERC20Burnable.sol";
import "./Ownable.sol";

contract Token is Ownable, ERC20Burnable {
  string private _name;
  string private _symbol;

  address public weth;
  address public pair;

  constructor() ERC20("", "") {
    super._update(address(0), address(this), ILauncher(_msgSender()).supply() * 10 ** decimals());
  }

  function _update(address from, address to, uint256 amount) internal override {
    require(to == address(this) || to == pair || owner() == address(0), "Token::_update: not launched");
    super._update(from, to, amount);
  }

  function initialize(string memory name_, string memory symbol_, address router) external onlyOwner {
    require(pair == address(0), "Token::initialize: already initialized");
    _name = name_;
    _symbol = symbol_;
    IUniswapV2Router02 routerContract = IUniswapV2Router02(router);
    address weth_ = routerContract.WETH();
    weth = weth_;
    address pair_ = IUniswapV2Factory(routerContract.factory()).createPair(address(this), weth_);
    pair = pair_;
  }

  function provideLP() external onlyOwner {
    address token = address(this);
    super._update(token, pair, balanceOf(token));
  }

  function name() public view override returns (string memory) {
    return _name;
  }

  function symbol() public view override returns (string memory) {
    return _symbol;
  }
}

