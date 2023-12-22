// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./Ownable.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";


interface USDEX {  
    function mint(address to, uint256 amount) external returns (bool);
}



contract DirectUSDEXMinter is Ownable, ReentrancyGuard {
  using SafeERC20 for IERC20;

  
  address public tokenUSDEX;
  address public tokenUSDC;

  event Mint(address _to, uint256 _amount);


  constructor(address _usdex, address _usdc) {
    tokenUSDEX = _usdex;
    tokenUSDC = _usdc;
  }

  function getBalanceUSDC() public view returns (uint256) {
    return IERC20(tokenUSDC).balanceOf(address(this));
  }

  function mint(uint256 _amount) external nonReentrant returns (bool) {
    require(_amount > 0, "DirectUSDEXMinter: Mint amount is zero");
    IERC20(tokenUSDC).safeTransferFrom(msg.sender, address(this), _amount);

    uint256 _amountToMint = _amount * 10 ** 12;

    USDEX(tokenUSDEX).mint(msg.sender, _amountToMint);

    emit Mint(msg.sender, _amount);

    return true;
  }

  function claimUSDC(uint256 _amount, address _to) external onlyOwner returns (bool) {
    IERC20(tokenUSDC).safeTransfer(_to, _amount);
    return true;
  }

  function fullClaimUSDC(address _to) external onlyOwner returns (bool) {
    IERC20(tokenUSDC).safeTransfer(_to, getBalanceUSDC());
    return true;
  }

  function foreignTokensRecover(IERC20 _token, uint256 _amount, address _to) external onlyOwner returns (bool) {
    _token.safeTransfer(_to, _amount);
    return true;
  }
}

