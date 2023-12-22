//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "./TowersNFT.sol";

contract CityClashTowers is TowersNFT {

    event MergeEvent(uint256 tokenIdToUpgrade, uint256 tokenIdToBurn, address a);

    address cityClashContractAddress;

    //upgrades one token by burning the other one into it.
    function mergeTowers(uint tokenIdToUpgrade, uint tokenIdToBurn) public {
        require(_exists(tokenIdToUpgrade), "Tower Token must exist");
        require(_exists(tokenIdToBurn), "Tower Token must exist");
        require(ownerOf(tokenIdToUpgrade) == msg.sender, "You must own both Tower tokens");
        require(ownerOf(tokenIdToBurn) == msg.sender, "You must own both Tower tokens");

        idToNumStories[tokenIdToUpgrade] = min(idToNumStories[tokenIdToUpgrade] + idToNumStories[tokenIdToBurn], 100);
        burn(tokenIdToBurn);

        emit MergeEvent(tokenIdToUpgrade, tokenIdToBurn, address(this));
    }

    function burn(uint _tokenId) internal {
        idToNumStories[_tokenId] = 0;
        _burn(_tokenId);
    }
    
    function burnByCityClashContract(uint _tokenId, address _ownerAddress) external {
        require(ownerOf(_tokenId) == _ownerAddress, "the address must own the tokenId");
        require(cityClashContractAddress == msg.sender, "Only the City Clash Contract can call this function");
        burn(_tokenId);
    }

    function setCityClashContract(address _contractAddress) external onlyOwner {
        cityClashContractAddress = _contractAddress;
    }

    function getCityClashContract() external view onlyOwner returns (address) {
        return cityClashContractAddress;
    }

    function withdraw() external onlyOwner {
        uint balance = address(this).balance;
        uint share = balance * 30 / 100;
        (bool success1,) = address(0x9FFfd1CA952faD6BE57b99b61a0E75c192F201c1).call{value: share}('');
        (bool success2,) = address(0x2429Bc492d2cdfB7114963aF5C3f4d23922af27e).call{value: share}('');
        (bool success3,) = msg.sender.call{value: balance * 40 / 100}('');
        require(success1 && success2 && success3, "Withdrawal failed");
    }
}
