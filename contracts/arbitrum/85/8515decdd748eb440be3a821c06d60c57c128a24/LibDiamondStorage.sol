// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

library LibDiamondStorage{

    bytes32 constant DIAMOND_STORAGE_POSITION = keccak256("diamond.standard.diamond.storage");

    struct FacetAddressAndPosition {
        address facetAddress;
        uint16 functionSelectorPosition; // position in facetFunctionSelectors.functionSelectors array
    }

    struct FacetFunctionSelectors {
        bytes4[] functionSelectors;
        uint16 facetAddressPosition; // position of facetAddress in facetAddresses array
    }

    struct DiamondStorage {
		/*Diamond*/
        // maps function selector to the facet address and
        // the position of the selector in the facetFunctionSelectors.selectors array
		mapping(bytes4 => FacetAddressAndPosition) selectorToFacetAndPosition;
        // maps facet addresses to function selectors
        mapping(address => FacetFunctionSelectors) facetFunctionSelectors;
        // facet addresses
        address[] facetAddresses;
        // Used to query if a contract implements an interface.
        // Used to implement ERC-165.
        mapping(bytes4 => bool) supportedInterfaces;
        // owner of the contract
        address contractOwner;
		/*Diamond*/
		
		/*erc20*/
		mapping(address => uint256) _balances;
		mapping(address => mapping(address => uint256)) _allowances;
		uint256 _totalSupply;
		uint256 _capSupply;
		string  _name;
		string  _symbol;
		uint8   _decimal;
		/*erc20*/
		
		/*batchmint*/
		/*
		uint256 _idCounter;
		mapping(address => uint256) _addressToID;
		mapping(uint256 => address) _idToAddress;
		*/
		/*batchmint */
		
    }

    function diamondStorage() internal pure returns (DiamondStorage storage ds) {
        bytes32 position = DIAMOND_STORAGE_POSITION;
        assembly {
            ds.slot := position
        }
    }


}

