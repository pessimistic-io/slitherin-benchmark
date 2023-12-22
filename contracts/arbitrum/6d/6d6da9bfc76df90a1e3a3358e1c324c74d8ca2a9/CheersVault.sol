// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import "./ReentrancyGuard.sol";

contract CheersVault is ReentrancyGuard {
    address public factory;
    address public cheersSubjuect;
    address public cheersV1address;

    mapping(address => uint256) public subsVaultShares;
    address[] public subsVaultBeneficiaries;
    mapping(address => uint256) public cheersVaultShares;
    address[] public cheersVaultBeneficiaries;

    uint256 public subsVaultValue = 0;
    uint256 public cheersVaultValue = 0;
    uint256 public lastDistributionTime; 
    uint256 public distributionInterval = 7 days;
    
    event Deposit(address indexed depositor, uint256 amount, uint256 vaultType);
    event Distribution(uint256 totalAmount);
    event DistributionDetails(address indexed beneficiaries, uint256 amount);

    constructor() payable {
        factory = msg.sender;
    }

    function initialize(address _cheersSubject, address _cheersV1address) external {
        require(msg.sender == factory, "sufficient check");
        cheersSubjuect = _cheersSubject;
        cheersV1address = _cheersV1address;
    }

    function getBalance() view public returns(uint) {
        return address(this).balance;
    }

    function removeValue(address _value, uint256 amount) public returns (bool) {
        uint256 length = cheersVaultBeneficiaries.length;
        for (uint256 i = 0; i < length; i++) {
            if (cheersVaultBeneficiaries[i] == _value && amount > 0) {
                cheersVaultBeneficiaries[i] = cheersVaultBeneficiaries[length - 1];
                cheersVaultBeneficiaries.pop();
                amount -= 1;
                if (amount == 0){
                    return true;
                }
            } 
        }
        return false;
    }

    function deposit(address depositor, uint256 action, uint256 vaultType, uint256 amount) external payable{
        require(msg.sender == cheersV1address, "only cheersV1 can deposit");
        require(tx.origin == depositor, "Only EOAs can call this function");
        // vault type == 1 means subs vault, else means cheers vault. All cheers commission fee go to subs vault, all subs fee go to cheers vault 
        if (vaultType == 1){
            subsVaultValue += msg.value;
            if (action == 1) {
                cheersVaultShares[depositor] += amount;
                for (uint256 i = 0; i < amount; i++) {
                    cheersVaultBeneficiaries.push(depositor);
                }
            } else {
                cheersVaultShares[depositor] -= amount;
                removeValue(depositor, amount);
            }
        } else {
            cheersVaultValue += msg.value;
            subsVaultShares[depositor] += amount;
            subsVaultBeneficiaries.push(depositor);
        }
        emit Deposit(msg.sender, msg.value,vaultType );
    }

    function distributeToSubsHolders() public nonReentrant {
        require(msg.sender == cheersSubjuect, "Only owner can destribute funds");
        require(block.timestamp >= lastDistributionTime + distributionInterval);
        uint256 totalAmount = subsVaultValue;
        require(totalAmount > 0, "No funds to distribute");
        uint256 totalShares;
        for (uint256 i = 0; i < subsVaultBeneficiaries.length; i++) {
            if (subsVaultShares[subsVaultBeneficiaries[i]] > block.timestamp){
                totalShares += 1;
            }
        }
        require(totalShares > 0, "No shares allocated");
        for (uint256 i = 0; i < subsVaultBeneficiaries.length; i++) {
            uint256 amount = totalAmount / totalShares;
            if (subsVaultShares[subsVaultBeneficiaries[i]] > block.timestamp){
                payable(subsVaultBeneficiaries[i]).transfer(amount);
                emit DistributionDetails(subsVaultBeneficiaries[i], amount);
            }
        }
        lastDistributionTime = block.timestamp;
        subsVaultValue = 0;
        emit Distribution(totalAmount);
    }

    function distributeToCheersHolders() public nonReentrant {
        require(msg.sender == cheersSubjuect, "Only owner can destribute funds");
        require(block.timestamp >= lastDistributionTime + distributionInterval);
        uint256 totalAmount = cheersVaultValue;
        require(totalAmount > 0, "No funds to distribute");
        uint256 totalShares;
        for (uint256 i = 0; i < cheersVaultBeneficiaries.length; i++) {
            totalShares += cheersVaultShares[cheersVaultBeneficiaries[i]];
        }
        require(totalShares > 0, "No shares allocated");
        for (uint256 i = 0; i < cheersVaultBeneficiaries.length; i++) {
            uint256 amount = totalAmount * cheersVaultShares[cheersVaultBeneficiaries[i]] / totalShares;
            payable(cheersVaultBeneficiaries[i]).transfer(amount);
            emit DistributionDetails(cheersVaultBeneficiaries[i], amount);
        }
        lastDistributionTime = block.timestamp;
        cheersVaultValue = 0;
        emit Distribution(totalAmount);
    }

    function updateDistributionInterval(uint256 _newInterval) public {
        require(msg.sender == cheersSubjuect, "Only owner can update interval");
        distributionInterval = _newInterval;
    }

}
