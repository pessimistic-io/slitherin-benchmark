// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Create2.sol";

interface IERC6551Registry {
    /**
     * @dev The registry MUST emit the ERC6551AccountCreated event upon successful account creation
     */
    event ERC6551AccountCreated(
        address account,
        address indexed implementation,
        bytes32 salt,
        uint256 chainId,
        address indexed tokenContract,
        uint256 indexed tokenId
    );

    /**
     * @dev The registry MUST revert with AccountCreationFailed error if the create2 operation fails
     */
    error AccountCreationFailed();

    /**
     * @dev Creates a token bound account for a non-fungible token
     *
     * If account has already been created, returns the account address without calling create2
     *
     * If initData is not empty and account has not yet been created, calls account with
     * provided initData after creation
     *
     * Emits ERC6551AccountCreated event
     *
     * @return the address of the account
     */
    function createAccount(
        address implementation,
        bytes32 salt,
        uint256 chainId,
        address tokenContract,
        uint256 tokenId
    ) external returns (address);

    /**
     * @dev Returns the computed token bound account address for a non-fungible token
     *
     * @return The computed address of the token bound account
     */
    function account(address implementation, bytes32 salt, uint256 chainId, address tokenContract, uint256 tokenId)
        external
        view
        returns (address);
}

library ERC6551BytecodeLib {
    /**
     * @dev Returns the creation code of the token bound account for a non-fungible token
     *
     * @return the creation code of the token bound account
     */
    function getCreationCode(
        address implementation_,
        bytes32 salt_,
        uint256 chainId_,
        address tokenContract_,
        uint256 tokenId_
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(
            hex"3d60ad80600a3d3981f3363d3d373d3d3d363d73",
            implementation_,
            hex"5af43d82803e903d91602b57fd5bf3",
            abi.encode(salt_, chainId_, tokenContract_, tokenId_)
        );
    }
}

contract ERC6551Registry is IERC6551Registry {
    /**
     * @dev {See IERC6551Registry-createAccount}
     */
    function createAccount(
        address implementation,
        bytes32 salt,
        uint256 chainId,
        address tokenContract,
        uint256 tokenId
    ) external returns (address) {
        bytes memory code = ERC6551BytecodeLib.getCreationCode(implementation, salt, chainId, tokenContract, tokenId);

        address _account = Create2.computeAddress(salt, keccak256(code));

        if (_account.code.length != 0) return _account;

        emit ERC6551AccountCreated(_account, implementation, salt, chainId, tokenContract, tokenId);

        assembly {
            _account := create2(0, add(code, 0x20), mload(code), salt)
        }

        if (_account == address(0)) revert AccountCreationFailed();

        return _account;
    }

    /**
     * @dev {See IERC6551Registry-account}
     */
    function account(address implementation, bytes32 salt, uint256 chainId, address tokenContract, uint256 tokenId)
        external
        view
        returns (address)
    {
        bytes32 bytecodeHash =
            keccak256(ERC6551BytecodeLib.getCreationCode(implementation, salt, chainId, tokenContract, tokenId));

        return Create2.computeAddress(salt, bytecodeHash);
    }
}

