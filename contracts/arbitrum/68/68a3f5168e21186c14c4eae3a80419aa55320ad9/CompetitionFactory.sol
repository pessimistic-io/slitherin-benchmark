pragma solidity ^0.8.12;

import "./ICompetition.sol";
import "./ICompetitionFactory.sol";
import "./IModeler.sol";
import "./DataTypes.sol";

import {ProxyBeaconDeployer} from "./BeaconProxyDeployer.sol";
import {UUPSUpgradeable} from "./UUPSUpgradeable.sol";
import "./Initializable.sol";
import "./SafeERC20.sol";

contract CompetitionFactory is ICompetitionFactory, Initializable, UUPSUpgradeable, ProxyBeaconDeployer {
    using SafeERC20 for IERC20;
    
    ICompetition private competitionLogic;
    IModeler private modelerLogic; 

    uint256 public version; 
    uint256 public competitionVersion; 
    uint256 public modelerVersion; 

    ICompetition[] public allCompetitions;
    IModeler[] public allModelerContracts;

    event CompetitionCreated(ICompetition competition, uint256 index);
    event CompetitionUpgraded(address indexed upgrader, ICompetition competition);
    event ModelerContractCreated(IModeler modelerContract, uint256 index);
    event ModelerContractUpgraded(address indexed upgrader, IModeler modelerContract);
    event NewAdminSet(address indexed newAdmin);
    
    address public owner; 
    uint256[50] private __gap;

    constructor() {
        owner = msg.sender;
    }

    function initialize(ICompetition _competitionLogic, IModeler _modelerLogic) external initializer {
        require(owner == msg.sender, "Only owner can initialize");
        require(address(_competitionLogic) != address(0), "cannot point to zero address");
        require(address(_modelerLogic) != address(0), "cannot point to zero address");
        __UUPSUpgradeable_init();
        competitionLogic = _competitionLogic;
        modelerLogic = _modelerLogic;
        version = 1;
        competitionVersion = 1;
        modelerVersion = 1;
    }

    function deployCompetition(
        address _admin,
        string calldata _ipfsCompetition, 
        uint256 _topNParameter
    ) external returns (ICompetition) {
        require(owner == msg.sender, "Only owner");
        require(_admin != address(0), "cannot point to zero address");
        require(bytes(_ipfsCompetition).length > 0, "_ipfsCompetition empty"); 
        require(_topNParameter > 0, "_topNParameter zero");
        address competitionProxy = deployCompetitionBeaconProxy(address(competitionLogic), "");
        ICompetition competition = ICompetition(competitionProxy);

        competition.initialize(
            _admin,
            _ipfsCompetition, 
            _topNParameter
        );

        allCompetitions.push(competition);
        emit CompetitionCreated(competition, allCompetitions.length);
        return competition;
    }

    function deployModeler(
        address _competitionContract,
        IERC20 _validatorToken,
        uint256 _validatorStakeAmount,
        uint256 _maxValidators
    ) external returns (IModeler) {
        require(owner == msg.sender, "Only owner");
        require(_competitionContract != address(0), "cannot point to zero address");
        require(address(_validatorToken) != address(0), "cannot point to zero address");
        require(_maxValidators > 0, "cannot be zero");
        address modelerProxy = deployModelerBeaconProxy(address(modelerLogic), "");
        IModeler modeler = IModeler(modelerProxy);
        
        modeler.initialize(
            _competitionContract,
            _validatorToken,
            _validatorStakeAmount,
            _maxValidators
        );
        allModelerContracts.push(modeler);
        emit ModelerContractCreated(modeler, allModelerContracts.length);
        return modeler;
    }

    function upgradeCompetition(ICompetition newCompetition) external {
        require(msg.sender == owner, "Only owner");
        require(address(newCompetition) != address(0), "cannot point to zero address" );
        emit CompetitionUpgraded(msg.sender, newCompetition);
        competitionLogic = newCompetition;
        upgradeCompetitionBeacon(address(newCompetition));
        ++competitionVersion;
    }

    function upgradeModelerContract(IModeler newModelerContract) external {
        require(msg.sender == owner, "Only owner");
        require(address(newModelerContract) != address(0), "cannot point to zero address" );
        emit ModelerContractUpgraded(msg.sender, IModeler(newModelerContract));
        modelerLogic = newModelerContract;
        upgradeModelerBeacon(address(newModelerContract));
        ++modelerVersion;
    }

    function allCompetitionsLength() external view returns (uint256) {
        return allCompetitions.length;
    }

    function getAllCompetitions() public view returns (ICompetition[] memory) {
        return allCompetitions;
    }

    function allModelersContractsLength() external view returns (uint256) {
        return allModelerContracts.length;
    }

    function getAllModelersContracts() public view returns (IModeler[] memory) {
        return allModelerContracts;
    }

    function setNewAdmin(address _newAdmin) external {
        require(msg.sender == owner, "Only owner");
        require(_newAdmin != address(0), "cannot point to zero address");
        owner = _newAdmin;
        emit NewAdminSet(_newAdmin);
    }

    function _authorizeUpgrade(address newImplementation) internal override {
        require(msg.sender == owner, "Only owner");
        require(newImplementation != address(0), "cannot point to zero address");
        ++version;
    }    
}

