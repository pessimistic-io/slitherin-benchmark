pragma solidity ^0.8.12;

import "./ICompetition.sol";
import "./DataTypes.sol";
import "./IERC20.sol";

interface IModeler {
    function initialize(
        address _competitionContract,
        IERC20 _validatorToken,
        uint256 _validatorStakeAmount,
        uint256 _maxValidators
    ) external;

    function registerValidator() external;

    function setNextRandSlot(address _modeler, uint256 _futureRandSlot) external;

    function setIPFSDataSet(string calldata _ipfsTestingDataset) external;

    function registerModeler(
        address _modeler,
        string calldata _modelCommitment,
        uint256 _stakedAmount
    ) external;

    function updateModel(string calldata _modelCommitment) external;

    function giveChallengeToModeler(
        string calldata _ipfsChallenge,
        address _modeler,
        DataTypes.DrandProof memory _proof
    ) external;

    function respondToChallenge(address _validator, string calldata _ipfsResponse) external;

    function postGraded(
        address modeler,
        string calldata _ipfsGraded,
        uint256 _performanceResult,
        string calldata _ipfsGradeDetailLink
    ) external;

    function setModelerNetPerformanceResultAndUpdate(address modeler) external;

    function ZKMLChallengeModeler(
        address modeler,
        string calldata _ipfsChallenge,
        DataTypes.DrandProof memory _proof
    ) external;

    function respondToZKMLChallenge(address _validator, string calldata _ipfsResponse) external;

    function replaceOptOutTopNModeler(
        uint256 oldModelerIndex,
        address oldModeler,
        address modeler
    ) external;

    function optOutModeler() external;

    function kickModeler(address modeler) external;

    function optInModeler() external;

    function emergencyOptOutValidator(address _validator) external;

    function optOutValidator() external;

    function optInValidator() external;

    //function allValidators() external view returns (address[] memory);

    function isValidator(address _validator) external view returns (bool);

    //function isModeler(address _modeler) external view returns (bool);

    function addStakeToModeler(uint256 amount) external;

    function addStakeToValidator(uint256 amount) external;

    //function getModeler(address _modeler) external view returns (DataTypes.ModelerData memory);

    //function modelers(address) external view returns (DataTypes.ModelerData memory);
    
}
