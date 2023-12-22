// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;
import "./IERC20.sol";

interface IOwnable {
  function transferOwnership(address newOwner) external;
}

interface INftTransfer {
  function transferNft_(address _to, uint _tokenId) external;
}

interface IJonesLpStaker {
  function claimFees(address _claimTo) external returns (uint256 _gxpAmt, uint256 _grailAmt);

  function claimDividends(address _claimTo) external returns (uint256 _gxpAmt, uint256 _clpAmt);

  function stake(uint256 _amount) external;
}

interface IPlsJonesRewardsDistro {
  function sendRewards(address _to, uint _grailAmt, uint _gxpAmt) external;

  function record() external returns (uint _grailAmt, uint _gxpAmt);

  function hasBufferedRewards() external view returns (bool);

  function pendingRewards() external view returns (uint _grailAmt, uint _gxpAmt);

  event FeeChanged(uint256 indexed _new, uint256 _old);

  error UNAUTHORIZED();
  error INVALID_FEE();
}

interface IStaker is IOwnable {
  function stake(uint256) external;

  function withdraw(uint256, address) external;

  function exit() external;
}

interface ITokenMinter is IERC20, IOwnable {
  function mint(address, uint256) external;

  function burn(address, uint256) external;

  function setOperator(address _operator) external;
}

interface IUniV2Router {
  function addLiquidity(
    address tokenA,
    address tokenB,
    uint amountADesired,
    uint amountBDesired,
    uint amountAMin,
    uint amountBMin,
    address to,
    uint deadline
  ) external returns (uint amountA, uint amountB, uint liquidity);

  function removeLiquidity(
    address tokenA,
    address tokenB,
    uint liquidity,
    uint amountAMin,
    uint amountBMin,
    address to,
    uint deadline
  ) external returns (uint amountA, uint amountB);
}

interface IUniV2Pair is IERC20 {
  function getReserves() external view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast);

  function burn(address to) external returns (uint amount0, uint amount1);

  function token0() external view returns (address);

  function token1() external view returns (address);
}

interface IPlsJonesPlutusChef {
  error DEPOSIT_ERROR(string);
  error WITHDRAW_ERROR();
  error UNAUTHORIZED();
  error FAILED(string);

  event HandlerUpdated(address indexed _handler, bool _isActive);
  event Deposit(address indexed _user, uint256 _amount);
  event Withdraw(address indexed _user, uint256 _amount);
  event EmergencyWithdraw(address indexed _user, uint256 _amount);
}

