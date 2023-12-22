// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "./IERC20.sol";
import "./IModeler.sol";
import "./IConsumption.sol";
import "./IServiceAgreement.sol";
import "./DataTypes.sol";
import "./ServiceAgreement.sol";

interface ICompetition {
    function initialize(
        address _admin,
        string memory _ipfsCompetition,
        uint256 _topNParameter
    ) external;

    function signUpToCompetition(string calldata _modelHash) external;
    function setModelerNetPerformanceResultAndUpdate(address modeler, uint256 medianPerformanceResults) external;
    function replaceOptOutTopNModeler(uint256 _oldModelerIndex, address _newModeler, uint256 _medianPerformanceResults) external;
    function setModelerContract(IModeler _modelerContract) external;
    function setConsumptionContract(IConsumption _consumptionContract) external;
    function setIPFSCompetitionDescriptionHash(string calldata _ipfsCompetition) external;
    function setIPFSTrainingDataSet(string calldata _ipfsTrainingDataset) external;
    function isTopNModeler(address _modeler) external view returns (bool);
    function setServiceAgreementContract(IServiceAgreement _agreement) external;
    function getTopNModelers() external view returns (address[] memory);
    function getTopNModelersLength() external view returns (uint256);
    function getModelerToMedian(address _modeler) external view returns (uint256);
    function getSAParams() external view returns (DataTypes.SAParams memory);
    function emergencyOptOutValidator(address _validator) external;
    function setAdmin(address _newAdmin) external;
    function admin() external view returns (address);
    function modelerToMedian(address) external view returns (uint256);
    function modelerContract() external view returns (IModeler);
    function consumptionContract() external view returns (address);
    function ipfsCompetition() external view returns (string memory);
    function topNParameter() external view returns (uint256);
    function topNModelers(uint) external view returns (address);
    function serviceAgreement() external view returns (IServiceAgreement);
    function getServiceAgreement() external view returns (IServiceAgreement);
    function ipfsTrainingDataset() external view returns (string memory);

}
