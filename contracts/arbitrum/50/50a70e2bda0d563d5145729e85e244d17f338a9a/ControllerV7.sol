// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "./ERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./safe-math.sol";

import "./IStrategyV2.sol";
import "./IUniswapV3Pool.sol";
import "./IControllerV7.sol";
import "./IConverter.sol";

contract ControllerV7 is IControllerV7, Initializable, ReentrancyGuardUpgradeable {
  using SafeERC20Upgradeable for IERC20Upgradeable;

  address public constant burn = 0x000000000000000000000000000000000000dEaD;

  mapping(address => address) public vaults;
  mapping(address => address) public strategies;
  mapping(address => mapping(address => address)) public converters;
  mapping(address => mapping(address => bool)) public approvedStrategies;
  mapping(Governance => address) public governance;
  string public constant CONTROLLER_TYPE = "Balanced";

  function initialize(
    address _governance,
    address _strategist,
    address _timelock,
    address _devfund,
    address _treasury
  ) public initializer {
    governance[Governance.governance] = _governance;
    governance[Governance.strategist] = _strategist;
    governance[Governance.timelock] = _timelock;
    governance[Governance.devfund] = _devfund;
    governance[Governance.treasury] = _treasury;
  }

  /**
   * @dev Allows the governance of a contract to set its address.
   * @param name Governance name
   * @param _address Address to be set
   */
  function setAddress(Governance name, address _address) public {
    require(msg.sender == governance[Governance.governance], "!governance");
    governance[name] = _address;
  }

  /**
   * @notice Set the address of a strategy for a given pool
   *
   * @param _pool The address of the pool for which to set the strategy
   * @param _address The address of the strategy to set for the pool
   * @param name The type of strategy to set (vault, revoke, approve, removeVault, removeStrategy, or setStrategy)
   *
   * @dev Only the strategist or governance address can call this function
   *
   */
  function setStrategyAddress(
    Strategy name,
    address _pool,
    address _address
  ) public {
    require(
      msg.sender == governance[Governance.strategist] || msg.sender == governance[Governance.governance],
      "!strategist"
    );

    if (name == Strategy.vault) {
      vaults[_pool] = _address;
    } else if (name == Strategy.revoke) {
      require(strategies[_pool] != _address, "cannot revoke active strategy");
      approvedStrategies[_pool][_address] = false;
    } else if (name == Strategy.approve) {
      approvedStrategies[_pool][_address] = true;
    } else if (name == Strategy.removeVault) {
      vaults[_pool] = address(0);
    } else if (name == Strategy.removeStrategy) {
      strategies[_pool] = address(0);
    } else if (name == Strategy.setStrategy) {
      require(approvedStrategies[_pool][_address] == true, "!approved");

      address _current = strategies[_pool];
      if (_current != address(0)) {
        IStrategyV2(_current).withdrawAll();
      }
      strategies[_pool] = _address;
    }
  }

  /**
   * @dev Allows the strategist or governance to withdraw from a strategy pool.
   * @param name Withdrawal type
   * @param _pool Address of the strategy pool
   * @param _amount Amount to be withdrawn
   * @param _token Address of the token to be withdrawn
   * @return Returns the amount of tokens and strategies withdrawn
   */
  function withdrawFunction(
    Withdraw name,
    address _pool,
    uint256 _amount,
    address _token
  ) public returns (uint256, uint256) {
    require(
      msg.sender == governance[Governance.strategist] || msg.sender == governance[Governance.governance],
      "!strategist"
    );
    uint256 a0;
    uint256 a1;

    if (name == Withdraw.withdrawAll) {
      (a0, a1) = IStrategyV2(strategies[_pool]).withdrawAll();
    } else if (name == Withdraw.inCaseTokensGetStuck) {
      IERC20Upgradeable(_token).safeTransfer(msg.sender, _amount);
    } else if (name == Withdraw.inCaseStrategyTokenGetStuck) {
      IStrategyV2(_pool).withdraw(_token);
    } else if (name == Withdraw.withdraw) {
      (a0, a1) = IStrategyV2(strategies[_pool]).withdraw(_amount);
    }
    return (a0, a1);
  }

  /**
   * @dev Gets the upper tick of a strategy pool.
   * @param _pool Address of the strategy pool
   * @return Returns the upper tick value
   */
  function getUpperTick(address _pool) external view returns (int24) {
    return IStrategyV2(strategies[_pool]).tick_upper();
  }

  /**
   * @dev Gets the lower tick of a strategy pool.
   * @param _pool Address of the strategy pool
   * @return Returns the lower tick value
   */
  function getLowerTick(address _pool) external view returns (int24) {
    return IStrategyV2(strategies[_pool]).tick_lower();
  }

  function treasury() external view returns (address) {
    return governance[Governance.treasury];
  }

  function earn(
    address _pool,
    uint256 _token0Amount,
    uint256 _token1Amount
  ) public {
    address _strategy = strategies[_pool];
    address _want = IStrategyV2(_strategy).pool();
    require(_want == _pool, "pool address is different");

    if (_token0Amount > 0) IERC20Upgradeable(IUniswapV3Pool(_pool).token0()).safeTransfer(_strategy, _token0Amount);
    if (_token1Amount > 0) IERC20Upgradeable(IUniswapV3Pool(_pool).token1()).safeTransfer(_strategy, _token1Amount);
    IStrategyV2(_strategy).deposit();
  }

  /**
   * @dev Gets the liquidity of a strategy pool.
   * @param _pool Address of the strategy pool
   * @return Returns the liquidity of the pool
   */
  function liquidityOf(address _pool) external view returns (uint256) {
    return IStrategyV2(strategies[_pool]).liquidityOf();
  }

  function withdraw(address _pool, uint256 _amount) public returns (uint256 a0, uint256 a1) {
    require(msg.sender == vaults[_pool], "!vault");
    (a0, a1) = IStrategyV2(strategies[_pool]).withdraw(_amount);
  }

  function onERC721Received(
    address,
    address,
    uint256,
    bytes memory
  ) public pure returns (bytes4) {
    return this.onERC721Received.selector;
  }
}

