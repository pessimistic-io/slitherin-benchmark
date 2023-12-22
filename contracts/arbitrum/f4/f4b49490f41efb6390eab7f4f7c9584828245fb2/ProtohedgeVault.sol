// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IPositionManager} from "./IPositionManager.sol";
import {ERC20} from "./ERC20.sol";
import {PhvToken} from "./PhvToken.sol";
import {PositionManagerStats} from "./PositionManagerStats.sol";
import {VaultStats} from "./VaultStats.sol";
import {PriceUtils} from "./PriceUtils.sol";

import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./OwnableUpgradeable.sol";

uint256 constant GAS_PRICE_DIVISOR = 1*10**20;

struct VaultInfo {
  IPositionManager[] positionManagers;
  uint256 usdcLiquidity;
}

struct RebalanceQueueData {
  IPositionManager positionManager;
  uint256 usdcAmountToHave;
} 

contract ProtohedgeVault is Initializable, UUPSUpgradeable, OwnableUpgradeable {
  string public vaultName; 
  ERC20 private usdcToken;
  PhvToken private phvToken;
  IPositionManager[] public positionManagers;
  PriceUtils private priceUtils; 
  address private ethPriceFeedAddress;
  uint256 private gasCostPayed;

  function initialize(string memory _vaultName, address _usdcAddress) public initializer {
    vaultName = _vaultName;
    usdcToken = ERC20(_usdcAddress);
    phvToken = new PhvToken();

    __Ownable_init();
  }

  function _authorizeUpgrade(address) internal override onlyOwner {}

  function vaultWorth() public view returns (uint256) {
    uint256 totalLiquidity = this.getAvailableLiquidity(); 

    for (uint256 i = 0; i < positionManagers.length; i++) {
      totalLiquidity += positionManagers[i].positionWorth();
    }

    return totalLiquidity; 
  }

  function getAvailableLiquidity() public view returns (uint256) {
    return usdcToken.balanceOf(address(this));
  }

  function addLiquidity(uint256 usdcAmount) external {
    usdcToken.transferFrom(msg.sender, address(this), usdcAmount);
    phvToken.mint(msg.sender, usdcAmount);
  }

  function removeLiquidity(uint256 phvTokenToBurn) external {
    phvToken.burn(msg.sender, phvTokenToBurn);
    uint256 percentOfPool = phvTokenToBurn / phvToken.totalSupply();
    uint256 amountOfUsdc = vaultWorth() * percentOfPool;
    require(amountOfUsdc <= getAvailableLiquidity(), "Not able to withdraw liquidity.");
    usdcToken.transfer(address(this), amountOfUsdc);
  }

  function rebalance(RebalanceQueueData[] memory rebalanceQueueData) external {
    uint256 initGas = gasleft();
    for (uint8 i = 0; i < rebalanceQueueData.length; i++) {
      if (!rebalanceQueueData[i].positionManager.canRebalance()) {
        revert("Position manager cannot rebalance");
      }
      rebalanceQueueData[i].positionManager.rebalance(rebalanceQueueData[i].usdcAmountToHave);
    }

    uint256 gasCost = estimateGasCost(initGas);
    gasCostPayed += gasCost;
  }

  function stats() public view returns (VaultStats memory) {
    PositionManagerStats[] memory positionManagersStats = new PositionManagerStats[](positionManagers.length);

    for (uint256 i = 0; i < positionManagersStats.length; i++) {
      positionManagersStats[i] = positionManagers[i].stats();
    }

    return VaultStats({
      vaultAddress: address(this),
      positionManagers: positionManagersStats, 
      vaultWorth: vaultWorth(),
      availableLiquidity: getAvailableLiquidity()
    });
  }

  function getPositionManagers() public view returns (IPositionManager[] memory) {
    return positionManagers;
  }

  function setPositionManagers(IPositionManager[] memory _positionManagers) external {
    positionManagers = _positionManagers;

    for (uint256 index = 0; index < _positionManagers.length; index++) {
      usdcToken.approve(address(positionManagers[index]), 9999999999999999999999999);
    }
  }

  function vaultCostBasis() public view returns (uint256) {
    uint256 costBasis = gasCostPayed;
    for (uint256 i = 0; i < positionManagers.length; i++) {
      costBasis += positionManagers[i].costBasis();
    }

    return costBasis; 
  }

  function estimateGasCost(uint256 initialGasLeft) public view returns (uint256) {
    uint256 gasPrice = tx.gasprice;
    uint256 ethPrice = priceUtils.getTokenPrice(ethPriceFeedAddress);
    return gasPrice * ethPrice * (initialGasLeft - gasleft()) / GAS_PRICE_DIVISOR; 
  }

  function setPriceUtils(address priceUtilsAddress) external {
    priceUtils = PriceUtils(priceUtilsAddress); 
  }

  function setEthPriceFeedAddress(address _ethPriceFeedAddress) external {
    ethPriceFeedAddress = _ethPriceFeedAddress;
  }
}

