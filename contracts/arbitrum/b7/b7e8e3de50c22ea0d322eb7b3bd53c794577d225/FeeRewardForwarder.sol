pragma solidity 0.5.16;

import "./SafeMath.sol";
import "./SafeERC20.sol";
import "./IERC20.sol";
import "./SwappingLibrary.sol";
import "./IRewardPool.sol";
import "./IUniswapV2Router02.sol";
import "./Governable.sol";

contract FeeRewardForwarder is Governable, SwappingLibrary {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  /// @notice Tokens for predefined routes.
  address public constant magic = address(0x2c852D3334188BE136bFC540EF2bB8C37b590BAD);
  address public constant weth = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
  address public constant swpr = address(0x955b9fe60a5b5093df9Dc4B1B18ec8e934e77162);

  /// @notice Routers for predefined routes.
  address public constant swaprRouter = address(0x530476d5583724A89c8841eB6Da76E7Af4C0F17E);
  address public constant sushiRouter = address(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506);

  /// @notice Routes for fee liquidation. Must be set to liquidate fees.
  mapping(address => mapping (address => address[])) public routes;

  /// @notice Target router for liquidation, if not set, swapping will be
  /// done on multiple dexes using `targetRouters`.
  mapping(address => mapping(address => address)) public targetRouter;

  /// @notice Target routers in-case reward liquidation needs to be done
  /// on multiple AMMs instead of one AMM for liquidation.
  mapping(address => mapping(address => address[])) public targetRouters;

 /// @notice The token to send to `profitSharingPool`.
  address public targetToken;

  /// @notice Contract to send part of the protocol fees to.
  address public profitSharingPool;

  /// @notice Address to receive the rest of the protocol fees.
  address public protocolFund;

  /// @notice Percentage to receive fees for gas.
  uint256 public fundNumerator;

  event TokenPoolSet(address token, address pool);

  constructor(
    address _storage,
    uint256 _fundNumerator
  ) public Governable(_storage) {
    fundNumerator = _fundNumerator;
    // Predefined routes
    routes[swpr][magic] = [swpr, weth, magic];
    // Predefined routers
    targetRouters[swpr][magic] = [swaprRouter, sushiRouter];
  }

  /*
  *   Set the pool that will receive the reward token
  *   based on the address of the reward Token
  */
  function setTokenPool(address _pool) public onlyGovernance {
    targetToken = IRewardPool(_pool).rewardToken();
    profitSharingPool = _pool;
    emit TokenPoolSet(targetToken, _pool);
  }

  /**
  * Sets the path for swapping tokens to the to address
  * The to address is not validated to match the targetToken,
  * so that we could first update the paths, and then,
  * set the new target
  */
  function setConversionPath(
    address from, 
    address to, 
    address[] memory _route
  ) public onlyGovernance {
    routes[from][to] = _route;
  }

  function setConversionRouter(
    address _from, 
    address _to, 
    address _router
  ) public onlyGovernance {
    require(_router != address(0), "FeeRewardForwarder: The router cannot be empty");
    targetRouter[_from][_to] = _router;
  }

  function setConversionRouters(
    address _from,
    address _to,
    address[] memory _routers
  ) public onlyGovernance {
    targetRouters[_from][_to] = _routers;
  }

  // Transfers the funds from the msg.sender to the pool
  // under normal circumstances, msg.sender is the strategy
  function poolNotifyFixedTarget(address _token, uint256 _amount) external {
    if (targetToken == address(0)) {
      return; // a No-op if target pool is not set yet
    }
    if (_token == targetToken) {
      // Send the tokens to the profitsharing pool.
      IERC20(_token).safeTransferFrom(msg.sender, profitSharingPool, _amount);
    } else {
      // Transfer `_token` to the contract.
      IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);

      // Calculate fee split.
      uint256 tokenBalance = IERC20(_token).balanceOf(address(this));
      uint256 forFund = tokenBalance.mul(fundNumerator).div(10000);
      uint256 balanceToSwap = tokenBalance.sub(forFund);

      // Send a % of fees to the protocol fund.
      address pfund = protocolFund;
      if(pfund != address(0)) {
        IERC20(_token).safeTransfer(pfund, tokenBalance);
      }

      // Convert the remaining fees.
      address[] memory routeToTarget = routes[_token][targetToken];
      if (routeToTarget.length > 1) {
        address swapRouter = targetRouter[_token][targetToken];
        address[] memory swapRouters;

        bool crossSwapEnabled;

        if(swapRouter == address(0)) {
          swapRouters = targetRouters[_token][targetToken];
          crossSwapEnabled = true;
        }

        uint256 endAmount;
        if(crossSwapEnabled) {
          endAmount = _crossSwap(swapRouters, _token, balanceToSwap, routeToTarget);
        } else {
          endAmount = _swap(swapRouter, _token, balanceToSwap, routeToTarget);
        }

        // Now we can send this token forward.
        IERC20(targetToken).safeTransfer(profitSharingPool, endAmount);
      }
      // Else the route does not exist for this token
      // do not take any fees - leave them in the controller
    }
  }
}
