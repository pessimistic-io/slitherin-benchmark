// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;
import "./AlgoTradingStorage.sol";

interface IAlgoTradeManager {
    function init(address[] memory, address, uint256, uint256) external;

    function fundDeploy(
        string memory _fundName,
        string memory _fundSymbol,
        bytes memory _feeManagerConfigData,
        bytes memory _policyManagerConfigData,
        uint256 _amount,
        AlgoTradingStorage.ExtensionArgs[] memory _swapArgs,
        AlgoTradingStorage.ExtensionArgs[] memory _positionArgs,
        address[] memory _followingTraders
        // bytes memory _gelatoFeeData
    ) external;

    // function setTraderConfigData(
    //     AlgoTradingStorage.MasterTraderConfig memory traderConfigData
    // ) external;

    // function setGelatoTaskFee(uint256) external;

    function vaultProxy() external view returns (address);

    function getPolicyManager() external returns (address);

    function strategyCreator() external returns (address);

    function shouldFollow(address, address, address) external returns (bool);

    function shouldStartCopy(address, bytes memory) external returns (bool);

    function getFundManagerFactory() external view returns (address);

    function followedTrader() external view returns (address);

    // function isFollowedTrader(address) external view returns (bool);

    function getTraderPositionInfo(
        address,
        bytes32
    ) external view returns (AlgoTradingStorage.PositionInfo memory);
}

