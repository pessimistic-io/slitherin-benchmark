// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IPositionManager} from "./IPositionManager.sol";
import {ERC20} from "./ERC20.sol";
import {PhvToken} from "./PhvToken.sol";
import {PositionManagerStats} from "./PositionManagerStats.sol";
import {VaultStats} from "./VaultStats.sol";
import "./Test.sol";

struct VaultInfo {
  IPositionManager[] positionManagers;
  uint256 usdcLiquidity;
}

struct RebalanceQueueData {
  IPositionManager positionManager;
  uint256 usdcAmountToHave;
} 

import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./OwnableUpgradeable.sol";

contract ProtohedgeVault is Initializable, UUPSUpgradeable, OwnableUpgradeable {
  string public vaultName; 
  ERC20 private usdcToken;
  PhvToken private phvToken;

  IPositionManager[] public positionManagers;

  event GasPrice(uint256 price);

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

  function rebalance(RebalanceQueueData[] memory rebalanceQueueData) external returns (uint256) {
    uint256 initGas = gasleft();
    for (uint8 i = 0; i < rebalanceQueueData.length; i++) {
      if (!rebalanceQueueData[i].positionManager.canRebalance()) {
        revert("Position manager cannot rebalance");
      }
      rebalanceQueueData[i].positionManager.rebalance(rebalanceQueueData[i].usdcAmountToHave);
    }

    emit GasPrice(initGas - gasleft());
    emit GasPrice(tx.gasprice);
  }

  function stats() external view returns (VaultStats memory) {
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

  function getPositionManagers() external view returns (IPositionManager[] memory) {
    return positionManagers;
  }

  function setPositionManagers(IPositionManager[] memory _positionManagers) external {
    positionManagers = _positionManagers;

    for (uint256 index = 0; index < _positionManagers.length; index++) {
      usdcToken.approve(address(positionManagers[index]), 9999999999999999999999999);
    }
  }
}

