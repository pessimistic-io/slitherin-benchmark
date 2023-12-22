// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;
// import './Pool.sol';
import "./IPoolSettingsSource.sol";
import "./AccessControl.sol";
import "./Initializable.sol";

contract PoolFactory is AccessControl, IPoolSettingsSource, Initializable {

    IPoolSettingsSource.PoolSettings public poolSettings;

    event PoolSettingsChanged(IPoolSettingsSource.PoolSettings settings);

    function initialize () public initializer {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }
    function setPoolSettings(IPoolSettingsSource.PoolSettings calldata settings) public onlyRole(DEFAULT_ADMIN_ROLE) {
        poolSettings = settings;
        emit PoolSettingsChanged(settings);
    }
    function getPoolSettings() external view returns (IPoolSettingsSource.PoolSettings memory) {
        return poolSettings;
    }

    event PoolCreated(address pool, address manager);
    // function createPool(address referenceTokenA, uint256 initialPriceX96, string memory tokenName, string memory tokenSymbol, uint8 tokenDecimals) public returns (address) {
    //     Pool newPool = new Pool(address(this), referenceTokenA, initialPriceX96, msg.sender, tokenName, tokenSymbol, tokenDecimals);
    //     emit PoolCreated(address(newPool), msg.sender);
    //     return address(newPool);
    // }
}
