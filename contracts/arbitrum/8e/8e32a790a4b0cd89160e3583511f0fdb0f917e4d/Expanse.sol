// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./IPool.sol";
import "./Ownable.sol";
import "./IUniswapV3Pool.sol";
import "./IUniswapV3Factory.sol";
import "./ISwapRouter.sol";
import "./FullMath.sol";

import "./IExpanse.sol";
import "./IManager.sol";
import "./IERC20Minimal.sol";
import "./TransferLibrary.sol";

// Uncomment this line to use console.log
//import "hardhat/console.sol";

contract Expanse is IExpanse, IManager, Ownable {
  address public constant FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
  address public constant AAVE_POOL = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;
  address public constant SWAP_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
  address public constant WBTC = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;
  address public constant USDCE = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
  uint24 public constant FEE = 500;

  uint128 private constant MAX_UINT_128 = type(uint128).max;
  mapping(address => Position) private clientPositions;
  mapping(address => Position[]) private clientPositionsHistory;
  mapping(address => uint256) private positionsTotalBalances;
  uint256 private leverage = 125; //25%
  uint256 private interestRateMode = 1;
  uint256 private totalCollateral;

  constructor(address owner) {
    _transferOwnership(owner);
    _addManager(owner);
  }

  /// @notice Change leverage ratio
  /// @param _newLeverage The new leverage ratio
  function changeLeverage(uint256 _newLeverage) external override onlyOwner {
    leverage = _newLeverage;
  }

  /// @notice Get leverage ratio
  /// @return leverage The current leverage ratio
  function getLeverage() public view returns (uint256) {
    return leverage;
  }

  /// @notice Change interest Rate Mode for AAVE
  /// @param _newInterestRateMode The new interest Rate Mode
  function changeInterestRateMode(uint256 _newInterestRateMode) external override onlyOwner {
    interestRateMode = _newInterestRateMode;
  }

  /// @notice Get interest Rate Mode
  /// @return interestRateMode The current interest Rate Mode
  function getInterestRateMode() public view returns (uint256) {
    return interestRateMode;
  }

  /// @notice Add a new manager address
  /// @param _manager The address of the new manager
  function addManager(address _manager) external override onlyOwner {
    _addManager(_manager);
  }

  /// @notice Remove a manager address
  /// @param _manager The address of the manager to remove
  function removeManager(address _manager) external override onlyOwner {
    _removeManager(_manager);
  }

  /// @notice Get current price of WBTC on Uniswap
  /// @return price in USDCE without decimals
  function calculateWBTCPrice() public view returns (uint256 price) {
    address poolAddress = IUniswapV3Factory(FACTORY).getPool(WBTC, USDCE, FEE);
    (uint160 sqrtPriceX96, , , , , , ) = IUniswapV3Pool(poolAddress).slot0();
    uint256 numerator1 = uint256(sqrtPriceX96) * uint256(sqrtPriceX96);
    uint256 numerator2 = 10e8;
    price = (FullMath.mulDiv(numerator1, numerator2, 1 << 192)) / 10e6;
  }

  /// @notice Create new client position
  /// @param clientUUID The identifier of client
  /// @param wbtcAmount The amount of WBTC in position
  /// @param usdceAmount The amount of USDCE in position
  function newPosition(
    address clientUUID,
    uint256 wbtcAmount,
    uint256 usdceAmount
  ) public override onlyManager {
    require(clientUUID != address(0), "Invalid clientUUID");

    if (clientPositions[clientUUID].entryPrice > 0) {
      require(clientPositions[clientUUID].state == State.Closed, "Position still opened");
    }

    if (wbtcAmount > clientPositions[clientUUID].WBTC)
      _safeAddTokens(WBTC, wbtcAmount - clientPositions[clientUUID].WBTC);
    if (usdceAmount > clientPositions[clientUUID].USDCE)
      _safeAddTokens(USDCE, usdceAmount - clientPositions[clientUUID].USDCE);

    Position memory newClientPosition = Position(
      State.Purchased,
      wbtcAmount,
      usdceAmount,
      0,
      0,
      0,
      0,
      0
    );
    clientPositions[clientUUID] = newClientPosition;
    emit PositionCreated(clientUUID);
  }

  /// @notice Change client position
  /// @param clientUUID The identifier of client
  /// @param state The state of position
  /// @param wbtcAmount The amount of WBTC in position
  /// @param usdceAmount The amount of USDCE in position
  /// @param entryPrice The entry price of WBTC token
  function changePosition(
    address clientUUID,
    State state,
    uint256 wbtcAmount,
    uint256 usdceAmount,
    uint256 entryPrice
  ) public override onlyOwner {
    require(clientUUID != address(0), "Invalid clientUUID");

    clientPositions[clientUUID].WBTC = wbtcAmount;
    clientPositions[clientUUID].USDCE = usdceAmount;
    clientPositions[clientUUID].entryPrice = entryPrice;
    clientPositions[clientUUID].state = state;

    emit PositionChanged(clientUUID);
  }

  /// @notice Get all client positions
  /// @param clientUUID The identifier of client
  /// @return Info about selected client position
  function getPosition(address clientUUID) public view override returns (PositionInfo memory) {
    Position memory position = clientPositions[clientUUID];
    uint256 currentLTV = position.debt == 0
      ? 0
      : (position.debt * 1e4) / ((position.collateral) * calculateWBTCPrice());
    return
      PositionInfo(
        position.state,
        position.WBTC,
        position.USDCE,
        position.collateral,
        position.debt,
        position.entryAmount,
        position.entryPrice,
        position.averagePrice,
        currentLTV
      );
  }

  /// @notice Get all client positions
  /// @param clientUUID The identifier of client
  /// @return Array of client positions
  function getPositionsHistory(
    address clientUUID
  ) public view override returns (Position[] memory) {
    require(clientUUID != address(0), "Invalid clientUUID");
    return clientPositionsHistory[clientUUID];
  }

  /// @notice Function that swaps WBTC tokens to exact amount of USDCE
  /// @param clientUUIDs  Array of client identifiers
  /// @param amounts Array of clients amounts of token
  function swapWBTCtoUSDCE(
    address[] memory clientUUIDs,
    uint256[] memory amounts
  ) public override onlyManager {
    _checkArrays(clientUUIDs, amounts);

    uint256 totalAmount;
    for (uint i = 0; i < amounts.length; i++) {
      _safeSubClientWBTC(clientUUIDs[i], amounts[i]);
      totalAmount += amounts[i];
    }
    _safeApprove(WBTC, SWAP_ROUTER, totalAmount);

    uint256 amountOutUSDCE = _swap(WBTC, USDCE, FEE, totalAmount);
    _safeSubTokens(WBTC, totalAmount);

    // Distribute USDCE to users according to their shares
    for (uint i = 0; i < clientUUIDs.length; i++) {
      clientPositions[clientUUIDs[i]].USDCE +=
        (amountOutUSDCE * ((amounts[i] * 1e18) / totalAmount)) /
        1e18;
    }
    _safeAddTokens(USDCE, amountOutUSDCE);
    emit SwappedToUSDCE(clientUUIDs);
  }

  /// @notice Function that swaps USDCE tokens to exact amount of WBTC
  /// @param clientUUIDs  Array of client identifiers
  /// @param amounts Array of clients amounts of token
  function swapUSDCEtoWBTC(
    address[] memory clientUUIDs,
    uint256[] memory amounts
  ) public override onlyManager {
    _checkArrays(clientUUIDs, amounts);

    uint256 totalAmount;
    for (uint i = 0; i < amounts.length; i++) {
      _safeSubClientUSDCE(clientUUIDs[i], amounts[i]);
      totalAmount += amounts[i];
    }
    _safeApprove(USDCE, SWAP_ROUTER, totalAmount);

    uint256 amountOutWBTC = _swap(USDCE, WBTC, FEE, totalAmount);
    _safeSubTokens(USDCE, totalAmount);

    // Distribute WBTC to users according to their shares
    for (uint i = 0; i < clientUUIDs.length; i++) {
      clientPositions[clientUUIDs[i]].WBTC +=
        (amountOutWBTC * ((amounts[i] * 1e18) / totalAmount)) /
        1e18;
      if (
        clientPositions[clientUUIDs[i]].entryAmount > 0 &&
        clientPositions[clientUUIDs[i]].entryAmount * leverage <=
        (clientPositions[clientUUIDs[i]].WBTC + clientPositions[clientUUIDs[i]].collateral) * 100
      ) {
        clientPositions[clientUUIDs[i]].state = State.Levered;
      }
    }
    _safeAddTokens(WBTC, amountOutWBTC);
    emit SwappedToWBTC(clientUUIDs);
  }

  /// @notice Function that supply WBTC tokens to AAVE pool and set it as collateral
  /// @param clientUUIDs  Array of client identifiers
  /// @param amounts Array of clients amounts of token
  function supplyWBTCLiquidity(
    address[] memory clientUUIDs,
    uint256[] memory amounts
  ) public override onlyManager {
    _checkArrays(clientUUIDs, amounts);
    IPool pool = IPool(AAVE_POOL);

    uint256 totalAmount;
    for (uint i = 0; i < amounts.length; i++) {
      _safeSubClientWBTC(clientUUIDs[i], amounts[i]);
      totalAmount += amounts[i];
    }
    _safeApprove(WBTC, AAVE_POOL, totalAmount);

    (uint256 totalCollateralBaseBefore, , , , , ) = pool.getUserAccountData(address(this));
    pool.supply(WBTC, totalAmount, address(this), 0);
    pool.setUserUseReserveAsCollateral(WBTC, true);
    (uint256 totalCollateralBaseAfter, , , , , ) = pool.getUserAccountData(address(this));
    uint256 collateralBaseAmount = totalCollateralBaseAfter - totalCollateralBaseBefore;
    uint256 price = collateralBaseAmount / totalAmount;

    // Distribute available borrows to users according to their shares
    for (uint i = 0; i < clientUUIDs.length; i++) {
      if (
        clientPositions[clientUUIDs[i]].entryAmount == 0 &&
        clientPositions[clientUUIDs[i]].state == State.Purchased
      ) {
        clientPositions[clientUUIDs[i]].entryAmount = amounts[i];
        clientPositions[clientUUIDs[i]].entryPrice = price;
        clientPositions[clientUUIDs[i]].state = State.Collateralized;
        clientPositions[clientUUIDs[i]].averagePrice = price;
      } else {
        clientPositions[clientUUIDs[i]].averagePrice =
          (clientPositions[clientUUIDs[i]].averagePrice *
            clientPositions[clientUUIDs[i]].collateral +
            amounts[i] *
            price) /
          (clientPositions[clientUUIDs[i]].collateral + amounts[i]);
      }
      clientPositions[clientUUIDs[i]].collateral += amounts[i];
    }
    totalCollateral += totalAmount;
    _safeSubTokens(WBTC, totalAmount);
    emit Collateralized(clientUUIDs);
  }

  /// @notice Function that withdraw WBTC tokens from AAVE pool for provided clients
  /// @param clientUUIDs  Array of client identifiers
  /// @param amounts Array of clients amounts
  function withdrawWBTCLiquidity(
    address[] memory clientUUIDs,
    uint256[] memory amounts
  ) public override onlyManager {
    _checkArrays(clientUUIDs, amounts);

    (, , uint256 availableBorrowsBase, , , ) = IPool(AAVE_POOL).getUserAccountData(address(this));
    uint256 totalAmount;
    for (uint i = 0; i < amounts.length; i++) {
      _checkDebt(clientUUIDs[i], availableBorrowsBase);
      clientPositions[clientUUIDs[i]].WBTC += amounts[i];
      _safeSubClientCollateral(clientUUIDs[i], amounts[i]);
      totalAmount += amounts[i];
    }
    IPool(AAVE_POOL).withdraw(WBTC, totalAmount, address(this));
    totalCollateral -= totalAmount;

    for (uint i = 0; i < clientUUIDs.length; i++) {
      if (clientPositions[clientUUIDs[i]].collateral == 0) {
        clientPositions[clientUUIDs[i]].state = State.Closed;
        clientPositionsHistory[clientUUIDs[i]].push(clientPositions[clientUUIDs[i]]);
      }
    }
    _safeAddTokens(WBTC, totalAmount);
    emit LiquidityWithdrew(clientUUIDs);
  }

  /// @notice Function that borrow USDCE tokens from AAVE pool for provided clients
  /// @param clientUUIDs  Array of client identifiers
  /// @param amounts Array of clients amounts
  function borrowUSDCE(
    address[] memory clientUUIDs,
    uint256[] memory amounts
  ) public override onlyManager {
    _checkArrays(clientUUIDs, amounts);
    (, , uint256 availableBorrowsBase, , , ) = IPool(AAVE_POOL).getUserAccountData(address(this));

    uint256 totalAmount;
    for (uint i = 0; i < amounts.length; i++) {
      clientPositions[clientUUIDs[i]].USDCE += amounts[i];
      clientPositions[clientUUIDs[i]].debt += amounts[i];
      _checkDebt(clientUUIDs[i], availableBorrowsBase);
      totalAmount += amounts[i];
    }
    IPool(AAVE_POOL).borrow(USDCE, totalAmount, interestRateMode, 0, address(this));
    _safeAddTokens(USDCE, totalAmount);
    emit Borrowed(clientUUIDs);
  }

  /// @notice Function that repay USDCE tokens to AAVE pool for provided clients
  /// @param clientUUIDs  Array of client identifiers
  /// @param amounts Array of clients amounts
  function repayUSDCE(
    address[] memory clientUUIDs,
    uint256[] memory amounts
  ) public override onlyManager {
    _checkArrays(clientUUIDs, amounts);
    uint256 totalAmount;
    for (uint i = 0; i < amounts.length; i++) {
      _safeSubClientUSDCE(clientUUIDs[i], amounts[i]);
      _safeSubClientDebt(clientUUIDs[i], amounts[i]);
      totalAmount += amounts[i];
    }
    _safeApprove(USDCE, AAVE_POOL, totalAmount);
    IPool(AAVE_POOL).repay(USDCE, totalAmount, interestRateMode, address(this));
    _safeSubTokens(USDCE, totalAmount);
    emit Repaid(clientUUIDs);
  }

  /// @notice Get AAVE account data for entire contract collateral/borrow rates
  function getAAVEInfo()
    public
    view
    override
    returns (
      uint256 totalCollateralBase,
      uint256 totalDebtBase,
      uint256 availableBorrowsBase,
      uint256 liquidationThreshold,
      uint256 currentLtv,
      uint256 healthFactor,
      uint256 totalContractCollateral
    )
  {
    (uint256 tc, uint256 td, uint256 ab, uint256 lth, uint256 ltv, uint256 hf) = IPool(AAVE_POOL)
      .getUserAccountData(address(this));
    totalCollateralBase = tc / 1e2;
    totalDebtBase = td / 1e2;
    availableBorrowsBase = ab / 1e2;
    liquidationThreshold = lth;
    currentLtv = ltv;
    healthFactor = hf;
    totalContractCollateral = totalCollateral;
  }

  /// @notice Withdraw ETH from the contract to the owner address
  /// @param amount The amount to withdraw
  function withdrawETH(uint256 amount) public override onlyOwner {
    TransferLibrary.safeTransferETH(owner(), amount);
  }

  /// @notice Withdraw tokens from the contract to owner
  /// @param token The token to withdraw
  /// @param amount The amount to withdraw
  function withdraw(address token, uint256 amount) public override onlyOwner {
    TransferLibrary.safeTransfer(IERC20Minimal(token), owner(), amount);
    _safeSubTokens(token, amount);
  }

  /// @notice _swap internal function that  swaps amountIn tokens to exact amountOut
  /// @param tokenIn  Input token address to swap
  /// @param tokenOut  Output token address to swap
  /// @param poolFee  pool swap fees
  /// @param amountIn  fixed amount of token input DAI or WETH
  /// @return _amountOut maximum possible output of WET or DAI received
  function _swap(
    address tokenIn,
    address tokenOut,
    uint24 poolFee,
    uint256 amountIn
  ) internal returns (uint _amountOut) {
    ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
      tokenIn: tokenIn,
      tokenOut: tokenOut,
      fee: poolFee,
      recipient: address(this),
      deadline: block.timestamp,
      amountIn: amountIn,
      amountOutMinimum: 0,
      sqrtPriceLimitX96: 0
    });

    _amountOut = ISwapRouter(SWAP_ROUTER).exactInputSingle(params);
  }

  /// @notice _safeAddTokens internal function that checks balances before change contract values
  /// @param token Address of token to change
  /// @param amount Token amount to change
  function _safeAddTokens(address token, uint256 amount) internal {
    require(
      IERC20Minimal(token).balanceOf(address(this)) >= positionsTotalBalances[token] + amount,
      "Incorrect token amount on add"
    );
    positionsTotalBalances[token] += amount;
  }

  /// @notice _safeSubTokens internal function that checks balances before change contract values
  /// @param token Address of token to change
  /// @param amount Token amount to change
  function _safeSubTokens(address token, uint256 amount) internal {
    require(
      IERC20Minimal(token).balanceOf(address(this)) >= positionsTotalBalances[token] - amount,
      "Incorrect token amount on sub"
    );
    positionsTotalBalances[token] -= amount;
  }

  /// @notice _safeSubClientWBTC internal function that sub client WBTC on position
  /// @param amount Token amount to change
  function _safeSubClientWBTC(address clientUUID, uint256 amount) internal {
    require(clientPositions[clientUUID].WBTC >= amount, "Not enough tokens");
    clientPositions[clientUUID].WBTC -= amount;
  }

  /// @notice _safeSubClientUSDCE internal function that sub client USDCE on position
  /// @param amount Token amount to change
  function _safeSubClientUSDCE(address clientUUID, uint256 amount) internal {
    require(clientPositions[clientUUID].USDCE >= amount, "Not enough tokens");
    clientPositions[clientUUID].USDCE -= amount;
  }

  /// @notice _safeSubClientWBTC internal function that sub client USDCE on position
  /// @param amount Token amount to change
  function _safeSubClientDebt(address clientUUID, uint256 amount) internal {
    if (clientPositions[clientUUID].debt < amount) {
      clientPositions[clientUUID].debt = 0;
    } else {
      clientPositions[clientUUID].debt -= amount;
    }
  }

  /// @notice _safeSubClientWBTC internal function that sub client available borrow on position
  /// @param amount Token amount to change
  function _safeSubClientCollateral(address clientUUID, uint256 amount) internal {
    require(clientPositions[clientUUID].collateral >= amount, "Not enough collateral");
    clientPositions[clientUUID].collateral -= amount;
  }

  function _safeApprove(address token, address spender, uint256 amount) internal {
    uint allowance = IERC20Minimal(token).allowance(address(this), spender);
    if (allowance < amount) {
      IERC20Minimal(token).approve(spender, MAX_UINT_128);
    }
  }

  function _checkArrays(address[] memory a1, uint256[] memory a2) internal pure {
    require(a1.length == a2.length, "Arrays not equal");
    require(a1.length > 0, "Arrays are empty");
  }

  function _checkDebt(address clientUUID, uint256 availableBorrowsBase) internal view {
    require(
      clientPositions[clientUUID].debt <=
        (availableBorrowsBase / totalCollateral) * clientPositions[clientUUID].collateral,
      "Client debt more than collateral"
    );
  }
}

