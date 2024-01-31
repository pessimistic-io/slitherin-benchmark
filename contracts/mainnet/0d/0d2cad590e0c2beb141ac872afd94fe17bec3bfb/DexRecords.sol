pragma solidity 0.5.17;

import "./Ownable.sol";

contract DexRecords is Ownable {
    mapping(uint256 => address) public dexes;
    uint256 public dexCount = 0;

    function retrieveDexAddress(uint256 number) public view returns (address) {
        require(dexes[number] != address(0), "DexRecords: No implementation set");
        return dexes[number];
    }

    function setDexID(address dex) public onlyOwner {
        dexes[++dexCount] = dex;
    }

    function setDexID(uint256 ID, address dex) public onlyOwner {
        require(dexes[ID] != address(0), "DexRecords: Invalid ID inputted");
        dexes[ID] = dex;
    }
	
    function getDexCount() external view returns(uint256) {
        return dexCount;
    }
}

