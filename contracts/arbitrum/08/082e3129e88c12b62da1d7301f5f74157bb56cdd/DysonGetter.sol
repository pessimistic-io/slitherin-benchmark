// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./IUniV3Vault.sol";
import "./IStrategyRebalanceStakerUniV3.sol";
import "./IControllerV7.sol";
import "./IUniswapV3Pool.sol";
import "./erc20.sol";
import "./IUniswapCalculator.sol";
import "./Initializable.sol";
import "./OwnableUpgradeable.sol";

contract DysonGetter is Initializable, OwnableUpgradeable {
  address public uniswapCalculator;

  function initialize(address _uniswapCalculator) public initializer {
    uniswapCalculator = _uniswapCalculator;
  }

  struct UniPoolData {
    address pool;
    address strategyAddress;
    uint lastHarvested;
    bool inRange;
    uint strategyFee;
    uint feeDivisor;
    uint basisPointFee;
    uint token0Amount;
    uint token1Amount;
    int24 upperTick;
    int24 lowerTick;
    int24 innerUpperTick;
    int24 innerLowerTick;
    int24 currentTick;
    UniUserData userData;
    TokenData token0Data;
    TokenData token1Data;
    TokenData depositData;
  }

  struct UniUserData {
    uint256 token0Balance;
    uint256 token0Allowance;
    uint256 token1Balance;
    uint256 token1Allowance;
    uint256 depositBalance;
    uint256 depositAllowance;
  }

  struct TokenData {
    address tokenAddress;
    string symbol;
    string name;
    uint decimals;
  }

  struct UserVaultData {
    string name;
    string symbol;
    uint decimals;
    uint userBalance;
    uint allowance;
  }

  /**
   * @notice  Gets data for all Dyson vaults
   * @param   _dysonUniVaults Array of Dyson vaults
   * @return  UniPoolDatas[] Array of UniPoolData structs
   */
  function getUniPoolDatas(
    IUniV3Vault[] memory _dysonUniVaults,
    address _user
  ) public view returns (UniPoolData[] memory) {
    UniPoolData[] memory uniPoolDatas = new UniPoolData[](_dysonUniVaults.length);
    for (uint256 i = 0; i < _dysonUniVaults.length; i++) {
      uniPoolDatas[i] = getUniPoolData(_dysonUniVaults[i], _user);
    }
    return uniPoolDatas;
  }

  /**
   * @notice  Gets data for a Dyson vault
   * @param   _dysonUniVault address of Dyson vault
   * @return  UniPoolData struct of UniPoolData
   */
  function getUniPoolData(IUniV3Vault _dysonUniVault, address _user) public view returns (UniPoolData memory) {
    UniPoolData memory uniPoolData;
    IUniV3Vault _vault = IUniV3Vault(_dysonUniVault);
    IControllerV7 _controller = IControllerV7(_vault.controller());
    IStrategyRebalanceStakerUniV3 _strategy = IStrategyRebalanceStakerUniV3(_controller.strategies(_vault.pool()));
    IUniswapV3Pool _pool = IUniswapV3Pool(_vault.pool());

    uniPoolData.pool = address(_pool);
    uniPoolData.strategyAddress = address(_strategy);
    uniPoolData.lastHarvested = _strategy.lastHarvest();
    uniPoolData.inRange = _strategy.inRangeCalc();
    uniPoolData.strategyFee = _strategy.performanceTreasuryFee();
    uniPoolData.feeDivisor = _strategy.PERFORMANCE_TREASURY_MAX();
    uniPoolData.basisPointFee = _pool.fee();
    uniPoolData.lowerTick = _strategy.tick_lower();
    uniPoolData.upperTick = _strategy.tick_upper();
    uniPoolData.innerLowerTick = _strategy.inner_tick_lower();
    uniPoolData.innerUpperTick = _strategy.inner_tick_upper();
    (uniPoolData.token0Amount, uniPoolData.token1Amount) = IUniswapCalculator(uniswapCalculator).getLiquidity(
      address(_strategy)
    );
    (, uniPoolData.currentTick, , , , , ) = _pool.slot0();
    uniPoolData.token0Data = _getTokenData(_pool.token0());
    uniPoolData.token1Data = _getTokenData(_pool.token1());
    uniPoolData.depositData = _getTokenData(address(_vault));

    if (_user != address(0x0)) {
      uniPoolData.userData.token0Balance = ERC20(_pool.token0()).balanceOf(_user);
      uniPoolData.userData.token1Balance = ERC20(_pool.token1()).balanceOf(_user);
      uniPoolData.userData.depositBalance = ERC20(address(_vault)).balanceOf(_user);
      uniPoolData.userData.token0Allowance = ERC20(_pool.token0()).allowance(_user, address(_vault));
      uniPoolData.userData.token1Allowance = ERC20(_pool.token1()).allowance(_user, address(_vault));
      uniPoolData.userData.depositAllowance = ERC20(address(_vault)).allowance(_user, address(_vault));
    }

    return uniPoolData;
  }

  /**
   * @notice  Gets data for all Tokens
   * @param   _token address of the token
   **/
  function _getTokenData(address _token) internal view returns (TokenData memory tokenData) {
    tokenData.tokenAddress = _token;
    tokenData.symbol = ERC20(_token).symbol();
    tokenData.name = ERC20(_token).name();
    tokenData.decimals = ERC20(_token).decimals();
    return tokenData;
  }
}

