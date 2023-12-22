// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

library ERC20Storage {
    struct ERC20DS {
        /*//////////////////////////////////////////////////////////////
                              ERC20 STORAGE
        //////////////////////////////////////////////////////////////*/
        string name;
        string symbol;
        uint8 decimals;
        uint256 totalSupply;
        mapping(address => uint256) balanceOf;
        mapping(address => mapping(address => uint256)) allowance;
        /*//////////////////////////////////////////////////////////////
                            EIP-2612 STORAGE
        //////////////////////////////////////////////////////////////*/
        uint256 INITIAL_CHAIN_ID;
        bytes32 INITIAL_DOMAIN_SEPARATOR;
        mapping(address => uint256) nonces;
    }

    bytes32 constant DIAMOND_STORAGE_ERC20 = keccak256('factor.studio.main.ERC20Storage');

    function layout() internal pure returns (ERC20DS storage ds) {
        bytes32 slot = DIAMOND_STORAGE_ERC20;
        assembly {
            ds.slot := slot
        }
    }
}

