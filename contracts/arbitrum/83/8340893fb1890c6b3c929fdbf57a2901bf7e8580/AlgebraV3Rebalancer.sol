pragma solidity ^0.8.0;

import "./IStrategyRebalanceStakerAlgebra.sol";
import "./IAlgebraV3Rebalancer.sol";
import "./OwnableUpgradeable.sol";
import "./IERC20.sol";

contract AlgebraV3Rebalancer is OwnableUpgradeable, IAlgebraV3Rebalancer {
  address[] public dysonPools;
  mapping(address => bool) public uniPoolCheck;
  mapping(address => bool) public harvesters;

  // **** Modifiers **** //

  modifier onlyBenevolent() {
    require(harvesters[msg.sender] || msg.sender == owner());
    _;
  }

  function initialize() public initializer {
    __Ownable_init();
  }

  /**
   * @notice  Rebalances all pools, if condition applies
   *          if no pool is to be re-balanced, send revert
   *          to save gas of the execution
   * @dev     Simsala
   */
  function rebalancePools() public onlyBenevolent {
    uint256 k;
    for (uint256 i = 0; i < dysonPools.length; i++) {
      IStrategyRebalanceStakerAlgebra dysonStrategy = IStrategyRebalanceStakerAlgebra(dysonPools[i]);

      if (!dysonStrategy.inRangeCalc()) {
        dysonStrategy.rebalance();
        k++;
      }
    }

    require(k > 0, "no pools to re-balance");
  }

  /**
   * @notice Harvests all Dyson pools that haven't been harvested in the past day
   *
   * @dev This function iterates through all the Dyson pools and calls the `harvest` function
   * on each of them if it hasn't been called in the past day.
   */
  function harvest() public onlyBenevolent {
    uint256 k;
    for (uint256 i = 0; i < dysonPools.length; i++) {
      IStrategyRebalanceStakerAlgebra dysonStrategy = IStrategyRebalanceStakerAlgebra(dysonPools[i]);

      if (block.timestamp > dysonStrategy.lastHarvest() + 24 hours) {
        dysonStrategy.harvest();
        k++;
      }
    }

    require(k > 0, "no pools to harvest");
  }

  /**
   * @notice  Recovers Native asset to owner
   * @dev     Simsala
   * @param   _receiver  address that receives native assets
   */
  function clearStuckBalance(address _receiver) external onlyOwner {
    uint256 balance = address(this).balance;
    payable(_receiver).transfer(balance);
    emit ClearStuckBalance(balance, _receiver, block.timestamp);
  }

  /**
   * @notice  returns assets of balance to owner
   * @dev     Simsala
   * @param   tokenAddress  address of ERC-20 to be refunded
   */
  function rescueToken(address tokenAddress) external onlyOwner {
    uint256 tokens = IERC20(tokenAddress).balanceOf(address(this));
    emit RescueToken(tokenAddress, msg.sender, tokens, block.timestamp);
    IERC20(tokenAddress).transfer(msg.sender, tokens);
  }

  /**
   * @notice  Returns the dyson pool array
   * @dev     Simsala
   * @return  address[]  dyson pool array
   */
  function dysonPoolsCheck() public view returns (address[] memory) {
    return dysonPools;
  }

  // **** Setters **** //

  /**
   * @notice  Whitelist harvesters for autocompounding, governance & strategists are whitelisted by default
   * @param   _harvesters  array of addresses to be whitelisted
   */
  function whitelistHarvesters(address[] calldata _harvesters) external {
    require(msg.sender == owner() || harvesters[msg.sender], "not authorized");

    for (uint256 i = 0; i < _harvesters.length; i++) {
      harvesters[_harvesters[i]] = true;
    }
  }

  /**
   * @notice  Revoke address from harvesting power, governance & strategists can't be turned off
   * @param   _harvesters  array of addresses to not be whitelisted
   */
  function revokeHarvesters(address[] calldata _harvesters) external {
    require(msg.sender == owner(), "not authorized");

    for (uint256 i = 0; i < _harvesters.length; i++) {
      harvesters[_harvesters[i]] = false;
    }
  }

  /**
   * @notice  Add dyson strategy to be checked for
   * @dev     Simsala
   * @param   _dysonPool  Dyson pool
   * @param   _value  if true, adds strategy, if false, remove from loop
   */
  function addDysonStrategy(address _dysonPool, bool _value) external onlyOwner {
    require(uniPoolCheck[_dysonPool] != _value, "Value already set");

    uniPoolCheck[_dysonPool] = _value;

    if (_value) {
      dysonPools.push(_dysonPool);
    } else {
      for (uint256 i = 0; i < dysonPools.length; i++) {
        if (dysonPools[i] == _dysonPool) {
          dysonPools[i] = dysonPools[dysonPools.length - 1];
          dysonPools.pop();
          break;
        }
      }
    }

    emit SetUniContracts(address(_dysonPool), _value);
  }
}

