// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "./Ownable.sol";
import "./IRelayStore.sol";

contract RelayStore is Ownable, IRelayStore {
    RelayEntry[] relayList;
    uint8 public relayPercentage = 10; // relayer beeps
    uint8 public relayPercentageSwap = 10;

    function setRelayPercentage(uint8 _relayPercentage) public onlyOwner {
        require(_relayPercentage <= 50);
        relayPercentage = _relayPercentage;
        emit RelayPercentageChanged(relayPercentage);
    }

    function setRelayPercentageSwap(uint8 _relayPercentageSwap)
        public
        onlyOwner
    {
        require(_relayPercentageSwap <= 50);
        relayPercentageSwap = _relayPercentageSwap;
        emit RelayPercentageSwapChanged(relayPercentageSwap);
    }


    function isRelayInList(address relay) public view returns (bool) {
        bool found = false;
        for (uint256 i = 0; i < relayList.length; i++) {
            if (relayList[i].relayAddress == relay) {
                found = true;
                break;
            }
        }
        return found;
    }

    function getRelayList() public view returns (RelayEntry[] memory) {
        return relayList;
    }

    function addOrSetRelay(
        address relayAddress,
        string memory url,
        uint256 priority
    ) public onlyOwner {
        uint256 foundIndex = relayList.length;

        for (uint256 i = 0; i < relayList.length; i++) {
            if (
                keccak256(abi.encodePacked(relayList[i].url)) ==
                keccak256(abi.encodePacked(url))
            ) {
                foundIndex = i;
                break;
            }
        }
        RelayEntry memory relayEntry = RelayEntry(relayAddress, url, priority);

        if (foundIndex != relayList.length) {
            require(
                relayList[foundIndex].relayAddress == relayAddress,
                "owner doesn't match"
            );
            relayList[foundIndex] = relayEntry;
        } else relayList.push(relayEntry);

        emit RelayAddedOrSet(relayAddress, url, priority);
    }
}

