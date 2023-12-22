pragma solidity ^0.8.12;

import "./Initializable.sol";
import "./SafeERC20.sol";
import "./IModeler.sol";
import "./IConsumption.sol";
import "./IServiceAgreement.sol";
import "./DataTypes.sol";
import "./CompetitionLibrary.sol";

contract Competition is ICompetition, Initializable {
    using SafeERC20 for IERC20;

    address public admin;

    // Modeler's net performance result
    mapping(address => uint256) public modelerToMedian;

    IModeler public modelerContract;
    address public consumptionContract;
    
    // IPFS hash to Competition details
    string public ipfsCompetition;

    // Top N Modelers serve inferences in the consumption window
    uint256 public topNParameter;
    address[] public topNModelers;

    IServiceAgreement public serviceAgreement;

    string public ipfsTrainingDataset;

    uint256[50] private __gap;

    event ModelerRegistered(address indexed modeler, string modelHash);
    event TopNModelersUpdated(address[] topNModelers);
    event ServiceAgreementSigned(address indexed modeler);
    event ServiceAgreementSet(IServiceAgreement newServiceAgreement);
    event ModelerContractSet(IModeler modelerContract);
    event ConsumptionContractSet(IConsumption consumptionContract);
    event ModelerNetPerformanceSet(address indexed modeler, uint256 medianPerformanceResults);
    event IPFSCompetitionDescriptionHashSet(string ipfsCompetition);
    event IPFSTrainingDataSetSet(string ipfsTrainingDataset);
    event OptOutValidator(address validator);
    event SetAdmin(address newAdmin);

    modifier onlyAdmin() {
        require(msg.sender == admin);
        _;
    }

    modifier onlyModelerContract() {
        require(msg.sender == address(modelerContract));
        _;
    }

    function initialize(
        address _admin,
        string memory _ipfsCompetition,
        uint256 _topNParameter
    ) external initializer  {
        admin = _admin;
        ipfsCompetition = _ipfsCompetition;
        topNParameter = _topNParameter;
    }

    function signUpToCompetition(string calldata _modelHash) external {
        require(bytes(_modelHash).length > 0, "ERR2");
        require(address(modelerContract) != address(0), "ERR1");
        IERC20(serviceAgreement.stakedToken()).safeTransferFrom(msg.sender, address(modelerContract), serviceAgreement.stakedAmount());
        modelerContract.registerModeler(msg.sender, _modelHash, serviceAgreement.stakedAmount());
        emit ModelerRegistered(msg.sender, _modelHash);
    }

    function setModelerNetPerformanceResultAndUpdate(address modeler, uint256 medianPerformanceResults) external onlyModelerContract {
        if (topNModelers.length == 0) {
            insertNewModeler(modeler, medianPerformanceResults);
            return;
        }
        
        uint256 topNMinus1 = topNModelers.length - 1;
        address lowestModeler = topNModelers[topNMinus1];

        if (topNModelers.length < topNParameter) {
            insertNewModeler(modeler, medianPerformanceResults);
        } else if (medianPerformanceResults > modelerToMedian[lowestModeler]) {
            uint256 newIndex = findModelerUpperBound(medianPerformanceResults);
            for (uint256 i = topNMinus1; i > newIndex; i--) {
                topNModelers[i] = topNModelers[i - 1];
            }
            topNModelers[newIndex] = modeler;
            modelerToMedian[modeler] = medianPerformanceResults;
            delete modelerToMedian[lowestModeler];
            emit ModelerNetPerformanceSet(modeler, medianPerformanceResults);
        }
    }

    function insertNewModeler(address modeler, uint256 performanceResult) internal {
        require(modelerToMedian[modeler] == 0, "ERR3");
        uint256 newIndex = findModelerUpperBound(performanceResult);
        topNModelers.push(address(0)); // Add a placeholder at the end of the array to make space for the new modeler
        for (uint256 i = topNModelers.length - 1; i > newIndex; i--) {
            topNModelers[i] = topNModelers[i - 1];
        }
        topNModelers[newIndex] = modeler;
        modelerToMedian[modeler] = performanceResult;
        emit TopNModelersUpdated(topNModelers);
    }

    function replaceOptOutTopNModeler(uint256 _oldModelerIndex, address _newModeler, uint256 _medianPerformanceResults) external onlyModelerContract {
        require(_oldModelerIndex < topNModelers.length, "ERR4");
        address _oldModeler = topNModelers[_oldModelerIndex];
        uint256 newIndex = findModelerUpperBound(_medianPerformanceResults);
        for (uint256 i = topNModelers.length; i > newIndex; i--) {
            topNModelers[i] = topNModelers[i - 1];
        }
        topNModelers[newIndex] = _newModeler;
        modelerToMedian[_newModeler] = _medianPerformanceResults;
        delete modelerToMedian[_oldModeler];
        emit TopNModelersUpdated(topNModelers);
    }

    function findModelerUpperBound(uint256 _element) internal view returns (uint256){
        return CompetitionLibrary.findModelerUpperBound(topNModelers, modelerToMedian, _element);
    }

    function setServiceAgreementContract(IServiceAgreement _agreement) external onlyAdmin {
        require(address(_agreement) != address(0), "ERR1");
        serviceAgreement = _agreement;
        emit ServiceAgreementSet(_agreement);
    }

    function setModelerContract(IModeler _modelerContract) external onlyAdmin {
        require(address(_modelerContract) != address(0), "ERR1");
        modelerContract = _modelerContract;
        emit ModelerContractSet(_modelerContract);
    }

    function setConsumptionContract(IConsumption _consumptionContract) external onlyAdmin {
        require(address(_consumptionContract) != address(0), "ERR1");
        consumptionContract = address(_consumptionContract);
        emit ConsumptionContractSet(_consumptionContract);
    }

    function setIPFSCompetitionDescriptionHash(string calldata _ipfsCompetition) external onlyAdmin {
        require(bytes(_ipfsCompetition).length > 0, "ERR2");
        ipfsCompetition = _ipfsCompetition;
        emit IPFSCompetitionDescriptionHashSet(_ipfsCompetition);
    }

    function setIPFSTrainingDataSet(string calldata _ipfsTrainingDataset) external onlyAdmin {
        require(bytes(_ipfsTrainingDataset).length > 0, "ERR2");
        ipfsTrainingDataset = _ipfsTrainingDataset;
        emit IPFSTrainingDataSetSet(_ipfsTrainingDataset);
    }

    function isTopNModeler(address _modeler) public view returns (bool isTopN) {
        return CompetitionLibrary.isTopNModeler(topNModelers, _modeler);
    }

    function getTopNModelers() public view returns (address[] memory) {
        return topNModelers;
    }

    function getTopNModelersLength() public view returns (uint256) {
        return topNModelers.length;
    }

    function getModelerToMedian(address _modeler) public view returns (uint256) {
        return modelerToMedian[_modeler];
    }

    function getSAParams() public view returns (DataTypes.SAParams memory) {
        return serviceAgreement.agreementParams();
    }

    function getServiceAgreement() public view returns (IServiceAgreement) {
        return serviceAgreement;
    }

    function emergencyOptOutValidator(address _validator) external onlyAdmin {
        modelerContract.emergencyOptOutValidator(_validator);
        emit OptOutValidator(_validator);
    }

    function setAdmin(address _newAdmin) external onlyAdmin {
        admin = _newAdmin;
        emit SetAdmin(_newAdmin);
    }

}

