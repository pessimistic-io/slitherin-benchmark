pragma solidity ^0.8.12;

import {UpgradeableBeacon} from "./UpgradeableBeacon.sol";
import {BeaconProxy} from "./BeaconProxy.sol";

contract ProxyBeaconDeployer {

    UpgradeableBeacon private competitionBeacon;
    UpgradeableBeacon private modelerBeacon;

    event CompetitionBeaconDeployed(UpgradeableBeacon _beacon);
    event ModelerBeaconDeployed(UpgradeableBeacon _beacon);

    function getCompetitionBeaconAddress() external view returns (address) {
        return address(competitionBeacon);
    }

    function getModelerBeaconAddress() external view returns (address) {
        return address(modelerBeacon);
    }

    function _createCompetitionBeacon(address logic) internal {
        require(address(competitionBeacon) == address(0), "Competition Beacon is already set");
        competitionBeacon = new UpgradeableBeacon(logic);
        emit CompetitionBeaconDeployed(competitionBeacon);
    }

    function _createModelerBeacon(address logic) internal {
        require(address(modelerBeacon) == address(0), "Competition Beacon is already set");
        modelerBeacon = new UpgradeableBeacon(logic);
        emit ModelerBeaconDeployed(modelerBeacon);
    }

    function upgradeCompetitionBeacon(address newLogic) internal {
        competitionBeacon.upgradeTo(newLogic);
    }
    function upgradeModelerBeacon(address newLogic) internal {
        modelerBeacon.upgradeTo(newLogic);
    }    

    function handleBeaconDeployment(address beacon, bytes memory payload) internal returns (address) {
        address payable addr;
        bytes memory _bytecode = type(BeaconProxy).creationCode;
        bytes memory _code = abi.encodePacked(_bytecode, abi.encode(beacon, payload));
        // solhint-disable-next-line no-inline-assembly
        assembly {
            addr := create(0, add(_code, 0x20), mload(_code))
            if iszero(extcodesize(addr)) {
                revert(0, 0)
            }
        }
        BeaconProxy proxy = BeaconProxy(addr);
        return address(proxy);
    }

    function deployCompetitionBeaconProxy(address logic, bytes memory payload) internal returns (address) {
        if (address(competitionBeacon) == address(0)) {
            _createCompetitionBeacon(logic);
        }
        return handleBeaconDeployment(address(competitionBeacon), payload);
    }

    function deployModelerBeaconProxy(address logic, bytes memory payload) internal returns (address) {
        if (address(modelerBeacon) == address(0)) {
            _createModelerBeacon(logic);
        }
        return handleBeaconDeployment(address(modelerBeacon), payload);
    }   
}
