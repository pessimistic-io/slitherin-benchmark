// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

import {Address} from "./Address.sol";

import {IGSWFactory} from "./IGSWFactory.sol";
import {IGaslessSmartWallet} from "./IGaslessSmartWallet.sol";

/// @title    GSWForwarder
/// @notice   Only compatible with forwarding `cast` calls to GaslessSmartWallet contracts. This is not a generic forwarder.
///           This is NOT a "TrustedForwarder" as proposed in EIP-2770. See notice in GaslessSmartWallet.
/// @dev      Does not validate the EIP712 signature (instead this is done in the Gasless Smart wallet)
contract GSWForwarder {
    using Address for address;

    IGSWFactory public immutable gswFactory;

    constructor(IGSWFactory _gswFactory) {
        gswFactory = _gswFactory;
    }

    /// @notice             Retrieves the current gswNonce of GSW for owner address, which is necessary to sign meta transactions
    /// @param owner        GaslessSmartWallet owner to retrieve the nonoce for. Address who signs a transaction (the signature creator)
    /// @return             returns the gswNonce for the owner necessary to sign a meta transaction
    function gswNonce(address owner) external view returns (uint256) {
        address gswAddress = gswFactory.computeAddress(owner);
        if (gswAddress.isContract()) {
            return IGaslessSmartWallet(gswAddress).gswNonce();
        }

        return 0;
    }

    /// @notice         Computes the deterministic address for owner based on Create2
    /// @param owner    GaslessSmartWallet owner
    /// @return         computed address for the contract
    function computeAddress(address owner) external view returns (address) {
        return gswFactory.computeAddress(owner);
    }

    /// @notice             Deploys GaslessSmartWallet for owner if necessary and calls `cast` on it.
    ///                     This method should be called by relayers.
    /// @param from         GaslessSmartWallet owner who signed the transaction (the signature creator)
    /// @param targets      the targets to execute the actions on
    /// @param datas        the data to be passed to the .call for each target
    /// @param values       the msg.value to be passed to the .call for each target. set to 0 if none
    /// @param signature    the EIP712 signature, should match keccak256(abi.encode(targets, datas, gswNonce, domainSeparatorV4()))
    ///                     see modifier validSignature
    /// @param validUntil   As EIP-2770: the highest block number the request can be forwarded in, or 0 if request validity is not time-limited
    ///                     Protects against relayers executing a certain transaction at a later moment not intended by the user, where it might
    ///                     have a completely different effect. (Given that the transaction is not executed right away for some reason)
    /// @param gas          As EIP-2770: an amount of gas limit to set for the execution
    ///                     Protects gainst potential gas griefing attacks / the relayer getting a reward without properly executing the tx completely
    ///                     See https://ronan.eth.limo/blog/ethereum-gas-dangers/
    function execute(
        address from,
        address[] calldata targets,
        bytes[] calldata datas,
        uint256[] calldata values,
        bytes calldata signature,
        uint256 validUntil,
        uint256 gas
    ) external payable {
        // gswFactory.deploy automatically checks if GSW has to be deployed
        // or if it already exists and simply returns the address in that case
        IGaslessSmartWallet gsw = IGaslessSmartWallet(gswFactory.deploy(from));

        gsw.cast{value: msg.value}(
            targets,
            datas,
            values,
            signature,
            validUntil,
            gas
        );
    }

    /// @notice             Verify the transaction is valid and can be executed.
    ///                     IMPORTANT: Expected to be called via callStatic
    ///                     Does not revert and returns successfully if the input is valid.
    ///                     Reverts if any validation has failed. For instance, if params or either signature or gswNonce are incorrect.
    /// @param from         GaslessSmartWallet owner who signed the transaction (the signature creator)
    /// @param targets      the targets to execute the actions on
    /// @param datas        the data to be passed to the .call for each target
    /// @param values       the msg.value to be passed to the .call for each target. set to 0 if none
    /// @param signature    the EIP712 signature, should match keccak256(abi.encode(targets, datas, gswNonce, domainSeparatorV4()))
    ///                     see modifier validSignature
    /// @param validUntil   As EIP-2770: the highest block number the request can be forwarded in, or 0 if request validity is not time-limited
    ///                     Protects against relayers executing a certain transaction at a later moment not intended by the user, where it might
    ///                     have a completely different effect. (Given that the transaction is not executed right away for some reason)
    /// @param gas          As EIP-2770: an amount of gas limit to set for the execution
    ///                     Protects gainst potential gas griefing attacks / the relayer getting a reward without properly executing the tx completely
    ///                     See https://ronan.eth.limo/blog/ethereum-gas-dangers/
    /// @return             returns true if everything is valid, otherwise reverts
    /// @dev                not marked as view because it does potentially state by deploying the GaslessSmartWallet for "from" if it does not exist yet.
    ///                     Expected to be called via callStatic
    function verify(
        address from,
        address[] calldata targets,
        bytes[] calldata datas,
        uint256[] calldata values,
        bytes calldata signature,
        uint256 validUntil,
        uint256 gas
    ) external returns (bool) {
        // gswFactory.deploy automatically checks if GSW has to be deployed
        // or if it already exists and simply returns the address
        IGaslessSmartWallet gsw = IGaslessSmartWallet(gswFactory.deploy(from));

        return gsw.verify(targets, datas, values, signature, validUntil, gas);
    }
}

