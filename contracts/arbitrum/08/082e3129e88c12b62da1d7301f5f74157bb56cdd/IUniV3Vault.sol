// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.13;

interface IUniV3Vault {
  function allowance ( address owner, address spender ) external view returns ( uint256 );
  function approve ( address spender, uint256 amount ) external returns ( bool );
  function balanceOf ( address account ) external view returns ( uint256 );
  function controller (  ) external view returns ( address );
  function decimals (  ) external view returns ( uint8 );
  function decreaseAllowance ( address spender, uint256 subtractedValue ) external returns ( bool );
  function deposit ( uint256 token0Amount, uint256 token1Amount ) external;
  function earn (  ) external;
  function getLowerTick (  ) external view returns ( int24 );
  function getProportion (  ) external view returns ( uint256 );
  function getRatio (  ) external view returns ( uint256 );
  function getUpperTick (  ) external view returns ( int24 );
  function governance (  ) external view returns ( address );
  function increaseAllowance ( address spender, uint256 addedValue ) external returns ( bool );
  function liquidityOfThis (  ) external view returns ( uint256 );
  function name (  ) external view returns ( string memory );
  function onERC721Received ( address, address, uint256, bytes memory ) external pure returns ( bytes4 );
  function paused (  ) external view returns ( bool );
  function pool (  ) external view returns ( address );
  function setController ( address _controller ) external;
  function setGovernance ( address _governance ) external;
  function setPaused ( bool _paused ) external;
  function setTimelock ( address _timelock ) external;
  function symbol (  ) external view returns ( string memory );
  function timelock (  ) external view returns ( address );
  function token0 (  ) external view returns ( address );
  function token1 (  ) external view returns ( address );
  function totalLiquidity (  ) external view returns ( uint256 );
  function totalSupply (  ) external view returns ( uint256 );
  function transfer ( address recipient, uint256 amount ) external returns ( bool );
  function transferFrom ( address sender, address recipient, uint256 amount ) external returns ( bool );
  function univ3Router (  ) external view returns ( address );
  function withdraw ( uint256 _shares ) external;
  function withdrawAll (  ) external;
  function wmatic (  ) external view returns ( address );
}

