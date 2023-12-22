// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.15;

import {ERC721Restricted} from "./ERC721Restricted.sol";
import {AnnotatingMulticall} from "./AnnotatingMulticall.sol";
import {IERC721RestrictedFactory, IERC721Restricted, Authority} from "./IERC721RestrictedFactory.sol";

import {CREATE3} from "./CREATE3.sol";

/// @notice A factory for deploying ERC721Restricted contracts.
/// @author Dinari (https://github.com/dinaricrypto/dinari-contracts/blob/main/contracts/tokens/ERC721RestrictedFactory.sol)
contract ERC721RestrictedFactory is IERC721RestrictedFactory, AnnotatingMulticall {
    /// @notice Emitted when a new token is deployed.
    /// @param token The newly deployed token.
    /// @param deployer The address of the deployer.
    event TokenDeployed(IERC721Restricted indexed token, address indexed deployer);

    /// @notice Deploy a new token.
    /// @return token The address of the newly deployed token.
    function deploy(
        bytes32 salt,
        string memory name,
        string memory symbol,
        address owner,
        Authority authority
    ) external override returns (IERC721Restricted token) {
        // Deploy the Wrapped Token using the CREATE2 opcode.
        token = IERC721Restricted(
            CREATE3.deploy(
                salt,
                abi.encodePacked(type(ERC721Restricted).creationCode, abi.encode(name, symbol, owner, authority)),
                0
            )
        );

        // Emit the event.
        // slither-disable-next-line reentrancy-events
        emit TokenDeployed(token, msg.sender);
    }

    /*///////////////////////////////////////////////////////////////
                           RETRIEVAL LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Get the address of a token given its salt.
    function getDeployedToken(bytes32 salt) external view override returns (IERC721Restricted token) {
        return IERC721Restricted(CREATE3.getDeployed(salt));
    }
}

