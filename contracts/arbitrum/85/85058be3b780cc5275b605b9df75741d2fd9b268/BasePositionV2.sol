// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "./AddressUpgradeable.sol";

import "./IPriceManager.sol";
import "./PositionConstants.sol";

import "./ISettingsManagerV2.sol";
import "./IPositionHandlerV2.sol";
import "./IPositionKeeperV2.sol";
import "./BaseExecutorV2.sol";

abstract contract BasePositionV2 is PositionConstants, BaseExecutorV2 {
    IPriceManager public priceManager;
    ISettingsManagerV2 public settingsManager;
    IPositionHandlerV2 public positionHandler;
    IPositionKeeperV2 public positionKeeper;
    uint256[50] private __gap;

    function _initialize(
        address _priceManager,
        address _settingsManager,
        address _positionHandler,
        address _positionKeeper
    ) internal {
        super.initialize();
        _baseInitialize(
            _priceManager,
            _settingsManager,
            _positionHandler,
            _positionKeeper
        );
    }
    
    function _baseInitialize(
        address _priceManager,
        address _settingsManager, 
        address _positionHandler,
        address _positionKeeper
    ) internal {
        require(AddressUpgradeable.isContract(_priceManager)
            && AddressUpgradeable.isContract(_settingsManager)
            && AddressUpgradeable.isContract(_positionHandler)
            && AddressUpgradeable.isContract(_positionKeeper), "IVLCA"); //Invalid contract
        priceManager  = IPriceManager(_priceManager);
        settingsManager = ISettingsManagerV2(_settingsManager);
        positionHandler = IPositionHandlerV2(_positionHandler);
        positionKeeper = IPositionKeeperV2(_positionKeeper);
    }

    function _prevalidate(address _indexToken) internal view {
        require(settingsManager.marketOrderEnabled() 
            && settingsManager.isTradable(_indexToken), "SM/PF"); //SettingsManager: Prevalidate failed
    }

    function _getPriceAndCheckFastExecute(address _indexToken) internal view returns (bool, uint256) {
        (uint256 price, , bool isFastExecute) = priceManager.getLatestSynchronizedPrice(_indexToken);
        return (isFastExecute, price);
    }

    function _getPricesAndCheckFastExecute(address[] memory _path) internal view returns (bool, uint256[] memory) {
        require(_path.length >= 1, "IVLPTL"); //Invalid path length
        bool isFastExecute;
        uint256[] memory prices;
        (prices, isFastExecute) = priceManager.getLatestSynchronizedPrices(_path);

        return (isFastExecute, prices);
    }
}
