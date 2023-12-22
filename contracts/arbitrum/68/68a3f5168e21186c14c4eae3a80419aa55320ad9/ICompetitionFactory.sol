pragma solidity ^0.8.12;

import "./DataTypes.sol";
import "./ICompetition.sol";
import "./IModeler.sol";
import "./IERC20.sol";

interface ICompetitionFactory {
    function initialize(ICompetition _competitionLogic, IModeler _modelerLogic) external;
    
    function deployCompetition(
        address _admin,
        string calldata _ipfsCompetition, 
        uint256 _topNParameter
    ) external returns (ICompetition);
    
    function deployModeler(
        address _competitionContract,
        IERC20 _validatorToken,
        uint256 _validatorStakeAmount,
        uint256 _maxValidators
    ) external returns (IModeler);
    
    function upgradeCompetition(ICompetition newCompetition) external;
    function upgradeModelerContract(IModeler newModelerContract) external;
    function allCompetitionsLength() external view returns (uint256);
    function getAllCompetitions() external view returns (ICompetition[] memory);
    function allModelersContractsLength() external view returns (uint256);
    function getAllModelersContracts() external view returns (IModeler[] memory);
    function setNewAdmin(address _newAdmin) external;
}
