// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;


import "./ERC20.sol";

interface INonfungiblePositionManager {
  struct CollectParams {
    uint256 tokenId;
    address recipient;
    uint128 amount0Max;
    uint128 amount1Max;
  }

  function collect(CollectParams calldata params) external payable returns (uint256 amount0, uint256 amount1);
  function transferFrom(address from, address to, uint256 tokenID) external;
}

////// MULTISIG NFT --- 158679
contract LiquidityLocker {

  address public constant token0 = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
  address public constant token1 = 0x954ac1c73e16c77198e83C088aDe88f6223F3d44;
  address public constant uniswapNFT = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;

  address public owner;
  uint256 public endOfLock;

  bool public hasStarted;

  function startLock(uint256 tokenID, uint256 secondsToLock) external {
    require(!hasStarted);

    owner = msg.sender;
    endOfLock = block.timestamp + secondsToLock;

    require(endOfLock < 1698913117);

    hasStarted = true;

    INonfungiblePositionManager(uniswapNFT).transferFrom(msg.sender, address(this), tokenID);
  }

  function sendBackNFT(uint256 tokenID) external {
    require(hasLockEnded());
    require(msg.sender == owner);

    INonfungiblePositionManager(uniswapNFT).transferFrom(address(this), owner, tokenID);
  }

  function hasLockEnded() public view returns(bool) {
    require(hasStarted);

    if(block.timestamp > endOfLock) return true;
    
    return false;
  }

  function collectAllFees(uint256 tokenID) external {
    require(hasStarted);

    INonfungiblePositionManager.CollectParams memory params =
      INonfungiblePositionManager.CollectParams({
          tokenId: tokenID,
          recipient: address(this),
          amount0Max: type(uint128).max,
          amount1Max: type(uint128).max
      });

    (uint256 amount0, uint256 amount1) = INonfungiblePositionManager(uniswapNFT).collect(params);

    _sendFeesToOwner(amount0, amount1);
  }
  
  function _sendFeesToOwner(uint256 amount0, uint256 amount1) internal {
    ERC20(token0).transfer(owner, amount0);
    ERC20(token1).transfer(owner, amount1);
  }
}
