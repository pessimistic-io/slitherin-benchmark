// SPDX-License-Identifier: UNLINCESED
pragma solidity 0.8.20;

error InvalidContract();

library LibAllowList {
    bytes32 internal constant ALLOW_LIST_STORAGE = keccak256("allow.list.storage");

    struct AllowListStorage {
        mapping(bytes4 => bool) allowedSelector;
        mapping(address => bool) allowList;
        address[] contracts;
    }

    function _getStorage() internal pure returns (AllowListStorage storage als) {
        bytes32 position = ALLOW_LIST_STORAGE;
        assembly {
            als.slot := position
        }
    } 

    function addAllowedContract(address _contract) internal {
        isContract(_contract);

        AllowListStorage storage als = _getStorage();

        if (als.allowList[_contract]) return;

        als.allowList[_contract] = true;
        als.contracts.push(_contract);
    }

    function removeAllowedContract(address _contract) internal {
        AllowListStorage storage als = _getStorage();

        if (!als.allowList[_contract]) return;

        als.allowList[_contract] = false;

        uint256 contractListLength = als.contracts.length;

        for (uint256 i = 0; i < contractListLength;) {
            if (_contract == als.contracts[i]) {
                als.contracts[i] = als.contracts[contractListLength - 1];
                als.contracts.pop();
                break;
            }
            unchecked {
                ++i;
            }
        }
    }

    function isContractAllowed(address _contract) internal view returns (bool) {
        return _getStorage().allowList[_contract];
    }

    function getAllAllowedContract() internal view returns (address[] memory) {
        return _getStorage().contracts;
    }

    // function isSelectorAllowed(bytes4 _selector) internal view returns (bool) {
    //     return _getStorage().allowedSelector[_selector];
    // }

    function isContract(address _contract) private view {
        if (_contract == address(0)) revert InvalidContract();
        if (_contract.code.length == 0) revert InvalidContract();
    }
}
