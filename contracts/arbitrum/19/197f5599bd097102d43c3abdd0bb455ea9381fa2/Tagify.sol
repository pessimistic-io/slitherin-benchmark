// File: contracts/Tagify.sol
// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.2 <0.9.0;

import "./Ownable.sol";
import "./ECDSA.sol";
import "./MessageHashUtils.sol";

contract Tagify is Ownable(msg.sender) {
    using ECDSA for bytes32;

    address private signerRole;
    address public protocolFeeDestination;

    // 100% = 10e18 (1 ether in wei)
    uint256 public protocolFeePercent;

    // 100% = 10e18 (1 ether in wei)
    uint256 public subjectFeePercent;

    event BuyShares(address indexed trader, uint256 indexed sharesId, uint256 shareAmount, uint256 ethAmount, uint256 protocolEthAmount, uint256 subjectEthAmount, uint256 supply);
    event SellShares(address indexed trader, uint256 indexed sharesId, address sharesSubject, uint256 shareAmount, uint256 ethAmount, uint256 protocolEthAmount, uint256 subjectEthAmount, uint256 supply);
    event WithdrawFee(uint256 indexed sharesId, address indexed sharesSubject, uint256 amount);
    event SignerRoleChanged(address indexed newSigner);
    event NewSharesSubject(uint256 indexed sharesId, address indexed sharesSubject);

    // @dev The association between sharesId and address
    // @notice Shares subject ID => Shares subject address
    mapping(uint256 => address) public sharesSubjects;

    // @dev Flag if the supply of shares subject has been sold at least once
    // @notice Shares subject ID => Is supply minted
    mapping(uint256 => bool) public isSupplyMinted;

    // @dev Accumulated fee of shares subject
    // @notice Shares subject ID => Fee balance
    mapping(uint256 => uint256) public sharesFeeBalance;

    // @dev Amount of supplies for each holder
    // @notice Shares subject ID => (Holder => Supply)
    mapping(uint256 => mapping(address => uint256)) public sharesBalance;

    // @dev Total amount of supplies
    // @notice Shares subject ID => Supply
    mapping(uint256 => uint256) public sharesSupply;

    // @dev Nonce of shares subject
    // @notice Shares subjectID => None
    mapping(uint256 => uint256) internal nonces;

    modifier checkSignature(bytes memory data, bytes memory signature) {
        require(signerRole == MessageHashUtils.toEthSignedMessageHash(keccak256(data)).recover(signature), "Invalid signature");
        _;
    }

    constructor(address signer, address feeDestination, uint256 protocolFee, uint256 subjectFee) {
        setSignerRole(signer);
        setFeeDestination(feeDestination);
        setProtocolFeePercent(protocolFee);
        setSubjectFeePercent(subjectFee);
    }

    function getSignerRole() public view returns (address) {
        return signerRole;
    }

    function setSignerRole(address newSignerRole) public onlyOwner {
        require(newSignerRole != address(0), "New signer wallet is the zero address");
        emit SignerRoleChanged(newSignerRole);
        signerRole = newSignerRole;
    }

    // @dev create association between sharesId and address
    // @param sharesId - ID of shares subject
    // @param finalTimestamp - signature expiration date
    // @param nonce - unique number
    // @param signature - signed message by backend
    function addSharesSubject(uint256 sharesId, uint256 finalTimestamp, uint256 nonce, bytes calldata signature) external checkSignature(abi.encode(sharesId, msg.sender, finalTimestamp, nonce), signature) {
        require(block.timestamp < finalTimestamp, "Signer transaction expired");
        require(nonces[sharesId] < nonce, "Incorrect nonce");

        nonces[sharesId] = nonce;
        sharesSubjects[sharesId] = msg.sender;

        // Mint first supply if shares subject has not supply
        // First supply is free and reserved for for subject owner
        if (!isSupplyMinted[sharesId]) {
            isSupplyMinted[sharesId] = true;

            if (sharesSupply[sharesId] == 0) {
                sharesSupply[sharesId] = 1;
            }

            sharesBalance[sharesId][msg.sender]++;
            emit BuyShares(msg.sender, sharesId, 1, 0, 0, 0, sharesSupply[sharesId]);
        }

        emit NewSharesSubject(sharesId, msg.sender);
    }

    // @dev Set service fee destination
    // @param feeDestination - destination address
    function setFeeDestination(address newFeeDestination) public onlyOwner {
        require(newFeeDestination != address(0), "Invalid address");
        protocolFeeDestination = newFeeDestination;
    }

    // @dev Set service fee percent
    // @param feePercent. 100% = 10e18. The percentage must be greater than 0% and less than 10%
    function setProtocolFeePercent(uint256 newProtocolFeePercent) public onlyOwner {
        require(newProtocolFeePercent > 0 && newProtocolFeePercent <= 1 ether / 10, "Invalid fee value");
        protocolFeePercent = newProtocolFeePercent;
    }

    // @dev Set subject fee percent
    // @param feePercent. 100% = 10e18. The percentage must be greater than 0% and less than 10%
    function setSubjectFeePercent(uint256 newSubjectFeePercent) public onlyOwner {
        require(newSubjectFeePercent > 0 && newSubjectFeePercent <= 1 ether / 10, "Invalid fee value");
        subjectFeePercent = newSubjectFeePercent;
    }

    // @dev Calculates the price of supplies
    // @notice Each next supply has a different price
    // @param supply - number of available supply
    // @param amount - amount of supplies for which the price needs to be calculated
    function getPrice(uint256 supply, uint256 amount) public pure returns (uint256) {
        // First supply is free and reserved for for subject owner
        uint256 supplyValue = supply == 0 ? 1 : supply;
        uint256 sum1 = (supplyValue - 1) * (supplyValue) * (2 * (supplyValue - 1) + 1) / 6;
        uint256 sum2 = (supplyValue + amount - 1) * (supplyValue + amount) * (2 * (supplyValue + amount - 1) + 1) / 6;
        uint256 summation = sum2 - sum1;

        return summation * 1 ether / 50000;
    }

    // @dev Calculates the price of supplies for buying
    // @param sharesId - ID of shares subject from which the supply is bought
    // @param amount - amount of supplies for which the price needs to be calculated
    function getBuyPrice(uint256 sharesId, uint256 amount) public view returns (uint256) {
        return getPrice(sharesSupply[sharesId], amount);
    }

    // @dev Calculates the price of supplies for selling
    // @param sharesId - ID of shares subject from which the supply is bought
    // @param amount - amount of supplies for which the price needs to be calculated
    function getSellPrice(uint256 sharesId, uint256 amount) public view returns (uint256) {
        return getPrice(sharesSupply[sharesId] - amount, amount);
    }

    // @dev Calculates the fees and price of supplies for buying
    function getBuyPriceAfterFee(uint256 sharesId, uint256 amount) public view returns (uint256) {
        uint256 price = getBuyPrice(sharesId, amount);
        uint256 protocolFee = price * protocolFeePercent / 1 ether;
        uint256 subjectFee = price * subjectFeePercent / 1 ether;

        return price + protocolFee + subjectFee;
    }

    // @dev Calculates the fees and price of supplies for selling
    function getSellPriceAfterFee(uint256 sharesId, uint256 amount) public view returns (uint256) {
        uint256 price = getSellPrice(sharesId, amount);
        uint256 protocolFee = price * protocolFeePercent / 1 ether;
        uint256 subjectFee = price * subjectFeePercent / 1 ether;

        return price - protocolFee - subjectFee;
    }

    // @dev Buy supplies
    // @param sharesId - ID of shares subject from which the supply is bought
    // @param amount - amount of supply
    function buyShares(uint256 sharesId, uint256 amount) public payable {
        require(amount > 0, "Amount must be greater than zero");

        uint256 supply = sharesSupply[sharesId];

        if (supply == 0) {
            // First share is free and reserved for for subject owner
            supply = 1;
        }

        uint256 price = getPrice(supply, amount);
        uint256 protocolFee = price * protocolFeePercent / 1 ether;
        uint256 subjectFee = price * subjectFeePercent / 1 ether;

        require(msg.value == price + protocolFee + subjectFee, "Invalid eth value");

        sharesBalance[sharesId][msg.sender] = sharesBalance[sharesId][msg.sender] + amount;
        sharesSupply[sharesId] = supply + amount;
        sharesFeeBalance[sharesId] = sharesFeeBalance[sharesId] + subjectFee;

        emit BuyShares(msg.sender, sharesId, amount, price, protocolFee, subjectFee, supply + amount);

        (bool success1,) = protocolFeeDestination.call{value: protocolFee}("");

        require(success1, "Unable to send funds");
    }

    // @dev Sell supplies
    // @param sharesId - ID of shares subject from which the supply is bought
    // @param amount - amount of supply
    function sellShares(uint256 sharesId, uint256 amount) public {
        require(amount > 0, "Amount must be greater than zero");

        uint256 supply = sharesSupply[sharesId];

        require(supply > amount, "Cannot sell the last share");

        uint256 price = getPrice(supply - amount, amount);
        uint256 protocolFee = price * protocolFeePercent / 1 ether;
        uint256 subjectFee = price * subjectFeePercent / 1 ether;

        require(sharesBalance[sharesId][msg.sender] >= amount, "Insufficient shares");

        sharesBalance[sharesId][msg.sender] = sharesBalance[sharesId][msg.sender] - amount;
        sharesSupply[sharesId] = supply - amount;
        sharesFeeBalance[sharesId] = sharesFeeBalance[sharesId] + subjectFee;

        emit SellShares(msg.sender, sharesId, sharesSubjects[sharesId], amount, price, protocolFee, subjectFee, supply - amount);

        (bool success1,) = msg.sender.call{value: price - protocolFee - subjectFee}("");
        (bool success2,) = protocolFeeDestination.call{value: protocolFee}("");

        require(success1 && success2, "Unable to send funds");
    }

    // @dev Withdrawal of the fee of the shares subject
    // @param sharesId -  ID of shares subject from which the fee is withdrawn
    function withdrawFee(uint256 sharesId) public {
        require(msg.sender == sharesSubjects[sharesId], "Caller is not shares subject");

        uint256 feeBalance = sharesFeeBalance[sharesId];

        require(feeBalance > 0, "Empty balance");

        sharesFeeBalance[sharesId] = 0;

        emit WithdrawFee(sharesId, msg.sender, feeBalance);

        (bool success,) = msg.sender.call{value: feeBalance}("");

        require(success, "Unable to send funds");
    }
}
