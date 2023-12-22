// SPDX-License-Identifier: MIT
pragma solidity >=0.8.2 <0.9.0;

import "./Ownable.sol";
import "./ECDSA.sol";

contract AIMePowersV4 is Ownable {
    address public protocolFeeDestination;
    uint256 public protocolFeePercent;
    uint256 public protocolFeeDeductedPercent;
    uint256 public creatorFeePercent;
    uint256 public referrerFeePercent;
    uint256 public maxSupply = 10000;
    address public attester;

    /**
     * @dev address - nounce - used
     * @notice used if true, not used if false
     **/
    mapping(address => mapping(uint256 => bool)) public addressNonceUsed;

    event Trade(address trader, address aimeAddress, bool isBuy, uint256 powerAmount, uint256 ethAmount, uint256 creatorFee, uint256 protocolFee, address referrerAddress, uint256 referrerFee, uint256 supply);

    // PowerAddress => (Holder => Balance)
    mapping(address => mapping(address => uint256)) public powerBalance;

    mapping(address => address) public referrer;

    // PowerAddress => Supply
    mapping(address => uint256) public powersSupply;

    function setAttester(address _attester) public onlyOwner {
        attester = _attester;
    }

    function setFeeDestination(address _feeDestination) public onlyOwner {
        protocolFeeDestination = _feeDestination;
    }

    function setProtocolFeePercent(uint256 _feePercent) public onlyOwner {
        protocolFeePercent = _feePercent;
    }

    function setProtocolFeeDeductedPercent(uint256 _feePercent) public onlyOwner {
        protocolFeeDeductedPercent = _feePercent;
    }

    function setCreatorFeePercent(uint256 _feePercent) public onlyOwner {
        creatorFeePercent = _feePercent;
    }

    function setReferrerFeePercent(uint256 _feePercent) public onlyOwner {
        referrerFeePercent = _feePercent;
    }

    function setReferrer(address referrerAddress) public {
        require(referrer[msg.sender] == address(0), "Cannot change referrer");
        referrer[msg.sender] = referrerAddress;
    }

    function _calculateFee(uint256 price) private view returns (uint256) {
        uint256 creatorFee = price * creatorFeePercent / 1 ether;
        uint256 protocolFee = referrer[msg.sender] == address(0) ? (price * protocolFeePercent / 1 ether) : (price * protocolFeeDeductedPercent / 1 ether);
        uint256 referrerFee = referrer[msg.sender] == address(0) ? 0 : (price * referrerFeePercent / 1 ether);
        return creatorFee + protocolFee + referrerFee;
    }

    function getPrice(uint256 supply, uint256 amount) public pure returns (uint256) {
        if (supply == 0) {
            return 0;
        }

        uint256 userSupply = supply;
        uint256 sum1 = (userSupply - 1 ) * (userSupply) * (2 * (userSupply - 1) + 1) / 6;
        uint256 sum2 = (userSupply - 1 + amount) * (userSupply + amount) * (2 * (userSupply - 1 + amount) + 1) / 6;
        uint256 summation = sum2 - sum1;
        return summation * 1 ether / 16000;
    }

    function getBuyPrice(address powerAddress, uint256 amount) public view returns (uint256) {
        return getPrice(powersSupply[powerAddress], amount);
    }

    function getSellPrice(address powerAddress, uint256 amount) public view returns (uint256) {
        return getPrice(powersSupply[powerAddress] - amount, amount);
    }

    function getBuyPriceAfterFee(address powerAddress, uint256 amount) public view returns (uint256) {
        uint256 price = getBuyPrice(powerAddress, amount);
        uint256 fee = _calculateFee(price);
        return price + fee;
    }

    function getSellPriceAfterFee(address powerAddress, uint256 amount) public view returns (uint256) {
        uint256 price = getSellPrice(powerAddress, amount);
        uint256 fee = _calculateFee(price);
        return price + fee;
    }

    function initAIME() public {
        require(powersSupply[msg.sender] == 0, "Already initialized");
        powersSupply[msg.sender] = 1;
    }

    function buyPowers(address powerAddress, uint256 amount) public payable {
        uint256 supply = powersSupply[powerAddress];
        require(supply + amount <= maxSupply, "Exceed hard cap");
        
        uint256 price = getPrice(supply, amount);
        uint256 creatorFee = price * creatorFeePercent / 1 ether;
        uint256 protocolFee = price * (referrer[msg.sender] == address(0) ? protocolFeePercent : protocolFeeDeductedPercent) / 1 ether;
        uint256 referrerFee = referrer[msg.sender] == address(0) ? 0 : (price * referrerFeePercent / 1 ether);
        require(msg.value >= price + creatorFee + protocolFee + referrerFee, "Insufficient payment");

        powerBalance[powerAddress][msg.sender] = powerBalance[powerAddress][msg.sender] + amount;
        powersSupply[powerAddress] = supply + amount;
        
        emit Trade(msg.sender, powerAddress, true, amount, price, creatorFee, protocolFee, referrer[msg.sender], referrerFee, supply + amount);
        
        (bool success1, ) = protocolFeeDestination.call{value: protocolFee}("");
        (bool success2, ) = powerAddress.call{value: creatorFee}("");
        require(success1 && success2, "Unable to send funds");

        if (referrer[msg.sender] != address(0)) {
            (bool success3, ) = referrer[msg.sender].call{value: referrerFee}("");
            require(success3, "Unable to send fund");
        }
    }

    function sellPowers(address powerAddress, uint256 amount) public payable {
        uint256 supply = powersSupply[powerAddress];
        require(supply > amount, "Cannot sell the last share");
        require(powerBalance[powerAddress][msg.sender] >= amount, "Insufficient powers");
        
        uint256 price = getPrice(supply - amount, amount);
        uint256 creatorFee = price * creatorFeePercent / 1 ether;
        uint256 protocolFee = price * (referrer[msg.sender] == address(0) ? protocolFeePercent : protocolFeeDeductedPercent) / 1 ether;
        uint256 referrerFee = referrer[msg.sender] == address(0) ? 0 : (price * referrerFeePercent / 1 ether);
        
        powerBalance[powerAddress][msg.sender] = powerBalance[powerAddress][msg.sender] - amount;
        powersSupply[powerAddress] = supply - amount;
        
        emit Trade(msg.sender, powerAddress, false, amount, price, creatorFee, protocolFee, referrer[msg.sender], referrerFee, supply - amount);
        
        (bool success1, ) = msg.sender.call{value: price - creatorFee - protocolFee - referrerFee}("");
        (bool success2, ) = protocolFeeDestination.call{value: protocolFee}("");
        (bool success3, ) = powerAddress.call{value: creatorFee}("");
        require(success1 && success2 && success3, "Unable to send funds");

        if (referrer[msg.sender] != address(0)) {
            (bool success4, ) = referrer[msg.sender].call{value: referrerFee}("");
            require(success4, "Unable to send fund");
        }
    }
}
