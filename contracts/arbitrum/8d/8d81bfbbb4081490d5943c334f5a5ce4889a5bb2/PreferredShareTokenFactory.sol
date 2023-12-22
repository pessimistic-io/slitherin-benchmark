// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.15;

import {PreferredShareToken, IERC20Metadata} from "./PreferredShareToken.sol";
import {AnnotatingMulticall} from "./AnnotatingMulticall.sol";
import {Authority} from "./AuthBase.sol";

import {CREATE3} from "./CREATE3.sol";

/// @notice A factory for deploying PreferredShareToken contracts.
/// @author Dinari (https://github.com/dinaricrypto/dinari-contracts/blob/main/contracts/tokens/PreferredShareTokenFactory.sol)
contract PreferredShareTokenFactory is AnnotatingMulticall {
    /// @notice Emitted when a new Wrapped Token is deployed.
    /// @param token The newly deployed Wrapped Token.
    /// @param deployer The address of the PreferredShareToken deployer.
    event TokenDeployed(PreferredShareToken indexed token, address indexed deployer);

    /// @notice Deploy a new Wrapped Token.
    /// @return token The address of the newly deployed token.
    function deployPreferredShareToken(
        bytes32 salt,
        string memory name,
        string memory symbol,
        IERC20Metadata underlying,
        uint256 multiple,
        address owner,
        Authority authority
    ) external returns (PreferredShareToken token) {
        // Deploy the Wrapped Token using the CREATE2 opcode.
        token = PreferredShareToken(
            CREATE3.deploy(
                salt,
                abi.encodePacked(
                    type(PreferredShareToken).creationCode,
                    abi.encode(name, symbol, underlying, multiple, owner, authority)
                ),
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

    /// @notice Get the address of a Wrapped Token given its salt.
    function getDeployedToken(bytes32 salt) external view returns (PreferredShareToken token) {
        return PreferredShareToken(CREATE3.getDeployed(salt));
    }
}

