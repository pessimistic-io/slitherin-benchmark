pragma solidity 0.7.6;
import "./Ownable.sol";

contract Whitelist is Ownable {
    mapping(address => uint256) public tiers;
    event ChangeTier(address indexed account, uint256 tier);

    bool initialized = false;

    constructor (address admin) Ownable(admin) {}

    function initialize(address admin) public {
        require(initialized == false, "Tiers: contract has already been initialized.");
        owner = admin;
        initialized = true;
    }

    function changeTier(address _address, uint256 _tier) public onlyOwner {
        tiers[_address] = _tier;
        emit ChangeTier(_address, _tier);
    }

    function changeTierBatch(address[] calldata _addresses, uint256[] calldata _tierList) public onlyOwner {
        uint arrayLength = _addresses.length;
        require(arrayLength == _tierList.length, "Tiers: Arrays are not the same size");
        for (uint i = 0; i < arrayLength; i++) {
            address _address = _addresses[i];
            uint256 _tier = _tierList[i];
            tiers[_address] = _tier;
            emit ChangeTier(_address, _tier);
        }
    }

    function getTier(address _address) public view returns(uint256) {
        return tiers[_address];
    }
}

