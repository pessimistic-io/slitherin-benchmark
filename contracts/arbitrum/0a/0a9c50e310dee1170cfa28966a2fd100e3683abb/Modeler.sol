pragma solidity ^0.8.12;
import "./ICompetition.sol";
import "./IServiceAgreement.sol";
import "./DataTypes.sol";
import "./SafeERC20Upgradeable.sol";
import "./PausableUpgradeable.sol";
import "./Initializable.sol";
import "./ModelerLibrary.sol";

contract Modeler is IModeler, Initializable, PausableUpgradeable  {
    using SafeERC20 for IERC20;
    
    uint256 private maxValidators;
    IERC20 private validatorToken;
    uint256 private validatorStakeAmount;

    mapping(address => DataTypes.ValidatorData) public validators;
    mapping(address => DataTypes.ModelerData) public modelers;

    mapping(address => bool) public isValidatorRegistered;

    mapping(address => DataTypes.ModelerChallenge) public modelerChallenges;

    /*
     A mapping of ZKML challenges given to a modeler to prove that the inferences 
     they are serving are from the model they submitted to be graded
     using zero knowledge machine learning proofs
    */
    mapping(address => DataTypes.ModelerChallenge) public ZKMLChallenges;
    mapping(address => mapping (address => uint256)) public futureRandSlots; // validator => modeler => randSlot
    mapping (uint256 => DataTypes.DrandProof) public drands; // blockNumber => DrandProof

    address[] public validatorAddresses;
    address[] public modelerAddresses;
    
    string public ipfsTestingDataset;

    address private competitionContract;

    uint256[50] private __gap;

    event ChallengeGiven(address indexed validator, address indexed modeler, string ipfsChallenge);
    event ModelerResponds(address indexed validator, address indexed modeler, string ipfsResponse);
    event ModelerGraded(address indexed validator, address indexed modeler, string ipfsGraded);
    event ModelUpdated(address indexed modeler, string modelCommitment);
    event SetRandSlot(address indexed validator, address indexed modeler, uint256 randSlot);
    event ZKMLChallengeGiven(address indexed validator, address indexed modeler, string ipfsChallenge);
    event ZKMLChallengeResponse(address indexed validator, address indexed modeler, string ipfsResponse);
    event DrandSubmitted(address indexed validator, uint256 round, bytes32 randomness, bytes signature, bytes previous_signature);
    event ModelerKicked(address indexed validator, address indexed modeler);
    event IPFSDatasetSet(string ipfsTestingDataset);

    modifier onlyValidator() {
        require(isValidator(msg.sender), "Not a V");
        _;
    }

    modifier onlyCompetition(){
        require(msg.sender == competitionContract);
        _;
    }

    function initialize(
        address _competitionContract,
        IERC20 _validatorToken,
        uint256 _validatorStakeAmount,
        uint256 _maxValidators
    ) external initializer {
        require(_maxValidators > 0, "Cant be zero");
        __Pausable_init();
        competitionContract = _competitionContract;
        validatorToken = _validatorToken;
        validatorStakeAmount = _validatorStakeAmount;
        maxValidators = _maxValidators;
    }


    function registerValidator() public whenNotPaused {
        ModelerLibrary.registerValidator(validatorAddresses, maxValidators, validatorToken, validators[msg.sender], validatorStakeAmount, isValidatorRegistered);
    }

    function setNextRandSlot(address _modeler, uint256 _futureRandSlot) external onlyValidator {
        futureRandSlots[msg.sender][_modeler] = _futureRandSlot;
        emit SetRandSlot(msg.sender, _modeler, _futureRandSlot);
    }

    function setIPFSDataSet(string calldata _ipfsTestingDataset) external onlyValidator {
        ipfsTestingDataset = _ipfsTestingDataset;
        emit IPFSDatasetSet(_ipfsTestingDataset);
    }

    function provideDrandProof(DataTypes.DrandProof memory proof) internal {
        require (drands[proof.round].round == 0, "Drand submitted");
        drands[proof.round] = proof;
        emit DrandSubmitted(msg.sender, proof.round, proof.randomness, proof.signature, proof.previous_signature);
    }

    function registerModeler(address _modeler, string calldata _modelCommitment, uint256 _stakedAmount) external onlyCompetition whenNotPaused {
        require(modelers[_modeler].modelerSubmissionBlock == 0, "M registered");
        modelers[_modeler] = DataTypes.ModelerData(_modelCommitment, block.number, 0, _stakedAmount, ~uint256(0));
        modelerAddresses.push(_modeler);
    }

    function updateModel(string calldata _modelCommitment) external {
        require(!ICompetition(competitionContract).isTopNModeler(msg.sender), "Top M cannot update model");
        require(modelers[msg.sender].modelerSubmissionBlock != 0, "M not registered");
        uint256 stakedAmount = modelers[msg.sender].currentStake;
        modelers[msg.sender] = DataTypes.ModelerData(_modelCommitment, block.number, 0, stakedAmount, ~uint256(0));
        modelerChallenges[msg.sender].ipfsGraded = "0";
        modelerChallenges[msg.sender].performanceResult = 0;
        modelers[msg.sender].medianPerformanceResults = 0;
        emit ModelUpdated(msg.sender, _modelCommitment);
    }

    function giveChallengeToModeler(string calldata _ipfsChallenge, address _modeler, DataTypes.DrandProof memory _proof) external onlyValidator whenNotPaused {
        require(_proof.round == futureRandSlots[msg.sender][_modeler] && _proof.round != 0, "Drand proof rand slot mismatch");
        provideDrandProof(_proof);
        modelerChallenges[_modeler].ipfsChallenge = _ipfsChallenge;
        emit ChallengeGiven(msg.sender, _modeler, _ipfsChallenge);
    }

    function respondToChallenge(address _validator, string calldata _ipfsResponse) external {
        require(modelers[msg.sender].modelerSubmissionBlock != 0, "M not registered");
        require(isValidatorRegistered[_validator], "V not registered");
        require(bytes(modelerChallenges[msg.sender].ipfsChallenge).length > 0, "C not found");
        modelerChallenges[msg.sender].ipfsResponse = _ipfsResponse;
        emit ModelerResponds(_validator, msg.sender, _ipfsResponse);
    }

    function postGraded(address modeler, string calldata _ipfsGraded, uint256 _performanceResult, string calldata _ipfsGradeDetailLink) external onlyValidator {
        require(bytes(modelerChallenges[modeler].ipfsChallenge).length > 0, "M not challenged");
        require(bytes(modelerChallenges[modeler].ipfsResponse).length > 0, "M not responded");
        modelerChallenges[modeler].ipfsGraded = _ipfsGraded;
        modelerChallenges[modeler].performanceResult = _performanceResult;
        modelerChallenges[modeler].ipfsGradeDetailLink = _ipfsGradeDetailLink;
        modelers[modeler].medianPerformanceResults = getMedianPerformanceResults(modeler);

        emit ModelerGraded(msg.sender, modeler, _ipfsGraded);
    }

    function setModelerNetPerformanceResultAndUpdate(address modeler) external onlyValidator whenNotPaused {
        DataTypes.ModelerData memory m = modelers[modeler];
        require(m.optOutTime > block.timestamp, "Already opted out");
        require(m.currentStake >= IServiceAgreement(ICompetition(competitionContract).getServiceAgreement()).stakedAmount(), "M does not have enough stake");
        ICompetition(competitionContract).setModelerNetPerformanceResultAndUpdate(modeler, m.medianPerformanceResults);
    }

    function ZKMLChallengeModeler(address modeler, string calldata _ipfsChallenge, DataTypes.DrandProof memory _proof) external onlyValidator whenNotPaused {
        require(_proof.round == futureRandSlots[msg.sender][modeler] && _proof.round != 0, "Drand proof rand slot mismatch");
        provideDrandProof(_proof);
        ZKMLChallenges[modeler].ipfsChallenge = _ipfsChallenge;
        emit ZKMLChallengeGiven(msg.sender, modeler, _ipfsChallenge);
    }

    function respondToZKMLChallenge(address _validator, string calldata _ipfsResponse) external {
        require(modelers[msg.sender].modelerSubmissionBlock != 0, "M not registered");
        require(isValidatorRegistered[_validator], "V not registered");
        DataTypes.ModelerChallenge memory zc = ZKMLChallenges[msg.sender];
        require(bytes(zc.ipfsChallenge).length > 0, "Challenge not found");
        zc.ipfsResponse = _ipfsResponse;
        emit ZKMLChallengeResponse(_validator, msg.sender, _ipfsResponse);
    } 

    function replaceOptOutTopNModeler(uint256 oldModelerIndex, address oldModeler, address modeler) external onlyValidator whenNotPaused {
        require(modelers[oldModeler].optOutTime < block.timestamp, "M not opted out");
        DataTypes.ModelerData memory m = modelers[modeler];
        require(m.optOutTime > block.timestamp, "New M opted out");
        require(m.currentStake >= IServiceAgreement(ICompetition(competitionContract).getServiceAgreement()).stakedAmount(), "New M does not have enough stake to participate");
        ICompetition(competitionContract).replaceOptOutTopNModeler(oldModelerIndex, modeler, m.medianPerformanceResults);
    }

    //only 1 validator for v1
    function getMedianPerformanceResults(address modeler) internal view returns (uint256) {
        return modelerChallenges[modeler].performanceResult;
    }

    function optOutModeler() external {
        ModelerLibrary.optOutModeler(modelers[msg.sender], ICompetition(competitionContract));
    }

    function kickModeler(address modeler) external onlyValidator whenNotPaused {
        modelers[modeler].optOutTime = block.timestamp;
        emit ModelerKicked(msg.sender, modeler);
    }

    function optInModeler() external whenNotPaused {
        ModelerLibrary.optInModeler(modelers[msg.sender], IServiceAgreement(ICompetition(competitionContract).getServiceAgreement()).stakedAmount());
    }

    function emergencyOptOutValidator(address _validator) external onlyCompetition {
        ModelerLibrary.emergencyOptOutValidator(_validator, validators[_validator], validatorAddresses, isValidatorRegistered);
    }

    function optOutValidator() external onlyValidator {
        ModelerLibrary.optOutValidator(validators[msg.sender], validatorAddresses, competitionContract, isValidatorRegistered);
    }

    function optInValidator() external whenNotPaused {
        ModelerLibrary.optInValidator(validators[msg.sender], validatorStakeAmount, validatorAddresses, isValidatorRegistered);
    }

    function isValidator(address _validator) public view returns (bool) {
        return isValidatorRegistered[_validator] && block.timestamp < validators[_validator].optOutTime;
    }

    function addStakeToModeler(uint256 amount) external whenNotPaused {
        require(modelers[msg.sender].modelerSubmissionBlock != 0, "M not registered");
        IERC20(IServiceAgreement(ICompetition(competitionContract).getServiceAgreement()).stakedToken()).safeTransferFrom(msg.sender, address(this), amount);
        modelers[msg.sender].currentStake += amount;
    }

    function addStakeToValidator(uint256 amount) external whenNotPaused {
        validatorToken.safeTransferFrom(msg.sender, address(this), amount);
        validators[msg.sender].currentStake += amount;
    }
}
